#!/bin/bash
# Generate OpenCode agent model assignments from privacy tier + registry
# Output: JSON snippet with "model" field for each sdd-*-free-models agent
# Used by apply-model-config.sh to patch opencode.jsonc

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/.privacy-config"
REGISTRY_FILE="$SCRIPT_DIR/privacy-tier-registry.json"

# ─── Load privacy tier ──────────────────────────────────────────────────────

if [ ! -f "$CONFIG_FILE" ]; then
    echo '{"error": "No .privacy-config found. Run ./privacy-setup.sh first."}' >&2
    exit 1
fi

source "$CONFIG_FILE"
TIER="$privacy_max_tier"

if [ -z "$TIER" ]; then
    echo '{"error": "Invalid .privacy-config: privacy_max_tier is empty."}' >&2
    exit 1
fi

# ─── Model selection logic (same as model-selector.sh) ──────────────────────

select_model_for_role() {
    local role=$1
    local max_tier=$2

    case $role in
        orchestrator) candidates=("opencode/mimo-v2.5-free" "opencode/nemotron-3-ultra-free" "opencode/deepseek-v4-flash-free") ;;
        explore)      candidates=("opencode/nemotron-3-ultra-free" "opencode/mimo-v2.5-free" "opencode/deepseek-v4-flash-free") ;;
        design)       candidates=("opencode/mimo-v2.5-free" "opencode/nemotron-3-ultra-free" "opencode/deepseek-v4-flash-free") ;;
        spec)         candidates=("opencode/ling-3.0-flash-fin-free" "opencode/nemotron-3.5-lightning-free" "opencode/deepseek-v4-flash-free") ;;
        tasks)        candidates=("opencode/ling-3.0-flash-fin-free" "opencode/nemotron-3.5-lightning-free" "opencode/deepseek-v4-flash-free") ;;
        apply)        candidates=("opencode/deepseek-v4-flash-free" "opencode/nemotron-3.5-lightning-free" "opencode/ling-3.0-flash-fin-free") ;;
        verify)       candidates=("opencode/nemotron-3.5-lightning-free" "opencode/nemotron-3-ultra-free" "opencode/ling-3.0-flash-fin-free") ;;
        archive)      candidates=("opencode/ling-3.0-flash-fin-free" "opencode/nemotron-3.5-lightning-free" "opencode/deepseek-v4-flash-free") ;;
        research)     candidates=("opencode/nemotron-3-ultra-free" "opencode/mimo-v2.5-free" "opencode/deepseek-v4-flash-free") ;;
    esac

    for model in "${candidates[@]}"; do
        local model_tier=$(jq -r ".models[\"$model\"].privacy_tier // \"99\"" "$REGISTRY_FILE" 2>/dev/null | cut -d'_' -f1)
        local exists=$(jq -r ".models[\"$model\"].name // \"\"" "$REGISTRY_FILE" 2>/dev/null)

        if [ -n "$exists" ] && [ "$model_tier" -le "$max_tier" ] 2>/dev/null; then
            echo "$model"
            return 0
        fi
    done

    # Fallback: first available model at tier
    local fallback=$(jq -r ".models | to_entries[] | select(
        (.value.privacy_tier | split(\"_\")[0] | tonumber) <= $max_tier
    ) | .key" "$REGISTRY_FILE" 2>/dev/null | head -1)

    if [ -n "$fallback" ]; then
        echo "$fallback"
        return 0
    fi

    echo ""
    return 1
}

# ─── Generate agent config ──────────────────────────────────────────────────

# Map agent name suffix → role for model selection
declare -A AGENT_ROLES=(
    ["orchestrator"]="orchestrator"
    ["explore"]="explore"
    ["research"]="research"
    ["design"]="design"
    ["spec"]="spec"
    ["tasks"]="tasks"
    ["apply"]="apply"
    ["verify"]="verify"
    ["archive"]="archive"
    ["init"]="spec"
    ["onboard"]="orchestrator"
    ["propose"]="design"
)

# Agent names that exist in opencode.jsonc as sdd-*-free-models
AGENT_NAMES=(
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

# Build JSON output
echo "{"
echo "  \"_meta\": {"
echo "    \"generated_by\": \"generate-agent-config.sh\","
echo "    \"privacy_tier\": $TIER,"
echo "    \"generated_at\": \"$(date -Iseconds)\""
echo "  },"
echo "  \"agents\": {"

first=true
for agent_name in "${AGENT_NAMES[@]}"; do
    # Extract role suffix (e.g., sdd-explore-free-models → explore)
    suffix="${agent_name#sdd-}"
    suffix="${suffix%-free-models}"
    role="${AGENT_ROLES[$suffix]:-$suffix}"

    model=$(select_model_for_role "$role" "$TIER")

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
