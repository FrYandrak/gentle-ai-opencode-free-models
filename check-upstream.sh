#!/bin/bash
# check-upstream.sh — detect Gentle-AI upstream releases that could affect
# this project (agent names, opencode.jsonc config shape, contract versions)
# and report what needs adapting — before silent breakage.
#
# Usage:
#   ./check-upstream.sh            run checks (once per day; stamp-gated)
#   ./check-upstream.sh --force    bypass the once-per-day stamp
#   ./check-upstream.sh --help     print usage and exit 0
#
# DUPLICATION RISK MARKER (see odd/tasks/check-upstream.md):
# daily-check.sh and session-start-hook.sh keep colors/banner/log/stamp
# helpers private — no shared shell lib exists. This script duplicates
# those helpers (4th copy of the colors/banner block across repo scripts).
# Extract lib-common.sh only if a 5th consumer appears; do not extract now.
#
# Exit codes:
#   0  success, warnings, and advisories (graceful network degradation:
#      any fetch failure prints a yellow warning and continues)
#   1  hard errors: missing jq, bad CLI flag

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPSTREAM_REPO="Gentleman-Programming/gentle-ai"
STAMP_FILE="$SCRIPT_DIR/results/.last-upstream-run"
LOCK_FILE="$SCRIPT_DIR/results/.last-upstream-run.lock"
LOG_FILE="$SCRIPT_DIR/results/check-upstream.log"
GEN_AGENT_CONFIG="$SCRIPT_DIR/generate-agent-config.sh"
OPENCODE_CONFIG="${OPENCODE_CONFIG:-$HOME/.config/opencode/opencode.jsonc}"
GENTLE_AI_BIN="${GENTLE_AI_BIN:-gentle-ai}"
CURL_MAX_TIME=15          # curl --max-time (seconds) for every GitHub API call
RELEASES_PER_PAGE=10      # page size for the releases listing
MAX_DIFF_SHOWN=30         # max upstream impact files printed in Check 3

# Colors (mirrors daily-check.sh L22-29)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

mkdir -p "$SCRIPT_DIR/results"

# ─── Flags ───────────────────────────────────────────────────────────────────
FORCE=false
for arg in "$@"; do
    case "$arg" in
        --force)
            FORCE=true
            ;;
        -h|--help)
            echo "Usage: $0 [--force]"
            echo ""
            echo "Detect upstream Gentle-AI releases that could affect this project"
            echo "(agent names, opencode.jsonc shape, contract versions) and report drift."
            echo ""
            echo "Options:"
            echo "  --force      bypass the once-per-day stamp and run checks now"
            echo "  -h, --help   print this help and exit (0)"
            echo ""
            echo "Exit codes: 0 = success/warnings (network failures degrade gracefully),"
            echo "            1 = hard errors (missing jq, bad flag)."
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $arg (try --help)${NC}" >&2
            exit 1
            ;;
    esac
done

# ============================================================
# Logging (mirrors daily-check.sh L57-60)
# ============================================================
log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" >> "$LOG_FILE"
}

section() {
    echo ""
    echo -e "${BOLD}==== $1 ====${NC}"
}

# ─── Banner (mirrors daily-check.sh L166-170) ────────────────────────────────
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║     Check Upstream — Gentle-AI drift detector            ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check dependencies (mirrors daily-check.sh L172-176)
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is required. Install with: sudo apt install jq${NC}"
    exit 1
fi

log "check-upstream started (force=$FORCE)"

# ─── Once-per-day stamp + flock (mirrors session-start-hook.sh L25-51) ───────
today=$(date +%Y-%m-%d)

already_ran_today() {
    [ -f "$STAMP_FILE" ] && [ "$(<"$STAMP_FILE")" = "$today" ]
}

if [ "$FORCE" = false ] && already_ran_today; then
    echo -e "${DIM}Already ran today ($today) — skipping. Use --force to re-run.${NC}"
    echo ""
    exit 0
