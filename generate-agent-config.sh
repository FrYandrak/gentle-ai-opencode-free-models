#!/bin/bash
# Generate OpenCode agent model assignments from privacy tier + registry
# Output: JSON snippet with "model" field for each sdd-*-free-models agent
# Used by apply-model-config.sh to patch opencode.jsonc

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/.privacy-config"
REGISTRY_FILE="$SCRIPT_DIR/privacy-tier-registry.json"

# Shared registry-driven role selection (load_privacy_tier, select_role_model)
source "$SCRIPT_DIR/select-role-model.sh"

# ─── Load privacy tier ──────────────────────────────────────────────────────

if [ ! -f "$CONFIG_FILE" ]; then
    echo '{"error": "No .privacy-config found. Run ./privacy-setup.sh first."}' >&2
    exit 1
fi

load_privacy_tier
TIER="$PRIVACY_TIER"

if [ -z "$TIER" ]; then
    echo '{"error": "Invalid .privacy-config: privacy_max_tier is empty."}' >&2
    exit 1
fi

# ─── Generate agent config ──────────────────────────────────────────────────

# Map agent name suffix → role for model selection.
# Only non-identity mappings live here: the ${AGENT_ROLES[$suffix]:-$suffix}
# fallback already handles every suffix that equals its own role name.
declare -A AGENT_ROLES=(
    ["init"]="spec"
    ["onboard"]="orchestrator"
    ["propose"]="design"
)

# Agent names that exist in opencode.jsonc as sdd-*-free-models
AGENT_NAMES=(
    "gentle-orchestrator"
    "sdd-orchestrator-free-models"
    "sdd-explore-free-models"
    "sdd-research-free-models"
    "sdd-design-free-models"
    "sdd-spec-free-models"
    "sdd-tasks-free-models"
    "sdd-apply-free-models"
    "sdd-verify-free-models"
    "sdd-archive-free-models"
    "sdd-init-free-models"
    "sdd-onboard-free-models"
    "sdd-propose-free-models"
)

# Also emit the top-level default model (used by agents that do not pin one)
orchestrator_model=$(select_role_model "orchestrator" "$TIER")
if [ -z "$orchestrator_model" ] || [ "$orchestrator_model" = "NONE" ]; then
    orchestrator_model="opencode/big-pickle"
fi

# Build JSON output
echo "{"
echo "  \"_meta\": {"
echo "    \"generated_by\": \"generate-agent-config.sh\","
echo "    \"privacy_tier\": $TIER,"
echo "    \"generated_at\": \"$(date -Iseconds)\","
echo "    \"top_level_model\": \"$orchestrator_model\""
echo "  },"
echo "  \"agents\": {"

first=true
for agent_name in "${AGENT_NAMES[@]}"; do
    # Extract role suffix (gentle-orchestrator → orchestrator; sdd-explore-free-models → explore)
    if [ "$agent_name" = "gentle-orchestrator" ]; then
        role="orchestrator"
    else
        suffix="${agent_name#sdd-}"
        suffix="${suffix%-free-models}"
        role="${AGENT_ROLES[$suffix]:-$suffix}"
    fi

    model=$(select_role_model "$role" "$TIER")

    if [ -z "$model" ]; then
        model="NONE"
    fi

    # Get model display name
    name=$(jq -r ".models[\"$model\"].name // \"$model\"" "$REGISTRY_FILE" 2>/dev/null)

    if [ "$first" = true ]; then first=false; else echo ","; fi
    printf '    "%s": { "model": "%s", "name": "%s", "role": "%s" }' \
        "$agent_name" "$model" "$name" "$role"
done

echo ""
echo "  }"
echo "}"
