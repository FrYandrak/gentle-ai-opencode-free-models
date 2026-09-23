#!/bin/bash
# Model Change Detector
# Checks OpenCode Zen for model additions/removals and notifies the user.
# Compares live model list against local registry and updates if confirmed.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/.privacy-config"
REGISTRY_FILE="$SCRIPT_DIR/privacy-tier-registry.json"
SNAPSHOT_FILE="$SCRIPT_DIR/results/.model-snapshot.txt"
CHANGELOG_FILE="$SCRIPT_DIR/results/model-changelog.md"

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
# Fetch live model list from OpenCode Zen
# ============================================================

fetch_live_models() {
    # Try the OpenCode Zen models endpoint
    local response=$(curl -s --max-time 10 "https://opencode.ai/zen/v1/models" 2>/dev/null || echo "")
    
    if [ -z "$response" ]; then
        echo -e "${YELLOW}⚠ Could not fetch live model list from OpenCode Zen.${NC}"
        echo -e "${DIM}  Using local registry as reference.${NC}"
        # Fallback: extract from local registry
        jq -r '.models | keys[]' "$REGISTRY_FILE" 2>/dev/null | sed 's|opencode/||g' | sort
        return 1
    fi
    
    # Parse the response - extract free model IDs
    # FREE-ONLY rule: paid models must NEVER enter the pipeline.
    # Match only ids ending in "-free" or the stealth big-pickle.
    echo "$response" | jq -r '
        if type == "array" then
            .[] | select(.id != null) | .id
        elif type == "object" then
            if .data then .data[] | select(.id != null) | .id
            elif .models then .models[] | select(.id != null) | .id
            else empty end
        else empty end
    ' 2>/dev/null | grep -iE -- '-free$|^big-pickle$' | sort || true
}

# ============================================================
# Local registry model list
# ============================================================

get_local_models() {
    jq -r '.models | keys[]' "$REGISTRY_FILE" 2>/dev/null | sed 's|opencode/||g' | sort
}

# ============================================================
# Snapshot comparison
# ============================================================

load_snapshot() {
    if [ -f "$SNAPSHOT_FILE" ]; then
        cat "$SNAPSHOT_FILE" | sort
    fi
}

save_snapshot() {
    local models=$1
    mkdir -p "$SCRIPT_DIR/results"
    echo "$models" > "$SNAPSHOT_FILE"
}

# ============================================================
# Privacy tier re-evaluation
# ============================================================

re_evaluate_assignments() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${YELLOW}No privacy config found. Run ./privacy-setup.sh first.${NC}"
        return
    fi
    
    load_privacy_tier
    local tier="$PRIVACY_TIER"
    
    echo ""
    echo -e "${BOLD}Re-evaluated assignments (privacy tier $tier):${NC}"
    echo ""
    
    local roles=("orchestrator" "explore" "design" "spec" "tasks" "apply" "verify" "archive")
    local role_labels=("Orchestrator" "sdd-explore" "sdd-design" "sdd-spec" "sdd-tasks" "sdd-apply" "sdd-verify" "sdd-archive")
    
    for i in "${!roles[@]}"; do
        local role="${roles[$i]}"
        local label="${role_labels[$i]}"
        
        # Registry-driven selection: first chain member passing all gates wins
        local model=$(select_role_model "$role" "$tier")
        
        if [ "$model" = "NONE" ]; then
            echo -e "  ${RED}✗${NC} $label: NO MODEL — needs attention"
            continue
        fi
        
        # Check if model still exists in registry
        local exists=$(jq -r ".models[\"$model\"].name // \"\"" "$REGISTRY_FILE" 2>/dev/null)
        local model_tier=$(jq -r ".models[\"$model\"].privacy_tier | split(\"_\")[0] | tonumber" "$REGISTRY_FILE" 2>/dev/null)
        
        if [ -z "$exists" ]; then
            echo -e "  ${RED}✗${NC} $label: $model ${RED}REMOVED — needs reassignment${NC}"
        elif [ "$model_tier" -gt "$tier" ] 2>/dev/null; then
            echo -e "  ${YELLOW}⚠${NC} $label: $model ${YELLOW}above your privacy tier${NC}"
        else
            echo -e "  ${GREEN}✓${NC} $label: $model"
        fi
    done
}

# ============================================================
# Changelog
# ============================================================

append_changelog() {
    local added=$1
    local removed=$2
    local timestamp=$(date -Iseconds)
    
    mkdir -p "$SCRIPT_DIR/results"
    
    cat >> "$CHANGELOG_FILE" << EOF

## $timestamp

### Models Added
$added

### Models Removed
$removed

EOF
    
    echo -e "${GREEN}✓ Change log updated: $CHANGELOG_FILE${NC}"
}