fi

# Serialize concurrent runs. flock is released automatically if a shell
# crashes mid-run, so there is no stale-lock recovery to manage.
exec 9>"$LOCK_FILE" || { echo -e "${YELLOW}⚠ Could not open lock file — skipping.${NC}"; exit 0; }
if ! flock -n 9; then
    # Another run holds the lock (running right now, or just finished).
    exec 9>&-
    echo -e "${DIM}Another check-upstream run holds the lock — skipping. Retry later or use --force.${NC}"
    echo ""
    exit 0
fi
if [ "$FORCE" = false ] && already_ran_today; then
    # Re-check under the lock: the previous holder may have just stamped.
    exec 9>&-
    echo -e "${DIM}Already ran today ($today) — stamped by a concurrent run. Use --force to re-run.${NC}"
    echo ""
    exit 0
fi

# ============================================================
# Network helpers — gh primary, curl fallback.
# gh is NEW for this repo (zero prior usage): both paths are verified
# working and degrade gracefully. Functions set globals directly (no
# command substitution) so FETCH_* survives outside subshells.
# Any fetch failure leaves FETCH_OK=false → caller warns (yellow) and
# continues; the script still exits 0.
# ============================================================
FETCH_OK=false
FETCH_SOURCE=""

fetch_latest_tag() {
    UPSTREAM_TAG=""
    FETCH_OK=false
    FETCH_SOURCE=""
    local tag="" body=""
    if command -v gh &>/dev/null; then
        tag=$(gh api "repos/$UPSTREAM_REPO/releases/latest" --jq '.tag_name' 2>/dev/null || true)
        if [ -n "$tag" ]; then
            UPSTREAM_TAG="$tag"
            FETCH_OK=true
            FETCH_SOURCE="gh"
            return 0
        fi
    fi
    body=$(curl -s --max-time "$CURL_MAX_TIME" "https://api.github.com/repos/$UPSTREAM_REPO/releases/latest" 2>/dev/null || true)
    if [ -n "$body" ] && printf '%s' "$body" | jq -e '.tag_name' >/dev/null 2>&1; then
        UPSTREAM_TAG=$(printf '%s' "$body" | jq -r '.tag_name' 2>/dev/null || true)
        if [ -n "$UPSTREAM_TAG" ]; then
            FETCH_OK=true
            FETCH_SOURCE="curl"
        fi
    fi
}

# Compare file list for range v<base>...v<head>. Empty COMPARE_FILES with
# FETCH_OK=true means zero changed files (API succeeded).
fetch_compare_files() {
    COMPARE_FILES=""
    FETCH_OK=false
    FETCH_SOURCE=""
    local range="$1...$2" out="" body=""
    if command -v gh &>/dev/null; then
        if out=$(gh api "repos/$UPSTREAM_REPO/compare/$range" --jq '.files[].filename' 2>/dev/null); then
            COMPARE_FILES="$out"
            FETCH_OK=true
            FETCH_SOURCE="gh"
            return 0
        fi
    fi
    body=$(curl -s --max-time "$CURL_MAX_TIME" "https://api.github.com/repos/$UPSTREAM_REPO/compare/$range" 2>/dev/null || true)
    if [ -n "$body" ] && printf '%s' "$body" | jq -e '.files' >/dev/null 2>&1; then
        COMPARE_FILES=$(printf '%s' "$body" | jq -r '.files[]?.filename' 2>/dev/null || true)
        FETCH_OK=true
        FETCH_SOURCE="curl"
    fi
}

