#!/bin/bash
# Model Selector — Privacy-Aware Model Assignment
# Reads user's privacy tier from .privacy-config and selects
# the best models for each Gentle-AI role within that tier.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/.privacy-config"
REGISTRY_FILE="$SCRIPT_DIR/privacy-tier-registry.json"
RESULTS_DIR="$SCRIPT_DIR/results"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ============================================================
# Config loading
# ============================================================

if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}Error: No privacy configuration found.${NC}"
    echo "Run ./privacy-setup.sh first to set your privacy preferences."
    exit 1
fi

source "$CONFIG_FILE"
PRIVACY_TIER="$privacy_max_tier"

if [ -z "$PRIVACY_TIER" ]; then
    echo -e "${RED}Error: Invalid configuration file.${NC}"
    exit 1
fi

if [ ! -f "$REGISTRY_FILE" ]; then
    echo -e "${RED}Error: privacy-tier-registry.json not found.${NC}"
    exit 1
fi

# ============================================================
# Core functions
# ============================================================

get_models_at_or_below_tier() {
    local max_tier=$1
    jq -r ".models | to_entries[] | select(
        (.value.privacy_tier | split(\"_\")[0] | tonumber) <= $max_tier
    ) | .key" "$REGISTRY_FILE" 2>/dev/null
}

get_model_info() {
    local model_id=$1
    local field=$2
    jq -r ".models[\"$model_id\"].$field // \"\"" "$REGISTRY_FILE" 2>/dev/null
}

get_model_tier() {
    local model_id=$1
    jq -r ".models[\"$model_id\"].privacy_tier // \"unknown\"" "$REGISTRY_FILE" 2>/dev/null
}

get_model_tier_num() {
    local model_id=$1
    local tier=$(get_model_tier "$model_id")
    echo "$tier" | cut -d'_' -f1
}

# ============================================================
# Role-based model selection (within privacy tier)
# ============================================================

select_best_for_role() {
    local role=$1
    local max_tier=$2
    
    # Role preferences: model IDs ordered by suitability for each role
    # If a model is excluded by tier, we fall through to the next best
    case $role in
        orchestrator)
            candidates=("opencode/mimo-v2.5-free" "opencode/nemotron-3-ultra-free" "opencode/big-pickle")
            ;;
        explore|research)
            candidates=("opencode/nemotron-3-ultra-free" "opencode/mimo-v2.5-free" "opencode/big-pickle")
            ;;
        design)
            candidates=("opencode/mimo-v2.5-free" "opencode/nemotron-3-ultra-free" "opencode/big-pickle")
            ;;
        spec|tasks|archive|documentation)
            candidates=("opencode/ling-3.0-flash-fin-free" "opencode/nemotron-3.5-lightning-free" "opencode/mimo-v2.5-free")
            ;;
        apply|code_generation)
            candidates=("opencode/big-pickle" "opencode/mimo-v2.5-free" "opencode/nemotron-3.5-lightning-free")
            ;;
        verify|quick_checks)
            candidates=("opencode/nemotron-3.5-lightning-free" "opencode/nemotron-3-ultra-free" "opencode/ling-3.0-flash-fin-free")
            ;;
        *)
            # Generic: return first available
            candidates=("opencode/mimo-v2.5-free" "opencode/nemotron-3-ultra-free" "opencode/big-pickle")
            ;;
    esac
    
    # Find first candidate that fits within tier
    for model in "${candidates[@]}"; do
        local model_tier=$(get_model_tier_num "$model")
        if [ "$model_tier" -le "$max_tier" ] 2>/dev/null; then
            echo "$model"
            return 0
        fi
    done
    
    # Fallback: return any available model at tier
    local first_available=$(get_models_at_or_below_tier "$max_tier" | head -1)
    if [ -n "$first_available" ]; then
        echo "$first_available"
        return 0
    fi
    
    echo "NONE"
    return 1
}

# ============================================================
# Output modes
# ============================================================

show_summary() {
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║     Model Assignment — Privacy Tier $PRIVACY_TIER                     ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Count available models
    local total_models=$(jq '.models | length' "$REGISTRY_FILE")
    local available_count=$(get_models_at_or_below_tier "$PRIVACY_TIER" | wc -l)
    local excluded_count=$((total_models - available_count))
    
    echo -e "  Privacy tier: ${CYAN}$PRIVACY_TIER${NC}"
    echo -e "  Models available: ${GREEN}$available_count${NC} / $total_models"
    if [ "$excluded_count" -gt 0 ]; then
        echo -e "  Models excluded: ${RED}$excluded_count${NC} (privacy policy above your tier)"
    fi
    echo ""
    
    echo -e "${BOLD}  Recommended assignments:${NC}"
    echo "  ┌────────────────────┬──────────────────────────────────────────┐"
    printf "  │ %-18s │ %-40s │\n" "Role" "Model"
    echo "  ├────────────────────┼──────────────────────────────────────────┤"
    
    local roles=("orchestrator" "explore" "design" "spec" "tasks" "apply" "verify" "archive")
    local role_labels=("Orchestrator" "sdd-explore" "sdd-design" "sdd-spec" "sdd-tasks" "sdd-apply" "sdd-verify" "sdd-archive")
    
    for i in "${!roles[@]}"; do
        local role="${roles[$i]}"
        local label="${role_labels[$i]}"
        local model=$(select_best_for_role "$role" "$PRIVACY_TIER")
        
        if [ "$model" = "NONE" ]; then
            printf "  │ %-18s │ ${RED}%-40s${NC} │\n" "$label" "NO MODEL AVAILABLE"
        else
            local name=$(get_model_info "$model" "name")
            local tier_num=$(get_model_tier_num "$model")
            local tier_color="$GREEN"
            if [ "$tier_num" -ge 3 ]; then tier_color="$YELLOW"; fi
            if [ "$tier_num" -ge 4 ]; then tier_color="$RED"; fi
            printf "  │ %-18s │ %-30s ${tier_color}T$tier_num${NC}     │\n" "$label" "$name"
        fi
    done
    
    echo "  └────────────────────┴──────────────────────────────────────────┘"
    echo ""
    
    # Show tier legend
    echo -e "  ${DIM}Tier legend: T1=Strict T2=Anonymous T3=Model-Improve T4=Explicit-Train${NC}"
    echo ""
}

