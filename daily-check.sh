#!/bin/bash
# Daily Model Check — Run at start of each gentle-ai session
# Checks OpenCode Zen for available models, updates registry if changed,
# and outputs today's model assignments based on user's privacy tier.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/.privacy-config"
REGISTRY_FILE="$SCRIPT_DIR/privacy-tier-registry.json"
SNAPSHOT_FILE="$SCRIPT_DIR/results/.daily-snapshot.txt"
LOG_FILE="$SCRIPT_DIR/results/daily-check.log"

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

mkdir -p "$SCRIPT_DIR/results"

# ============================================================
# Logging
# ============================================================

log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" >> "$LOG_FILE"
}

# ============================================================
# Fetch live models from OpenCode Zen
# ============================================================

fetch_zen_models() {
    local response=""
    
    # Try the models endpoint
    response=$(curl -s --max-time 15 "https://opencode.ai/zen/v1/models" 2>/dev/null || echo "")
    
    if [ -z "$response" ]; then
        echo ""
        return 1
    fi
    
    # Extract free model IDs — FREE-ONLY rule: paid models must NEVER enter
    # the pipeline. Match only ids ending in "-free" or the stealth big-pickle.
    echo "$response" | jq -r '
        if type == "array" then .[]
        elif type == "object" then
            if .data then .data[]
            elif .models then .models[]
            else empty end
        else empty end
        | select(.id != null)
        | .id
    ' 2>/dev/null | grep -iE -- '-free$|^big-pickle$' | sort || true
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
    echo "$1" > "$SNAPSHOT_FILE"
}

# ============================================================
# Model selection based on privacy tier — provided by
# select-role-model.sh (select_role_model)
# ============================================================

# ============================================================
# Main daily check
# ============================================================

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║     Daily Free Model Check                              ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check dependencies
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is required. Install with: sudo apt install jq${NC}"
    exit 1
fi

if [ ! -f "$REGISTRY_FILE" ]; then
    echo -e "${RED}Error: privacy-tier-registry.json not found.${NC}"
    exit 1
fi

# Check privacy config
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${YELLOW}No privacy configuration found.${NC}"
    echo "Running first-time setup..."
    echo ""
    bash "$SCRIPT_DIR/privacy-setup.sh"
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}Setup cancelled. Cannot proceed without privacy tier.${NC}"
        exit 1
    fi
fi

load_privacy_tier

echo -e "  Privacy tier: ${CYAN}$PRIVACY_TIER${NC}"
echo -e "  Checking OpenCode Zen..."
echo ""

log "Daily check started — tier $PRIVACY_TIER"

# Fetch live models
live_models=$(fetch_zen_models)
if [ -z "$live_models" ]; then
    echo -e "${YELLOW}⚠ Could not fetch live model list from OpenCode Zen.${NC}"
    echo -e "${DIM}  Continuing with local registry.${NC}"
    log "WARNING: Could not fetch live models from Zen"
    live_count=0
else
    live_count=$(echo "$live_models" | grep -c . || echo "0")
fi

# Load previous snapshot
prev_snapshot=$(load_snapshot)
prev_count=0
if [ -n "$prev_snapshot" ]; then
    prev_count=$(echo "$prev_snapshot" | grep -c . || echo "0")
fi

echo -e "  Live models found: ${CYAN}$live_count${NC}"
echo -e "  Previous snapshot: ${CYAN}$prev_count${NC}"
echo ""