fetch_releases_json() {
    RELEASES_JSON=""
    FETCH_OK=false
    FETCH_SOURCE=""
    local out="" body=""
    if command -v gh &>/dev/null; then
        if out=$(gh api "repos/$UPSTREAM_REPO/releases?per_page=$RELEASES_PER_PAGE" 2>/dev/null); then
            RELEASES_JSON="$out"
            FETCH_OK=true
            FETCH_SOURCE="gh"
            return 0
        fi
    fi
    body=$(curl -s --max-time "$CURL_MAX_TIME" "https://api.github.com/repos/$UPSTREAM_REPO/releases?per_page=$RELEASES_PER_PAGE" 2>/dev/null || true)
    if [ -n "$body" ] && printf '%s' "$body" | jq -e 'type == "array"' >/dev/null 2>&1; then
        RELEASES_JSON="$body"
        FETCH_OK=true
        FETCH_SOURCE="curl"
    fi
}

# Upstream contracts inventory: one call for contracts/ dirs (gh api
# .../contents/contracts per the feature doc), then one per dir for
# version subdirs (v1, v2, ...). Results: lines "contracts/<name>/v<N>".
fetch_contract_versions() {
    CONTRACT_VERSIONS=""
    FETCH_OK=false
    FETCH_SOURCE=""
    local dirs="" body="" name="" vers="" b2="" v=""
    if command -v gh &>/dev/null; then
        dirs=$(gh api "repos/$UPSTREAM_REPO/contents/contracts" --jq '.[].name' 2>/dev/null || true)
        if [ -n "$dirs" ]; then
            FETCH_SOURCE="gh"
        fi
    fi
    if [ -z "$dirs" ]; then
        body=$(curl -s --max-time "$CURL_MAX_TIME" "https://api.github.com/repos/$UPSTREAM_REPO/contents/contracts" 2>/dev/null || true)
        if [ -n "$body" ] && printf '%s' "$body" | jq -e 'type == "array"' >/dev/null 2>&1; then
            dirs=$(printf '%s' "$body" | jq -r '.[].name' 2>/dev/null || true)
            FETCH_SOURCE="curl"
        fi
    fi
    if [ -z "$dirs" ]; then
        return 0
    fi
    FETCH_OK=true
    while IFS= read -r name; do
        if [ -z "$name" ]; then
            continue
        fi
        vers=""
        if [ "$FETCH_SOURCE" = "gh" ]; then
            vers=$(gh api "repos/$UPSTREAM_REPO/contents/contracts/$name" --jq '.[].name' 2>/dev/null || true)
        else
            b2=$(curl -s --max-time "$CURL_MAX_TIME" "https://api.github.com/repos/$UPSTREAM_REPO/contents/contracts/$name" 2>/dev/null || true)
            if [ -n "$b2" ] && printf '%s' "$b2" | jq -e 'type == "array"' >/dev/null 2>&1; then
                vers=$(printf '%s' "$b2" | jq -r '.[].name' 2>/dev/null || true)
            fi
        fi
        while IFS= read -r v; do
            if [[ "$v" =~ ^v[0-9]+$ ]]; then
                CONTRACT_VERSIONS+="contracts/$name/$v"$'\n'
            fi
        done <<< "$vers"
    done <<< "$dirs"
}

