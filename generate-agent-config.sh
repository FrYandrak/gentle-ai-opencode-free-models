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

    # Every chain ends with opencode/big-pickle as the designated fallout.
    case $role in
        orchestrator) candidates=("opencode/mimo-v2.5-free" "opencode/mimo-v2.6-flash-free" "opencode/nemotron-3-ultra-free" "opencode/big-pickle") ;;
        explore)      candidates=("opencode/nemotron-3-ultra-free" "opencode/mimo-v2.5-free" "opencode/mimo-v2.6-flash-free" "opencode/big-pickle") ;;
        design)       candidates=("opencode/mimo-v2.5-free" "opencode/mimo-v2.6-flash-free" "opencode/nemotron-3-ultra-free" "opencode/big-pickle") ;;
        spec)         candidates=("opencode/ling-3.0-flash-fin-free" "opencode/nemotron-3.5-lightning-free" "opencode/mimo-v2.5-free" "opencode/mimo-v2.6-flash-free" "opencode/big-pickle") ;;
        tasks)        candidates=("opencode/ling-3.0-flash-fin-free" "opencode/nemotron-3.5-lightning-free" "opencode/mimo-v2.5-free" "opencode/mimo-v2.6-flash-free" "opencode/big-pickle") ;;
        apply)        candidates=("opencode/mimo-v2.5-free" "opencode/mimo-v2.6-flash-free" "opencode/nemotron-3.5-lightning-free" "opencode/big-pickle") ;;
        verify)       candidates=("opencode/nemotron-3.5-lightning-free" "opencode/nemotron-3-ultra-free" "opencode/ling-3.0-flash-fin-free" "opencode/mimo-v2.6-flash-free" "opencode/big-pickle") ;;
        archive)      candidates=("opencode/ling-3.0-flash-fin-free" "opencode/nemotron-3.5-lightning-free" "opencode/mimo-v2.5-free" "opencode/mimo-v2.6-flash-free" "opencode/big-pickle") ;;
        research)     candidates=("opencode/nemotron-3-ultra-free" "opencode/mimo-v2.5-free" "opencode/mimo-v2.6-flash-free" "opencode/big-pickle") ;;
        *)            candidates=("opencode/mimo-v2.5-free" "opencode/mimo-v2.6-flash-free" "opencode/nemotron-3-ultra-free" "opencode/big-pickle") ;;
    esac

    for model in "${candidates[@]}"; do
        local model_tier=$(jq -r ".models[\"$model\"].privacy_tier // \"99\"" "$REGISTRY_FILE" 2>/dev/null | cut -d'_' -f1)
        local exists=$(jq -r ".models[\"$model\"].name // \"\"" "$REGISTRY_FILE" 2>/dev/null)

        if [ -n "$exists" ] && [ "$model_tier" -le "$max_tier" ] 2>/dev/null; then
            echo "$model"
            return 0
        fi
    done

    # Designated fallout: Big Pickle if still within privacy tier
    local bp_tier=$(jq -r '.models["opencode/big-pickle"].privacy_tier // "99"' "$REGISTRY_FILE" 2>/dev/null | cut -d'_' -f1)
    if [ -n "$bp_tier" ] && [ "$bp_tier" -le "$max_tier" ] 2>/dev/null; then
        echo "opencode/big-pickle"
        return 0
    fi

    # Last resort: first available model at tier
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
orchestrator_model=$(select_model_for_role "orchestrator" "$TIER")
if [ -z "$orchestrator_model" ]; then
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
