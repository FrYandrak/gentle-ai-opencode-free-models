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

# ─── Generate agent config ──────────────────────────────────────────────────

echo "Generating model assignments..."
config_file=$(mktemp)
"$SCRIPT_DIR/generate-agent-config.sh" > "$config_file" 2>/dev/null

if [ ! -s "$config_file" ]; then
    echo "Error: generate-agent-config.sh produced empty output" >&2
    rm -f "$config_file"
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

# ─── Patch opencode.jsonc ───────────────────────────────────────────────────

# For each agent in the generated config, set the model field in opencode.jsonc
TMPFILE=$(mktemp)
cp "$OPENCODE_CONFIG" "$TMPFILE"

jq -r '.agents | to_entries[] | "\(.key)|\(.value.model)"' "$config_file" | while IFS='|' read -r agent_name model; do
    if [ "$model" = "NONE" ]; then
        echo "  ⚠ No model available for $agent_name — skipping"
        continue
    fi

    # Patch the model field for this agent
    jq ".agent[\"$agent_name\"].model = \"$model\"" "$TMPFILE" > "$TMPFILE.tmp" && mv "$TMPFILE.tmp" "$TMPFILE"
    echo "  ✓ $agent_name → $model"
done

# Patch top-level default model so unpinned agents (and OpenCode's
# session default) never fall back to a local LLM.
top_model=$(jq -r '._meta.top_level_model // empty' "$config_file")
if [ -n "$top_model" ] && [ "$top_model" != "NONE" ]; then
    jq ".model = \"$top_model\"" "$TMPFILE" > "$TMPFILE.tmp" && mv "$TMPFILE.tmp" "$TMPFILE"
    echo "  ✓ top-level model → $top_model"
else
    echo "  ⚠ top_level_model missing — leaving top-level model unchanged"
fi

# ─── Validate and apply ─────────────────────────────────────────────────────

if jq empty "$TMPFILE" 2>/dev/null; then
    mv "$TMPFILE" "$OPENCODE_CONFIG"
    echo ""
    echo "✓ opencode.jsonc updated successfully"
else
    echo "ERROR: Patched config failed JSON validation. Original preserved." >&2
    rm -f "$TMPFILE"
    rm -f "$config_file"
    exit 1
fi

# ─── Summary ────────────────────────────────────────────────────────────────

tier=$(jq -r '._meta.privacy_tier' "$config_file" 2>/dev/null || echo "?")
rm -f "$config_file"

echo ""
echo "Model config applied (tier $tier). Changes take effect on next OpenCode session restart."
echo "To restore: cp $BACKUP $OPENCODE_CONFIG"