show_machine_output() {
    # Machine-readable output for scripts
    local role=$1
    if [ -n "$role" ]; then
        local model=$(select_best_for_role "$role" "$PRIVACY_TIER")
        echo "$model"
    else
        # Output all assignments as JSON
        echo "{"
        echo "  \"privacy_tier\": $PRIVACY_TIER,"
        echo "  \"assignments\": {"
        local roles=("orchestrator" "explore" "design" "spec" "tasks" "apply" "verify" "archive")
        local first=true
        for role in "${roles[@]}"; do
            local model=$(select_best_for_role "$role" "$PRIVACY_TIER")
            if [ "$first" = true ]; then first=false; else echo ","; fi
            printf "    \"%s\": \"%s\"" "$role" "$model"
        done
        echo ""
        echo "  }"
        echo "}"
    fi
}

show_list() {
    echo -e "${BOLD}Available models (tier ≤ $PRIVACY_TIER):${NC}"
    echo ""
    while IFS= read -r model_id; do
        if [ -n "$model_id" ]; then
            local name=$(get_model_info "$model_id" "name")
            local provider=$(get_model_info "$model_id" "provider")
            local tier_num=$(get_model_tier_num "$model_id")
            local tier_color="$GREEN"
            if [ "$tier_num" -ge 3 ]; then tier_color="$YELLOW"; fi
            if [ "$tier_num" -ge 4 ]; then tier_color="$RED"; fi
            echo -e "  ${tier_color}[$tier_num]${NC} $name ($provider)"
            echo -e "       ${DIM}$model_id${NC}"
        fi
    done < <(get_models_at_or_below_tier "$PRIVACY_TIER")
    echo ""
}

show_excluded() {
    echo -e "${BOLD}Excluded models (tier > $PRIVACY_TIER):${NC}"
    echo ""
    while IFS= read -r model_id; do
        if [ -n "$model_id" ]; then
            local name=$(get_model_info "$model_id" "name")
            local provider=$(get_model_info "$model_id" "provider")
            local tier=$(get_model_tier "$model_id")
            local evidence=$(get_model_info "$model_id" "evidence")
            echo -e "  ${RED}✗${NC} $name ($provider)"
            echo -e "    ${DIM}Privacy tier: $tier${NC}"
            echo -e "    ${DIM}${evidence:0:120}...${NC}"
            echo ""
        fi
    done < <(jq -r ".models | to_entries[] | select(
        (.value.privacy_tier | split(\"_\")[0] | tonumber) > $PRIVACY_TIER
    ) | .key" "$REGISTRY_FILE" 2>/dev/null)
}

show_gentleai_profile() {
    # Output a gentle-ai compatible profile based on privacy tier
    local orchestrator=$(select_best_for_role "orchestrator" "$PRIVACY_TIER")
    local explore=$(select_best_for_role "explore" "$PRIVACY_TIER")
    local apply=$(select_best_for_role "apply" "$PRIVACY_TIER")
    local verify=$(select_best_for_role "verify" "$PRIVACY_TIER")
    
    echo "# Gentle-AI Profile (Privacy Tier $PRIVACY_TIER)"
    echo "# Generated by model-selector.sh"
    echo ""
    echo "gentle-ai sync --profile free-models:$orchestrator \\"
    echo "  --profile-phase free-models:sdd-explore:$explore \\"
    echo "  --profile-phase free-models:sdd-apply:$apply \\"
    echo "  --profile-phase free-models:sdd-verify:$verify"
}

# ============================================================
# CLI
# ============================================================

usage() {
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  (none)        Show summary of model assignments for your privacy tier"
    echo "  list          List all available models at your tier"
    echo "  excluded      List models excluded by your privacy tier"
    echo "  role ROLE     Get the best model for a specific role"
    echo "  all           Output all assignments as JSON"
    echo "  profile       Output a gentle-ai sync command for your tier"
    echo ""
    echo "Examples:"
    echo "  $0                  # Show assignment summary"
    echo "  $0 role apply       # Get best model for sdd-apply"
    echo "  $0 profile          # Get gentle-ai profile command"
    echo "  $0 list             # List available models"
}

case "${1:-}" in
    "")
        show_summary
        ;;
    list)
        show_list
        ;;
    excluded)
        show_excluded
        ;;
    role)
        if [ -z "${2:-}" ]; then
            echo -e "${RED}Error: specify a role (orchestrator, explore, design, spec, tasks, apply, verify, archive)${NC}"
            exit 1
        fi
        model=$(select_best_for_role "$2" "$PRIVACY_TIER")
        if [ "$model" = "NONE" ]; then
            echo -e "${RED}No model available for role '$2' at privacy tier $PRIVACY_TIER${NC}"
            exit 1
        fi
        name=$(get_model_info "$model" "name")
        echo "$model"
        ;;
    all)
        show_machine_output
        ;;
    profile)
        show_gentleai_profile
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        echo -e "${RED}Unknown command: $1${NC}"
        usage
        exit 1
        ;;
esac
