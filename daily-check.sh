#!/bin/bash
# Daily Model Check — Run at start of each gentle-ai session
# Checks OpenCode Zen for available models, updates registry if changed,
# and outputs today's model assignments based on user's privacy tier.
#
# Usage:
#   ./daily-check.sh                 # non-interactive (session hook path)
#   ./daily-check.sh --interactive   # diff vs registry, confirm before write

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/.privacy-config"
REGISTRY_FILE="$SCRIPT_DIR/privacy-tier-registry.json"
SNAPSHOT_FILE="$SCRIPT_DIR/results/.daily-snapshot.txt"
LOG_FILE="$SCRIPT_DIR/results/daily-check.log"
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

mkdir -p "$SCRIPT_DIR/results"

# ─── Mode ───────────────────────────────────────────────────────────────────
# Plain (default) preserves the exact non-interactive behavior the session
# hook relies on: snapshot diff, auto-update registry, no prompts.
INTERACTIVE=false
for arg in "$@"; do
    case "$arg" in
        --interactive)
            INTERACTIVE=true
            ;;
        -h|--help)
            echo "Usage: $0 [--interactive]"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $arg (try --help)${NC}" >&2
            exit 1
            ;;
    esac
done

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
# Registry update — one jq pass for add + remove + timestamp.
# New models default to tier 4 (unknown privacy = worst case).
# Writes via same-directory mktemp + mv (atomic, no fixed .tmp path).
# ============================================================

apply_registry_changes() {
    local added=$1 removed=$2
    local added_arr removed_arr tmp_registry
    added_arr=$(printf '%s' "$added" | jq -Rn '[inputs | select(length > 0)]')
    removed_arr=$(printf '%s' "$removed" | jq -Rn '[inputs | select(length > 0)]')
    tmp_registry=$(mktemp "${REGISTRY_FILE}.tmp.XXXXXX")
    jq -n \
        --argjson reg "$reg_json" \
        --argjson adds "$added_arr" \
        --argjson rems "$removed_arr" \
        --arg ts "$(date -Iseconds)" '
        reduce $adds[] as $m ($reg;
            if (.models | has("opencode/" + $m)) then .
            else .models["opencode/" + $m] = {
                name: $m,
                provider: "Unknown",
                privacy_tier: "4_explicit_training",
                evidence: ("UNVERIFIED — auto-added " + $ts + ". Default tier 4 per free-only policy: unknown privacy = maximum exposure. Upgrade only after verified privacy evidence."),
                privacy_url: null,
                context_window: 262144,
                output_limit: 131072,
                tool_call: true,
                best_for: []
            } end)
        | reduce $rems[] as $m (. ; del(.models["opencode/" + $m]))
        | .last_updated = $ts
    ' > "$tmp_registry" && mv "$tmp_registry" "$REGISTRY_FILE"
    reg_json=$(jq -c . "$REGISTRY_FILE")
}

# ============================================================
# Changelog (interactive mode)
# ============================================================

append_changelog() {
    local added=$1 removed=$2
    local timestamp=$(date -Iseconds)
    {
        echo ""
        echo "## $timestamp"
        echo ""
        echo "### Models Added"
        echo "$added"
        echo ""
        echo "### Models Removed"
        echo "$removed"
        echo ""
    } >> "$CHANGELOG_FILE"
    echo -e "${GREEN}✓ Change log updated: $CHANGELOG_FILE${NC}"
}

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

# Single registry load for the run; reloaded after any write below so
# later lookups always see the current state.
reg_json=$(jq -c . "$REGISTRY_FILE")

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
    live_count=$(echo "$live_models" | grep -c . || true)
fi