detect_local_version() {
    LOCAL_VER=""
    local out=""
    if command -v "$GENTLE_AI_BIN" &>/dev/null; then
        out=$("$GENTLE_AI_BIN" --version 2>/dev/null || true)
    elif [ -x "$HOME/.local/bin/gentle-ai" ]; then
        out=$("$HOME/.local/bin/gentle-ai" --version 2>/dev/null || true)
    fi
    # Binary prints e.g. "gentle-ai 3.4.0" — extract the semver.
    LOCAL_VER=$(printf '%s' "$out" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
}

# Sets VERDICT to in-sync | behind | ahead | invalid (local perspective).
# Invalid/malformed inputs set VERDICT="invalid" and return 0 — the script
# runs under set -e, so this function must never return non-zero.
VERDICT="unknown"
compare_versions() {
    local a="$1" b="$2" newest=""
    if ! [[ "$a" =~ ^[0-9]+(\.[0-9]+)+([-+][0-9A-Za-z.-]+)?$ ]] ||
       ! [[ "$b" =~ ^[0-9]+(\.[0-9]+)+([-+][0-9A-Za-z.-]+)?$ ]]; then
        VERDICT="invalid"
        return 0
    fi
    if [ "$a" = "$b" ]; then
        VERDICT="in-sync"
        return 0
    fi
    newest=$(printf '%s\n%s\n' "$a" "$b" | sort -V | tail -1)
    if [ "$newest" = "$b" ]; then
        VERDICT="behind"
    else
        VERDICT="ahead"
    fi
}

# ============================================================
# Checks 1–6
# ============================================================
ADVISORY_COUNT=0
WARN_COUNT=0
UPSTREAM_TAG=""
UPSTREAM_VER=""
LOCAL_VER=""

# ── Check 1: Latest upstream release tag ──────────────────────────────────────
section "Check 1: Latest upstream release tag"
fetch_latest_tag
if [ "$FETCH_OK" = false ] || [ -z "$UPSTREAM_TAG" ]; then
    echo -e "${YELLOW}⚠ Could not fetch the latest upstream release (network/API failure).${NC}"
    echo -e "${DIM}  Continuing with remaining checks (graceful degradation).${NC}"
    log "WARNING: upstream latest-tag fetch failed"
    WARN_COUNT=$((WARN_COUNT + 1))
else
    if [[ "$UPSTREAM_TAG" =~ ^v[0-9]+(\.[0-9]+)+([-+][0-9A-Za-z.-]+)?$ ]]; then
        echo -e "${GREEN}✓${NC} Latest upstream release: ${CYAN}$UPSTREAM_TAG${NC} ${DIM}(via $FETCH_SOURCE)${NC}"
        UPSTREAM_VER="${UPSTREAM_TAG#v}"
    else
        echo -e "${YELLOW}⚠ Unexpected upstream tag format: '$UPSTREAM_TAG' — tag not a vN.N.N release, downstream checks skipped.${NC}"
        log "WARNING: unexpected upstream tag format"
        WARN_COUNT=$((WARN_COUNT + 1))
        UPSTREAM_TAG=""
        UPSTREAM_VER=""
    fi
fi

# ── Check 2: Local version vs upstream → drift verdict ───────────────────────
section "Check 2: Local version vs upstream (drift verdict)"
detect_local_version
if [ -z "$LOCAL_VER" ]; then
    echo -e "${YELLOW}⚠ gentle-ai binary not found or '--version' failed — cannot compute drift.${NC}"
    echo -e "${DIM}  Expected binary: ~/.local/bin/gentle-ai${NC}"
elif [ -z "$UPSTREAM_VER" ]; then
    echo -e "${YELLOW}⚠ Upstream tag unknown (check 1 failed) — drift verdict skipped.${NC}"
else
    compare_versions "$LOCAL_VER" "$UPSTREAM_VER"
    case "$VERDICT" in
        in-sync)
            echo -e "${GREEN}${BOLD}✓ In sync:${NC} local $LOCAL_VER == upstream $UPSTREAM_TAG"
            ;;
        behind)
            echo -e "${YELLOW}${BOLD}⚠ BEHIND:${NC} local $LOCAL_VER → upstream $UPSTREAM_TAG"
            echo -e "${DIM}  Review upstream release notes before upgrading.${NC}"
            ADVISORY_COUNT=$((ADVISORY_COUNT + 1))
            ;;
        ahead)
            echo -e "${CYAN}${BOLD}↑ AHEAD:${NC} local $LOCAL_VER > upstream $UPSTREAM_TAG (pre-release or local build?)"
            ADVISORY_COUNT=$((ADVISORY_COUNT + 1))
            ;;
        invalid)
            echo -e "${YELLOW}⚠ Malformed version string(s): local '$LOCAL_VER' vs upstream '$UPSTREAM_VER' — drift verdict skipped.${NC}"
            ;;
    esac
fi

