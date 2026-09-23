#!/bin/bash
# Apply generated agent model config to opencode.jsonc
# Reads generate-agent-config.sh output and patches model fields
# Safe: only modifies "model" fields in sdd-*-free-models agents

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

# One jq pass sets every agent model field plus the top-level model.
jq --argjson updates "$updates" \
   --arg top "$top_model" \
   --argjson set_top "$set_top" '
    reduce ($updates | to_entries[]) as $e (. ;
        .agent[$e.key].model = $e.value)
    | if $set_top then .model = $top else . end
' "$OPENCODE_CONFIG" > "$patched_file"

jq -r '.agents | to_entries[] | select(.value.model != "NONE")
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