if [ "$INTERACTIVE" = true ]; then
    # ── Interactive: diff live list vs the registry (source of truth),
    # confirm before writing, then re-evaluate the assignments below.
    # Fetch warnings were already printed by the fetch step; stdout of
    # fetch_zen_models carries model ids only (no warning pollution).
    registry_models=$(jq -r '.models | keys[]' <<<"$reg_json" | sed 's|^opencode/||' | sort)
    registry_count=$(echo "$registry_models" | grep -c . || true)

    echo -e "  Live models:     ${CYAN}$live_count${NC}"
    echo -e "  Registry models: ${CYAN}$registry_count${NC}"
    echo ""

    if [ "$live_count" -gt 0 ]; then
        added=$(comm -13 <(echo "$registry_models") <(echo "$live_models"))
        removed=$(comm -23 <(echo "$registry_models") <(echo "$live_models"))

        if [ -z "$added" ] && [ -z "$removed" ]; then
            echo -e "${GREEN}${BOLD}✓ Registry is current. No changes detected.${NC}"
            save_snapshot "$live_models"
        else
            if [ -n "$added" ]; then
                echo -e "${GREEN}${BOLD}NEW models detected on OpenCode Zen:${NC}"
                while IFS= read -r m; do
                    [ -n "$m" ] && echo -e "  ${GREEN}+${NC} $m"
                done <<< "$added"
                echo ""
            fi

            if [ -n "$removed" ]; then
                echo -e "${RED}${BOLD}REMOVED models from OpenCode Zen:${NC}"
                while IFS= read -r m; do
                    [ -n "$m" ] && echo -e "  ${RED}-${NC} $m"
                done <<< "$removed"
                echo ""
            fi

            echo -e "${BOLD}Changes detected in the free model landscape.${NC}"
            echo ""
            read -r -p "Update local registry with these changes? [Y/n]: " confirm || confirm=""

            if [[ "$confirm" =~ ^[nN]$ ]]; then
                echo -e "${YELLOW}Changes not applied. Re-evaluating current assignments...${NC}"
            else
                echo ""
                echo -e "${BOLD}Updating registry...${NC}"
                while IFS= read -r m; do
                    [ -n "$m" ] && log "ADDED: $m"
                done <<< "$added"
                while IFS= read -r m; do
                    [ -n "$m" ] && log "REMOVED: $m"
                done <<< "$removed"

                apply_registry_changes "$added" "$removed"
                append_changelog "$added" "$removed"
                save_snapshot "$live_models"
                echo ""
                echo -e "${GREEN}${BOLD}Registry updated.${NC}"

                if [ -n "$added" ]; then
                    echo ""
                    echo -e "${YELLOW}${BOLD}⚠ Important:${NC}"
                    echo "  • New models were added with default privacy tier 4 (unknown = worst case)."
                    echo "  • Please verify their actual privacy policies."
                    echo "  • Run ./privacy-setup.sh to review and adjust if needed."
                    echo "  • If a model you were using was removed, re-run:"
                    echo "    ./model-selector.sh"
                fi
            fi
        fi
    fi
else
    # ── Non-interactive (session hook path): snapshot diff, auto-update.

    # Load previous snapshot
    prev_snapshot=$(load_snapshot)
    prev_count=0
    if [ -n "$prev_snapshot" ]; then
        prev_count=$(echo "$prev_snapshot" | grep -c . || true)
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

            # Report only models that are actually new to the registry.
            added_arr=$(printf '%s' "$added" | jq -Rn '[inputs | select(length > 0)]')
            while IFS= read -r model; do
                [ -n "$model" ] && echo -e "    ${GREEN}+ Added to registry: $model${NC} (default tier 4 — verify privacy to upgrade)"
            done < <(jq -rn --argjson reg "$reg_json" --argjson adds "$added_arr" \
                '$adds[] | select(($reg.models // {}) | has("opencode/" + .) | not)')

            # Batch: add new, remove gone, stamp timestamp — single jq + one write.
            apply_registry_changes "$added" "$removed"

            while IFS= read -r model; do
                [ -n "$model" ] && echo -e "    ${RED}- Removed from registry: $model${NC}"
            done <<< "$removed"

            # Save new snapshot
            save_snapshot "$live_models"

            echo ""
        else
            echo -e "${GREEN}✓ No changes detected. Model list is current.${NC}"
            # Still update snapshot timestamp
            [ "$live_count" -gt 0 ] && save_snapshot "$live_models"
        fi
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

# One jq pass: model_id → display name for the whole table.
declare -A MODEL_NAMES
while IFS='|' read -r mid mname; do
    [ -n "$mid" ] && MODEL_NAMES["$mid"]="$mname"
done < <(jq -r '.models | to_entries[] | "\(.key)|\(.value.name // .key)"' <<<"$reg_json")

printf "  ${BOLD}%-18s %-35s %s${NC}\n" "Role" "Model" "Status"
echo "  ─────────────────────────────────────────────────────────────"

for i in "${!roles[@]}"; do
    role="${roles[$i]}"
    label="${role_labels[$i]}"
    model=$(select_role_model "$role" "$PRIVACY_TIER")
    name="${MODEL_NAMES[$model]:-$model}"
    
    if [ "$model" = "NONE" ]; then
        printf "  %-18s ${RED}%-35s %s${NC}\n" "$label" "NO MODEL" "⚠ needs attention"
    elif [ "$model" = "opencode/big-pickle" ]; then
        printf "  %-18s %-35s ${YELLOW}%s${NC}\n" "$label" "$name" "⚠ stealth fallback"
    else
        printf "  %-18s %-35s ${GREEN}%s${NC}\n" "$label" "$name" "✓ ready"
    fi
done

echo ""

# Count available
total_count=$(jq '.models | length' <<<"$reg_json")
available_count=$(jq --arg max "$PRIVACY_TIER" '
    [.models | to_entries[] | select(
        ((.value.privacy_tier // "4" | tostring | split("_")[0] | tonumber? // 4)) <= ($max | tonumber)
    )] | length' <<<"$reg_json")

echo -e "  ${DIM}Available: $available_count / $total_count models at tier $PRIVACY_TIER${NC}"

if [ "$available_count" -lt 3 ]; then
    echo -e "  ${YELLOW}⚠ Low model count. Consider raising privacy tier with ./privacy-setup.sh${NC}"
fi

echo ""
log "Daily check complete — $available_count models available at tier $PRIVACY_TIER"
echo -e "${GREEN}✓ Daily check complete.${NC}"