# ── Check 3: Diff surface since local version ─────────────────────────────────
section "Check 3: Diff surface since local version"
if [ -z "$LOCAL_VER" ] || [ -z "$UPSTREAM_VER" ]; then
    echo -e "${YELLOW}⚠ Local version or upstream tag unknown — diff surface skipped.${NC}"
elif [ "$VERDICT" = "in-sync" ]; then
    echo -e "${GREEN}✓ Versions in sync — no diff to inspect.${NC}"
elif [ "$VERDICT" = "ahead" ]; then
    echo -e "${CYAN}Local is ahead of upstream — compare direction not applicable, skipped.${NC}"
elif [ "$VERDICT" = "behind" ]; then
    fetch_compare_files "v$LOCAL_VER" "v$UPSTREAM_VER"
    if [ "$FETCH_OK" = false ]; then
        echo -e "${YELLOW}⚠ Could not fetch compare v$LOCAL_VER...v$UPSTREAM_VER (network/API failure).${NC}"
        log "WARNING: compare fetch failed (v$LOCAL_VER...v$UPSTREAM_VER)"
        WARN_COUNT=$((WARN_COUNT + 1))
    else
        filtered=$(printf '%s\n' "$COMPARE_FILES" | grep -E 'opencode|agent|contract' || true)
        impact_count=$(printf '%s' "$filtered" | grep -c . || true)
        if [ "$impact_count" -eq 0 ]; then
            echo -e "${GREEN}✓ No opencode/agent/contract files changed upstream since v$LOCAL_VER.${NC}"
        else
            echo -e "${YELLOW}${BOLD}⚠ $impact_count potential impact file(s) (opencode|agent|contract) since v$LOCAL_VER:${NC}"
            shown=0
            while IFS= read -r f; do
                if [ -z "$f" ]; then
                    continue
                fi
                if [ "$shown" -lt "$MAX_DIFF_SHOWN" ]; then
                    echo "    • $f"
                    shown=$((shown + 1))
                fi
            done <<< "$filtered"
            if [ "$impact_count" -gt "$MAX_DIFF_SHOWN" ]; then
                echo -e "${DIM}    … and $((impact_count - MAX_DIFF_SHOWN)) more:${NC}"
                echo -e "${DIM}    https://github.com/$UPSTREAM_REPO/compare/v$LOCAL_VER...v$UPSTREAM_VER${NC}"
            fi
            log "ADVISORY: $impact_count potential impact files since v$LOCAL_VER"
            ADVISORY_COUNT=$((ADVISORY_COUNT + 1))
        fi
    fi
else
    echo -e "${YELLOW}⚠ Drift verdict unavailable — diff surface skipped.${NC}"
fi

# ── Check 4: Release-notes keyword scan ───────────────────────────────────────
section "Check 4: Release-notes keyword scan (breaking|opencode|agent)"
fetch_releases_json
if [ "$FETCH_OK" = false ]; then
    echo -e "${YELLOW}⚠ Could not fetch upstream release notes (network/API failure).${NC}"
    log "WARNING: release-notes fetch failed"
    WARN_COUNT=$((WARN_COUNT + 1))
else
    rel_total=$(jq 'length' <<<"$RELEASES_JSON" 2>/dev/null || echo 0)
    rel_breaking=$(jq '[.[] | select((.body // "") | test("breaking"; "i"))] | length' <<<"$RELEASES_JSON" 2>/dev/null || echo 0)
    rel_opencode=$(jq '[.[] | select((.body // "") | test("opencode"; "i"))] | length' <<<"$RELEASES_JSON" 2>/dev/null || echo 0)
    rel_agent=$(jq '[.[] | select((.body // "") | test("agent"; "i"))] | length' <<<"$RELEASES_JSON" 2>/dev/null || echo 0)
    echo -e "  Scanned last ${CYAN}$rel_total${NC} release note(s) ${DIM}(via $FETCH_SOURCE)${NC}"
    if [ "$rel_breaking" -eq 0 ] && [ "$rel_opencode" -eq 0 ] && [ "$rel_agent" -eq 0 ]; then
        echo -e "${GREEN}✓ No breaking/opencode/agent keyword hits in release notes.${NC}"
    else
        echo ""
        echo -e "${YELLOW}${BOLD}⚠ Advisory:${NC} keyword hits in release notes:"
        echo "  • breaking: $rel_breaking of $rel_total release note(s)"
        echo "  • opencode: $rel_opencode of $rel_total release note(s)"
        echo "  • agent:    $rel_agent of $rel_total release note(s)"
        echo -e "${DIM}  Read matching release notes before upgrading gentle-ai.${NC}"
        log "ADVISORY: release-notes keyword hits breaking=$rel_breaking opencode=$rel_opencode agent=$rel_agent"
        ADVISORY_COUNT=$((ADVISORY_COUNT + 1))
    fi
