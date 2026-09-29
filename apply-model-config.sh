#!/bin/bash
# Apply generated agent model config to opencode.jsonc
# Reads generate-agent-config.sh output and patches model fields
# Safe: only modifies "model" fields in agents the target config already
# declares — it never creates an agent, and it refuses to write at all when
# none of the generated agents are present.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENCODE_CONFIG="${OPENCODE_CONFIG:-$HOME/.config/opencode/opencode.jsonc}"

# ─── Dependencies ───────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
    echo "Error: jq is required. Install with: sudo apt install jq" >&2
    exit 1
fi

if [ ! -f "$OPENCODE_CONFIG" ]; then
    echo "Error: opencode.jsonc not found at $OPENCODE_CONFIG" >&2
    exit 1
fi

# ─── Temps + cleanup ────────────────────────────────────────────────────────

# Both temps live next to their targets' filesystems (patched_file next to
# OPENCODE_CONFIG) so mv stays a same-filesystem rename. The EXIT trap
# guarantees neither leaks, on any exit path.
config_file=$(mktemp)
patched_file=$(mktemp "${OPENCODE_CONFIG}.tmp.XXXXXX")
trap 'rm -f "$config_file" "$patched_file"' EXIT

# ─── Generate agent config ──────────────────────────────────────────────────

echo "Generating model assignments..."
"$SCRIPT_DIR/generate-agent-config.sh" > "$config_file" 2>/dev/null

if [ ! -s "$config_file" ]; then
    echo "Error: generate-agent-config.sh produced empty output" >&2
    exit 1
fi

# Show what we're about to apply
echo ""
echo "Current assignments:"
jq -r '.agents | to_entries[] | "  \(.key) → \(.value.name) (\(.value.model))"' "$config_file"

# ─── Guard: only patch agents the config already declares ────────────────────

# `.agent[$e.key].model = $e.value` auto-vivifies in jq, so a config with no
# `.agent` key would silently gain model-only stubs for every agent — and the
# script would still print "updated successfully". Resolve the intersection of
# the generated names with the target's real `.agent` keys BEFORE any write:
# never create an agent, never touch a file that declares none of them.
#
# Assumption (unchanged): the target is .jsonc but read straight by jq, so it
# carries no comments. A comment parser stays out of scope here — see
# check-upstream.sh for the one place that tolerates them.
if ! jq empty "$OPENCODE_CONFIG" 2>/dev/null; then
    echo "ERROR: $OPENCODE_CONFIG is not valid JSON for jq." >&2
    echo "  This tool reads opencode.jsonc with jq, so comments in the file break the read." >&2
    exit 1
fi

existing_json=$(jq -c '.agent // {} | keys' "$OPENCODE_CONFIG")
existing_agents=$(jq -r '.[]' <<<"$existing_json")
intended_count=$(jq -r '.agents | length' "$config_file")

missing_agents=""
present_count=0
while IFS= read -r agent; do
    [ -n "$agent" ] || continue
    if printf '%s\n' "$existing_agents" | grep -qxF "$agent"; then
        present_count=$((present_count + 1))
    else
        missing_agents+="$agent"$'\n'
    fi
done <<< "$(jq -r '.agents | keys[]' "$config_file")"

if [ "$present_count" -eq 0 ]; then
    echo "" >&2
    echo "ERROR: none of the $intended_count generated agents exist in $OPENCODE_CONFIG." >&2
    echo "  The file declares no matching .agent keys — what a fresh OpenCode install or a" >&2
    echo "  non-Gentle-AI setup looks like. Patching it would fabricate agents this config" >&2
    echo "  never had, so nothing was written (not the agents, not the top-level model)." >&2
    echo "  Add the agents to opencode.jsonc first, then re-run." >&2
    exit 1
fi

# Agents the target does not declare are reported and never patched. NONE
# agents get their own line below; those are skipped for a different reason
# (no eligible model), so they are not repeated here.
if [ -n "$missing_agents" ]; then
    echo ""
    echo "  ⚠ Skipping agent(s) not declared in $OPENCODE_CONFIG:"
    while IFS= read -r agent; do
        [ -n "$agent" ] || continue
        if jq -e --arg a "$agent" '.agents[$a].model != "NONE"' "$config_file" >/dev/null; then
            echo "    ⚠ $agent"
        fi
    done <<<"$missing_agents"
fi

# ─── Backup current config ──────────────────────────────────────────────────

BACKUP="$OPENCODE_CONFIG.pre-free-models-backup"
if [ ! -f "$BACKUP" ]; then
    cp "$OPENCODE_CONFIG" "$BACKUP"
    echo ""
    echo "Backup created: $BACKUP"
fi

# ─── Patch opencode.jsonc (single jq pass) ──────────────────────────────────

# Agents without a model are reported and never patched.
jq -r '.agents | to_entries[] | select(.value.model == "NONE")
    | "  ⚠ No model available for \(.key) — skipping"' "$config_file"

# Update object: agent name → model (NONE entries excluded).
updates=$(jq -c '.agents
    | with_entries(select(.value.model != "NONE") | .value = .value.model)' "$config_file")

# Top-level default model so unpinned agents (and OpenCode's
# session default) never fall back to a local LLM.
top_model=$(jq -r '._meta.top_level_model // empty' "$config_file")
set_top=false
if [ -n "$top_model" ] && [ "$top_model" != "NONE" ]; then
    set_top=true
fi

# One jq pass sets every EXISTING agent model field plus the top-level model.
# $existing gates the assignment: an undeclared key would be auto-vivified, so
# it is filtered out here rather than trusted.
jq --argjson updates "$updates" \
   --argjson existing "$existing_json" \
   --arg top "$top_model" \
   --argjson set_top "$set_top" '
    reduce ($updates | to_entries[] | select(.key as $k | $existing | index($k))) as $e (. ;
        .agent[$e.key].model = $e.value)
    | if $set_top then .model = $top else . end
' "$OPENCODE_CONFIG" > "$patched_file"

jq -r --argjson existing "$existing_json" '
    .agents | to_entries[]
    | select(.value.model != "NONE")
    | select(.key as $k | $existing | index($k))
    | "  ✓ \(.key) → \(.value.model)"' "$config_file"
if [ "$set_top" = true ]; then
    echo "  ✓ top-level model → $top_model"
else
    echo "  ⚠ top_level_model missing — leaving top-level model unchanged"
fi

# ─── Validate and apply ─────────────────────────────────────────────────────

if jq empty "$patched_file" 2>/dev/null; then
    mv "$patched_file" "$OPENCODE_CONFIG"
    echo ""
    echo "✓ opencode.jsonc updated successfully"
else
    echo "ERROR: Patched config failed JSON validation. Original preserved." >&2
    exit 1
fi

# ─── Summary ────────────────────────────────────────────────────────────────

tier=$(jq -r '._meta.privacy_tier' "$config_file" 2>/dev/null || echo "?")

echo ""
echo "Model config applied (tier $tier). Changes take effect on next OpenCode session restart."
echo "To restore: cp $BACKUP $OPENCODE_CONFIG"