# ============================================================
# Main
# ============================================================

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║     Free Model Change Detector                          ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check dependencies
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is required but not installed.${NC}"
    exit 1
fi

if [ ! -f "$REGISTRY_FILE" ]; then
    echo -e "${RED}Error: privacy-tier-registry.json not found.${NC}"
    exit 1
fi

# Fetch live models
echo -e "${BOLD}Fetching live model list from OpenCode Zen...${NC}"
live_models=$(fetch_live_models)
live_count=$(echo "$live_models" | grep -c . || echo "0")

echo -e "${BOLD}Local registry models:${NC}"
local_models=$(get_local_models)
local_count=$(echo "$local_models" | grep -c . || echo "0")

echo ""
echo -e "  Live models:   ${CYAN}$live_count${NC}"
echo -e "  Local models:  ${CYAN}$local_count${NC}"
echo ""

# Compare
added_to_live=$(comm -13 <(echo "$local_models") <(echo "$live_models"))
removed_from_live=$(comm -23 <(echo "$local_models") <(echo "$live_models"))

has_changes=false

if [ -n "$added_to_live" ]; then
    has_changes=true
    echo -e "${GREEN}${BOLD}NEW models detected on OpenCode Zen:${NC}"
    while IFS= read -r model; do
        if [ -n "$model" ]; then
            echo -e "  ${GREEN}+${NC} $model"
        fi
    done <<< "$added_to_live"
    echo ""
fi

if [ -n "$removed_from_live" ]; then
    has_changes=true
    echo -e "${RED}${BOLD}REMOVED models from OpenCode Zen:${NC}"
    while IFS= read -r model; do
        if [ -n "$model" ]; then
            echo -e "  ${RED}-${NC} $model"
        fi
    done <<< "$removed_from_live"
    echo ""
fi

if [ "$has_changes" = false ]; then
    echo -e "${GREEN}${BOLD}✓ No changes detected. Model list is current.${NC}"
    echo ""
    
    # Still re-evaluate assignments
    re_evaluate_assignments
    exit 0
fi

# Ask user to update
echo -e "${BOLD}Changes detected in the free model landscape.${NC}"
echo ""
read -p "Update local registry with these changes? [Y/n]: " confirm

if [[ "$confirm" =~ ^[nN]$ ]]; then
    echo -e "${YELLOW}Changes not applied. Re-evaluating current assignments...${NC}"
    re_evaluate_assignments
    exit 0
fi

# Update registry
echo ""
echo -e "${BOLD}Updating registry...${NC}"

# Add new models
while IFS= read -r model; do
    if [ -n "$model" ]; then
        # Default tier 4 (unknown privacy = worst case) per free-only policy
        jq ".models[\"opencode/$model\"] = {
            \"name\": \"$model\",
            \"provider\": \"Unknown\",
            \"privacy_tier\": \"4_explicit_training\",
            \"evidence\": \"UNVERIFIED — added $(date -Iseconds). Default tier 4 per free-only policy: unknown privacy = maximum exposure. Upgrade only after verified privacy evidence.\",
            \"privacy_url\": null,
            \"context_window\": 262144,
            \"output_limit\": 131072,
            \"tool_call\": true,
            \"best_for\": []
        }" "$REGISTRY_FILE" > "$REGISTRY_FILE.tmp" && mv "$REGISTRY_FILE.tmp" "$REGISTRY_FILE"
        echo -e "  ${GREEN}+ Added: $model${NC} (default tier 4 — verify privacy policy to upgrade)"
    fi
done <<< "$added_to_live"

# Remove models no longer on Zen
while IFS= read -r model; do
    if [ -n "$model" ]; then
        jq "del(.models[\"opencode/$model\"])" "$REGISTRY_FILE" > "$REGISTRY_FILE.tmp" && mv "$REGISTRY_FILE.tmp" "$REGISTRY_FILE"
        echo -e "  ${RED}- Removed: $model${NC}"
    fi
done <<< "$removed_from_live"

# Update timestamp
jq ".last_updated = \"$(date -Iseconds)\"" "$REGISTRY_FILE" > "$REGISTRY_FILE.tmp" && mv "$REGISTRY_FILE.tmp" "$REGISTRY_FILE"

echo ""
echo -e "${GREEN}${BOLD}Registry updated.${NC}"
echo ""

# Log changes
append_changelog "$added_to_live" "$removed_from_live"

# Re-evaluate assignments with updated registry
re_evaluate_assignments

echo ""
echo -e "${YELLOW}${BOLD}⚠ Important:${NC}"
echo "  • New models were added with default privacy tier 4 (unknown = worst case)."
echo "  • Please verify their actual privacy policies."
echo "  • Run ./privacy-setup.sh to review and adjust if needed."
echo "  • If a model you were using was removed, re-run:"
echo "    ./model-selector.sh"