fi

# ── Check 5: Offline agent-name dependency check ──────────────────────────────
section "Check 5: Offline agent-name dependency check"
agent_names=""
if [ -f "$GEN_AGENT_CONFIG" ]; then
    agent_names=$(sed -n '/^AGENT_NAMES=(/,/^)/p' "$GEN_AGENT_CONFIG" | grep -oE '"[^"]+"' | tr -d '"' || true)
fi
if [ -z "$agent_names" ]; then
    echo -e "${YELLOW}⚠ Could not extract AGENT_NAMES from generate-agent-config.sh — check skipped.${NC}"
elif [ ! -f "$OPENCODE_CONFIG" ]; then
    echo -e "${YELLOW}⚠ opencode.jsonc not found at $OPENCODE_CONFIG — check skipped.${NC}"
else
    # opencode.jsonc is JSONC: jq fails if comments are present. Try the
    # file as-is first; on failure strip only FULL-LINE // comments (a
    # naive 's|//.*||' would corrupt https:// URLs inside strings) and pipe
    # the stripped stream straight into jq on stdin — no temp file, so an
    # interrupt cannot leak one.
    config_keys=""
    if ! config_keys=$(jq -r '.agent // {} | keys[]' "$OPENCODE_CONFIG" 2>/dev/null); then
        config_keys=$(sed 's|^[[:space:]]*//.*||' "$OPENCODE_CONFIG" | jq -r '.agent // {} | keys[]' 2>/dev/null || true)
    fi
    expected_count=$(printf '%s\n' "$agent_names" | grep -c . || true)
    missing_names=""
    while IFS= read -r name; do
        if [ -z "$name" ]; then
            continue
        fi
        if ! printf '%s\n' "$config_keys" | grep -qxF "$name"; then
            missing_names+="$name"$'\n'
        fi
    done <<< "$agent_names"
    missing_count=$(printf '%s' "$missing_names" | grep -c . || true)
    if [ "$missing_count" -eq 0 ]; then
        echo -e "${GREEN}✓ All $expected_count AGENT_NAMES present as .agent keys in opencode.jsonc.${NC}"
    else
        echo -e "${RED}${BOLD}✗ $missing_count agent name(s) referenced in generate-agent-config.sh but MISSING from opencode.jsonc .agent:${NC}"
        while IFS= read -r name; do
            if [ -n "$name" ]; then
                echo "    ✗ $name"
            fi
        done <<< "$missing_names"
        echo -e "${DIM}  Re-run apply-model-config.sh or reconcile AGENT_NAMES.${NC}"
        log "ADVISORY: $missing_count agent names missing from opencode.jsonc"
        ADVISORY_COUNT=$((ADVISORY_COUNT + 1))
    fi
fi

# ── Check 6: Contract version pins (local vs upstream) ────────────────────────
section "Check 6: Contract version pins (local vs upstream)"
# Local pins: grep this repo for gentle-ai.<name>.v<N> contract references.
local_pins=$(grep -rhoIE 'gentle-ai\.[a-z-]+\.v[0-9]+' "$SCRIPT_DIR" \
    --exclude-dir=.git --exclude-dir=results --exclude-dir=.engram \
    --exclude=check-upstream.sh 2>/dev/null | sort -u || true)
