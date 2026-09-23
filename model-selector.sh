#!/bin/bash
# Model Selector — Privacy-Aware Model Assignment
# Reads user's privacy tier from .privacy-config and selects
# the best models for each Gentle-AI role within that tier.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/.privacy-config"
REGISTRY_FILE="$SCRIPT_DIR/privacy-tier-registry.json"
RESULTS_DIR="$SCRIPT_DIR/results"

# Shared registry-driven role selection (load_privacy_tier, select_role_model)
source "$SCRIPT_DIR/select-role-model.sh"

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

load_privacy_tier

if [ -z "$PRIVACY_TIER" ]; then
    echo -e "${RED}Error: Invalid configuration file.${NC}"
    exit 1
fi

if [ ! -f "$REGISTRY_FILE" ]; then
    echo -e "${RED}Error: privacy-tier-registry.json not found.${NC}"
    exit 1
fi

# ============================================================
# Role-based model selection (within privacy tier)
# — provided by select-role-model.sh (select_role_model)
# ============================================================

# ============================================================
# Output modes
# ============================================================

show_summary() {
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║     Model Assignment — Privacy Tier $PRIVACY_TIER                     ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # One jq pass: load name/tier for every model, count available at tier.
    local total_models=0 available_count=0
    local -A MODEL_NAMES MODEL_TIERS
    while IFS='|' read -r mid mname mtier; do
        [ -n "$mid" ] || continue
        MODEL_NAMES["$mid"]="$mname"
        MODEL_TIERS["$mid"]="$mtier"
        total_models=$((total_models + 1))
        if [ "$mtier" -le "$PRIVACY_TIER" ] 2>/dev/null; then
            available_count=$((available_count + 1))
        fi
    done < <(jq -r '.models | to_entries[]
        | [.key,
           (.value.name // .key),
           ((.value.privacy_tier // "4" | tostring | split("_")[0]))]
        | join("|")' "$REGISTRY_FILE" 2>/dev/null)
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
        local model=$(select_role_model "$role" "$PRIVACY_TIER")
        
        if [ "$model" = "NONE" ]; then
            printf "  │ %-18s │ ${RED}%-40s${NC} │\n" "$label" "NO MODEL AVAILABLE"
        else
            local name="${MODEL_NAMES[$model]:-$model}"
            local tier_num="${MODEL_TIERS[$model]:-4}"
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
    # Machine-readable output for scripts: all assignments as JSON.
    # (No single-role branch: the only caller invokes this with no args.)
    echo "{"
    echo "  \"privacy_tier\": $PRIVACY_TIER,"
    echo "  \"assignments\": {"
    local roles=("orchestrator" "explore" "design" "spec" "tasks" "apply" "verify" "archive")
    local first=true
    for role in "${roles[@]}"; do
        local model=$(select_role_model "$role" "$PRIVACY_TIER")
        if [ "$first" = true ]; then first=false; else echo ","; fi
        printf "    \"%s\": \"%s\"" "$role" "$model"
    done
    echo ""
    echo "  }"
    echo "}"
}

show_list() {
    echo -e "${BOLD}Available models (tier ≤ $PRIVACY_TIER):${NC}"
    echo ""
    # Single jq emits every field the listing needs (id|name|provider|tier).
    while IFS='|' read -r model_id name provider tier_num; do
        [ -n "$model_id" ] || continue
        local tier_color="$GREEN"
        if [ "$tier_num" -ge 3 ]; then tier_color="$YELLOW"; fi
        if [ "$tier_num" -ge 4 ]; then tier_color="$RED"; fi
        echo -e "  ${tier_color}[$tier_num]${NC} $name ($provider)"
        echo -e "       ${DIM}$model_id${NC}"
    done < <(jq -r --arg max "$PRIVACY_TIER" '
        .models | to_entries[]
        | ((.value.privacy_tier // "4" | tostring | split("_")[0] | tonumber? // 4)) as $t
        | select($t <= ($max | tonumber))
        | [.key,
           (.value.name // .key),
           (.value.provider // "Unknown"),
           ($t | tostring)]
        | join("|")' "$REGISTRY_FILE" 2>/dev/null)
    echo ""
}

show_excluded() {
    echo -e "${BOLD}Excluded models (tier > $PRIVACY_TIER):${NC}"
    echo ""
    # Single jq emits id|name|provider|full tier|evidence (last field keeps
    # any embedded "|" via read's remainder assignment).
    while IFS='|' read -r model_id name provider tier evidence; do
        [ -n "$model_id" ] || continue
        echo -e "  ${RED}✗${NC} $name ($provider)"
        echo -e "    ${DIM}Privacy tier: $tier${NC}"
        echo -e "    ${DIM}${evidence:0:120}...${NC}"
        echo ""
    done < <(jq -r --arg max "$PRIVACY_TIER" '
        .models | to_entries[]
        | ((.value.privacy_tier // "4" | tostring | split("_")[0] | tonumber? // 4)) as $t
        | select($t > ($max | tonumber))
        | [.key,
           (.value.name // .key),
           (.value.provider // "Unknown"),
           (.value.privacy_tier // "unknown"),
           (.value.evidence // "")]
        | join("|")' "$REGISTRY_FILE" 2>/dev/null)
}

show_gentleai_profile() {
    # Output a gentle-ai compatible profile based on privacy tier
    local orchestrator=$(select_role_model "orchestrator" "$PRIVACY_TIER")
    local explore=$(select_role_model "explore" "$PRIVACY_TIER")
    local apply=$(select_role_model "apply" "$PRIVACY_TIER")
    local verify=$(select_role_model "verify" "$PRIVACY_TIER")
    
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
        model=$(select_role_model "$2" "$PRIVACY_TIER")
        if [ "$model" = "NONE" ]; then
            echo -e "${RED}No model available for role '$2' at privacy tier $PRIVACY_TIER${NC}"
            exit 1
        fi
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