# Detect changes
if [ "$live_count" -gt 0 ]; then
    added=$(comm -13 <(echo "$prev_snapshot" 2>/dev/null || echo "") <(echo "$live_models"))
    removed=$(comm -23 <(echo "$prev_snapshot" 2>/dev/null || echo "") <(echo "$live_models"))
    
    if [ -n "$added" ] || [ -n "$removed" ]; then
        echo -e "${BOLD}Changes detected:${NC}"
        
        if [ -n "$added" ]; then
            echo -e "${GREEN}  + New models:${NC}"
            while IFS= read -r m; do
                [ -n "$m" ] && echo -e "    ${GREEN}+${NC} $m"
                log "ADDED: $m"
            done <<< "$added"
        fi
        
        if [ -n "$removed" ]; then
            echo -e "${RED}  - Removed models:${NC}"
            while IFS= read -r m; do
                [ -n "$m" ] && echo -e "    ${RED}-${NC} $m"
                log "REMOVED: $m"
            done <<< "$removed"
        fi
        
        echo ""
        echo -e "${YELLOW}Registry will be updated with available models.${NC}"
        
        # Update registry: new models default to tier 4 (unknown privacy = worst case)
        while IFS= read -r model; do
            if [ -n "$model" ]; then
                exists=$(jq -r ".models[\"opencode/$model\"].name // \"\"" "$REGISTRY_FILE" 2>/dev/null)
                if [ -z "$exists" ]; then
                    jq ".models[\"opencode/$model\"] = {
                        \"name\": \"$model\",
                        \"provider\": \"Unknown\",
                        \"privacy_tier\": \"4_explicit_training\",
                        \"evidence\": \"UNVERIFIED — auto-added $(date -Iseconds). Default tier 4 per free-only policy: unknown privacy = maximum exposure. Upgrade only after verified privacy evidence.\",
                        \"privacy_url\": null,
                        \"context_window\": 262144,
                        \"output_limit\": 131072,
                        \"tool_call\": true,
                        \"best_for\": []
                    }" "$REGISTRY_FILE" > "$REGISTRY_FILE.tmp" && mv "$REGISTRY_FILE.tmp" "$REGISTRY_FILE"
                    echo -e "    ${GREEN}+ Added to registry: $model${NC} (default tier 4 — verify privacy to upgrade)"
                fi
            fi
        done <<< "$added"
        
        # Remove models no longer on Zen
        while IFS= read -r model; do
            if [ -n "$model" ]; then
                jq "del(.models[\"opencode/$model\"])" "$REGISTRY_FILE" > "$REGISTRY_FILE.tmp" && mv "$REGISTRY_FILE.tmp" "$REGISTRY_FILE"
                echo -e "    ${RED}- Removed from registry: $model${NC}"
            fi
        done <<< "$removed"
        
        # Update timestamp
        jq ".last_updated = \"$(date -Iseconds)\"" "$REGISTRY_FILE" > "$REGISTRY_FILE.tmp" && mv "$REGISTRY_FILE.tmp" "$REGISTRY_FILE"
        
        # Save new snapshot
        save_snapshot "$live_models"
        
        echo ""
    else
        echo -e "${GREEN}✓ No changes detected. Model list is current.${NC}"
        # Still update snapshot timestamp
        [ "$live_count" -gt 0 ] && save_snapshot "$live_models"
    fi
fi

# ============================================================
# Today's model assignments
# ============================================================

echo ""
echo -e "${BOLD}Today's model assignments (tier $PRIVACY_TIER):${NC}"
echo ""

roles=("orchestrator" "explore" "design" "spec" "tasks" "apply" "verify" "archive")
role_labels=("Orchestrator" "sdd-explore" "sdd-design" "sdd-spec" "sdd-tasks" "sdd-apply" "sdd-verify" "sdd-archive")

printf "  ${BOLD}%-18s %-35s %s${NC}\n" "Role" "Model" "Status"
echo "  ─────────────────────────────────────────────────────────────"

for i in "${!roles[@]}"; do
    role="${roles[$i]}"
    label="${role_labels[$i]}"
    model=$(select_role_model "$role" "$PRIVACY_TIER")
    
    if [ "$model" = "NONE" ]; then
        printf "  %-18s ${RED}%-35s %s${NC}\n" "$label" "NO MODEL" "⚠ needs attention"
    elif [ "$model" = "opencode/big-pickle" ]; then
        name=$(jq -r ".models[\"$model\"].name // \"$model\"" "$REGISTRY_FILE" 2>/dev/null)
        printf "  %-18s %-35s ${YELLOW}%s${NC}\n" "$label" "$name" "⚠ stealth fallback"
    else
        name=$(jq -r ".models[\"$model\"].name // \"$model\"" "$REGISTRY_FILE" 2>/dev/null)
        printf "  %-18s %-35s ${GREEN}%s${NC}\n" "$label" "$name" "✓ ready"
    fi
done

echo ""

# Count available
available_count=0
total_count=$(jq '.models | length' "$REGISTRY_FILE" 2>/dev/null)
while IFS= read -r m; do
    [ -n "$m" ] && available_count=$((available_count + 1))
done < <(jq -r ".models | to_entries[] | select(
    (.value.privacy_tier | split(\"_\")[0] | tonumber) <= $PRIVACY_TIER
) | .key" "$REGISTRY_FILE" 2>/dev/null)

echo -e "  ${DIM}Available: $available_count / $total_count models at tier $PRIVACY_TIER${NC}"

if [ "$available_count" -lt 3 ]; then
    echo -e "  ${YELLOW}⚠ Low model count. Consider raising privacy tier with ./privacy-setup.sh${NC}"
fi

echo ""
log "Daily check complete — $available_count models available at tier $PRIVACY_TIER"
echo -e "${GREEN}✓ Daily check complete.${NC}"