declare -A LOCAL_PIN_MAJORS=()
if [ -n "$local_pins" ]; then
    echo "  Local contract pins:"
    while IFS= read -r pin; do
        if [ -z "$pin" ]; then
            continue
        fi
        echo "    • $pin"
        pname="${pin#gentle-ai.}"
        pname="${pname%.v*}"
        pmaj="${pin##*.v}"
        LOCAL_PIN_MAJORS["$pname"]="$pmaj"
    done <<< "$local_pins"
else
    echo -e "  ${DIM}No local contract pins found (pattern: gentle-ai.<name>.v<N>).${NC}"
fi
fetch_contract_versions
if [ "$FETCH_OK" = false ]; then
    echo -e "${YELLOW}⚠ Could not fetch upstream contracts/ directory (network/API failure).${NC}"
    log "WARNING: upstream contracts fetch failed"
    WARN_COUNT=$((WARN_COUNT + 1))
else
    declare -A CONTRACT_MAJORS=()
    while IFS= read -r line; do
        if [ -z "$line" ]; then
            continue
        fi
        cname="${line#contracts/}"
        cname="${cname%/v*}"
        cmaj="${line##*/v}"
        CONTRACT_MAJORS["$cname"]+="$cmaj "
    done <<< "$CONTRACT_VERSIONS"
    if [ "${#CONTRACT_MAJORS[@]}" -eq 0 ]; then
        echo -e "${YELLOW}⚠ Upstream contracts/ has no versioned directories (unexpected shape).${NC}"
    else
        echo -e "  Upstream contracts/ versions ${DIM}(via $FETCH_SOURCE):${NC}"
        for cname in "${!CONTRACT_MAJORS[@]}"; do
            maj_list=""
            for m in $(printf '%s\n' ${CONTRACT_MAJORS[$cname]} | sort -n); do
                maj_list+="${maj_list:+, }v$m"
            done
            max_major=$(printf '%s\n' ${CONTRACT_MAJORS[$cname]} | sort -n | tail -1)
            echo "    • $cname: $maj_list"
            # Advisory: upstream newer than a local pin, or a brand-new
            # major line (v3+) appears with no local pin to compare.
            reason=""
            if [ -n "${LOCAL_PIN_MAJORS[$cname]:-}" ]; then
                if [ "$max_major" -gt "${LOCAL_PIN_MAJORS[$cname]}" ]; then
                    reason="upstream v$max_major > local pin v${LOCAL_PIN_MAJORS[$cname]}"
                fi
            elif [ "$max_major" -ge 3 ]; then
                reason="upstream reached v$max_major — newer major line than tracked v1/v2"
            fi
            if [ -n "$reason" ]; then
                echo -e "      ${YELLOW}⚠ Advisory: $cname — $reason${NC}"
                ADVISORY_COUNT=$((ADVISORY_COUNT + 1))
            fi
        done
        log "contracts upstream: ${#CONTRACT_MAJORS[@]} contract dir(s) inventoried"
    fi
fi

# ============================================================
# Summary + stamp
# ============================================================
echo ""
if [ "$ADVISORY_COUNT" -gt 0 ]; then
    echo -e "${YELLOW}${BOLD}⚠ Check complete — $ADVISORY_COUNT advisory item(s) above need review.${NC}"
elif [ "$WARN_COUNT" -gt 0 ]; then
    echo -e "${YELLOW}${BOLD}⚠ Check complete with $WARN_COUNT network warning(s) — re-run later (--force) for full results.${NC}"
else
    echo -e "${GREEN}${BOLD}✓ Check complete — no action needed.${NC}"
fi

echo "$today" > "$STAMP_FILE"
log "check-upstream complete (advisories=$ADVISORY_COUNT, warnings=$WARN_COUNT)"
exec 9>&-
exit 0
