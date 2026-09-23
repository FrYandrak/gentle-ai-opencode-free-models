#!/bin/bash
# Privacy-Aware Model Setup for Free Model Comparison
# First-time setup: asks user privacy preferences and stores them
# Can be re-run anytime to modify preferences

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/.privacy-config"
REGISTRY_FILE="$SCRIPT_DIR/privacy-tier-registry.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ============================================================
# Helper functions
# ============================================================

print_header() {
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║     Privacy-Aware Free Model Configuration              ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ============================================================
# Registry-derived counts and name lists (one jq per call — no
# hardcoded model counts or stale name lists)
# ============================================================

registry_total() {
    jq '.models | length' "$REGISTRY_FILE" 2>/dev/null || echo 0
}

_registry_query() {
    # $1 = comparison (le|gt|eq), $2 = tier number, $3 = jq output template
    jq -r --arg op "$1" --argjson t "$2" --arg out "$3" '
        [.models | to_entries[]
         | ((.value.privacy_tier // "4" | tostring | split("_")[0] | tonumber? // 4)) as $tier
         | select(
             if $op == "le" then $tier <= $t
             elif $op == "gt" then $tier > $t
             else $tier == $t end)
         | {tier: $tier, name: (.value.name // .key)}]
        | sort_by(.tier)
        | if $out == "count" then length
          else map(.name) | join(", ") end' "$REGISTRY_FILE" 2>/dev/null
}

registry_count_le() {
    _registry_query le "$1" count || echo 0
}

registry_count_eq() {
    _registry_query eq "$1" count || echo 0
}

registry_names_le() {
    _registry_query le "$1" names
}

registry_names_gt() {
    _registry_query gt "$1" names
}

registry_names_eq() {
    _registry_query eq "$1" names
}

print_tier_info() {
    local tier=$1
    local total avail_names lost_names avail_count tier4_names
    total=$(registry_total)
    avail_names=$(registry_names_le "$tier")
    lost_names=$(registry_names_gt "$tier")
    avail_count=$(registry_count_le "$tier")
    tier4_names=$(registry_names_eq 4)
    case $tier in
        1)
            echo -e "${GREEN}TIER 1 — Strict Privacy${NC}"
            echo "  No data used for training. Zero-retention."
            echo "  No logging for improvement."
            echo ""
            if [ -z "$avail_names" ]; then
                echo -e "  ${YELLOW}Available models: None (no free models meet strict privacy)${NC}"
            else
                echo -e "  ${YELLOW}Available models: ${avail_names}${NC}"
            fi
            echo -e "  ${YELLOW}⚠ You lose: ALL free models — ${lost_names}${NC}"
            ;;
        2)
            echo -e "${GREEN}TIER 2 — Anonymous Improvement Only${NC}"
            echo "  Data logged for service improvement, NOT linked to identity."
            echo "  No model training."
            echo ""
            echo -e "  ${YELLOW}Available models: ${avail_names}${NC}"
            echo -e "  ${YELLOW}⚠ You lose: ${lost_names} (higher-tier models)${NC}"
            ;;
        3)
            echo -e "${GREEN}TIER 3 — Model Improvement${NC}"
            echo "  Data may be used to improve the model during free period."
            echo "  Not linked to identity."
            echo ""
            echo -e "  ${YELLOW}Available models: ${avail_count} of ${total} — ${avail_names}${NC}"
            if [ -n "$lost_names" ]; then
                echo -e "  ${YELLOW}⚠ Excluded above your tier: ${lost_names}${NC}"
            fi
            ;;
        4)
            echo -e "${GREEN}TIER 4 — Accept All${NC}"
            echo "  All models available including those that train on your data."
            echo "  You explicitly accept that some providers use your prompts"
            echo "  and completions to train their models."
            echo ""
            echo -e "  ${YELLOW}Available models: ALL ${total} free models${NC}"
            echo -e "  ${YELLOW}⚠ Tier-4 models (explicit training or unknown privacy): ${tier4_names}${NC}"
            ;;
    esac
}

get_models_for_tier() {
    local max_tier=$1
    # One jq pass emits every field the listing loops need
    # (id|name|provider), ordered by tier.
    jq -r --arg max "$max_tier" '
        [.models | to_entries[]
         | ((.value.privacy_tier // "4" | tostring | split("_")[0] | tonumber? // 4)) as $t
         | select($t <= ($max | tonumber))
         | {tier: $t,
            id: .key,
            name: (.value.name // .key),
            provider: (.value.provider // "Unknown")}]
        | sort_by(.tier)
        | .[] | "\(.id)|\(.name)|\(.provider)"' "$REGISTRY_FILE" 2>/dev/null
}

save_config() {
    local tier=$1
    local timestamp=$(date -Iseconds)
    
    cat > "$CONFIG_FILE" << EOF
# Privacy Configuration for Free Model Comparison
# Generated by privacy-setup.sh
# DO NOT EDIT MANUALLY — run ./privacy-setup.sh to modify

privacy_max_tier=$tier
created_at=$timestamp
last_modified=$timestamp
version=1.0.0
EOF
    
    echo -e "${GREEN}✓ Configuration saved to $CONFIG_FILE${NC}"
}

show_current_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}No configuration found. First-time setup required.${NC}"
        return 1
    fi
    
    source "$CONFIG_FILE"
    
    echo -e "${BOLD}Current Configuration:${NC}"
    echo "  Privacy tier: $privacy_max_tier"
    echo "  Last modified: $last_modified"
    echo ""
    
    print_tier_info "$privacy_max_tier"
    
    echo -e "${BOLD}Models available at your tier:${NC}"
    local count=0
    while IFS='|' read -r model_id name provider; do
        if [ -n "$model_id" ]; then
            echo "  ✓ $name ($provider) — $model_id"
            count=$((count + 1))
        fi
    done < <(get_models_for_tier "$privacy_max_tier")
    echo ""
    echo "  Total: $count models available"
}

# ============================================================
# Main setup flow
# ============================================================

print_header

# Check if jq is available
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is required but not installed.${NC}"
    echo "Install with: sudo apt install jq"
    exit 1
fi

# Check if registry exists
if [ ! -f "$REGISTRY_FILE" ]; then
    echo -e "${RED}Error: privacy-tier-registry.json not found at $REGISTRY_FILE${NC}"
    exit 1
fi

# Check if config already exists
if [ -f "$CONFIG_FILE" ]; then
    echo -e "${CYAN}Existing configuration detected.${NC}"
    echo ""
    show_current_config
    echo ""
    echo -e "${BOLD}What would you like to do?${NC}"
    echo "  1) Keep current settings"
    echo "  2) Change privacy tier"
    echo "  3) View all models and their privacy details"
    echo "  4) Exit"
    echo ""
    read -p "Select option [1-4]: " choice
    
    case $choice in
        1)
            echo -e "${GREEN}Keeping current settings.${NC}"
            exit 0
            ;;
        2)
            echo ""
            echo -e "${BOLD}Changing privacy tier...${NC}"
            ;;
        3)
            echo ""
            echo -e "${BOLD}All models and their privacy details:${NC}"
            echo ""
            jq -r '.models | to_entries[] | 
                "Model: \(.value.name)\nProvider: \(.value.provider // "Unknown")\nTier: \(.value.privacy_tier)\nEvidence: \(.value.evidence)\n"' \
                "$REGISTRY_FILE" 2>/dev/null
            echo ""
            read -p "Press Enter to continue..."
            echo ""
            show_current_config
            exit 0
            ;;
        4)
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option. Keeping current settings.${NC}"
            exit 0
            ;;
    esac
fi

# ============================================================
# First-time setup / tier selection
# ============================================================

# Counts and name lists for the menu come from the registry — never hardcoded.
menu_total=$(registry_total)
menu_c1=$(registry_count_le 1)
menu_c2=$(registry_count_le 2)
menu_c3=$(registry_count_le 3)
menu_c4=$(registry_count_eq 4)

menu_line() {
    # Pad by character count (wc -m), not bytes, so UTF-8 glyphs align.
    local line="$1" width pad
    width=$(printf '%s' "$line" | wc -m)
    pad=$((57 - width))
    [ "$pad" -lt 0 ] && pad=0
    printf '  │%s%*s│\n' "$line" "$pad" ""
}

echo -e "${BOLD}Choose your privacy level:${NC}"
echo ""
echo "  ┌─────────────────────────────────────────────────────────┐"
menu_line "  1  Strict Privacy"
menu_line "     No data used for training. Zero-retention."
menu_line "     ⚠ None — no free models (${menu_c1} of ${menu_total})"
menu_line ""
menu_line "  2  Anonymous Improvement Only"
menu_line "     Logged for improvement, NOT linked to identity."
menu_line "     ⚠ Only lower-tier models (${menu_c2} of ${menu_total})"
menu_line ""
menu_line "  3  Model Improvement (Recommended)"
menu_line "     Data may improve the model during free period."
menu_line "     ✓ ${menu_c3} of ${menu_total} — excludes higher-tier models"
menu_line ""
menu_line "  4  Accept All"
menu_line "     All ${menu_total} free models incl. explicit training."
menu_line "     ⚠ ${menu_c4} tier-4 models may train on your data"
echo "  └─────────────────────────────────────────────────────────┘"
echo ""
read -p "Select privacy tier [1-4]: " tier

# Validate input
if [[ ! "$tier" =~ ^[1-4]$ ]]; then
    echo -e "${RED}Invalid selection. Please enter 1, 2, 3, or 4.${NC}"
    exit 1
fi

echo ""
print_tier_info "$tier"

echo ""
echo -e "${BOLD}Models you'll have access to:${NC}"
while IFS='|' read -r model_id name provider; do
    if [ -n "$model_id" ]; then
        echo "  ✓ $name ($provider)"
    fi
done < <(get_models_for_tier "$tier")

echo ""
echo -e "${BOLD}Models excluded at tier $tier:${NC}"
# One jq pass emits id|name|full tier for every model above the selected tier.
while IFS='|' read -r model_id name tier_name; do
    if [ -n "$model_id" ]; then
        echo "  ✗ $name (tier: $tier_name)"
    fi
done < <(jq -r --arg max "$tier" '
    .models | to_entries[]
    | ((.value.privacy_tier // "4" | tostring | split("_")[0] | tonumber? // 4)) as $t
    | select($t > ($max | tonumber))
    | [.key, (.value.name // .key), (.value.privacy_tier // "unknown")]
    | join("|")' "$REGISTRY_FILE" 2>/dev/null)

echo ""
read -p "Confirm this selection? [Y/n]: " confirm
if [[ "$confirm" =~ ^[nN]$ ]]; then
    echo -e "${YELLOW}Setup cancelled.${NC}"
    exit 0
fi

save_config "$tier"

echo ""
echo -e "${GREEN}${BOLD}Setup complete!${NC}"
echo ""
echo "Your privacy tier ($tier) is now saved and will be used by:"
echo "  • model-selector.sh — picks best models for your tier"
echo "  • daily-check.sh --interactive — notifies when models change"
echo ""
echo "To change your preferences later, run:"
echo "  ./privacy-setup.sh"
