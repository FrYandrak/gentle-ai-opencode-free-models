#!/bin/bash
# Daily Model Check — Run at start of each gentle-ai session
# Checks OpenCode Zen for available models, updates registry if changed,
# and outputs today's model assignments based on user's privacy tier.
#
# Usage:
#   ./daily-check.sh                 # non-interactive (session hook path)
#   ./daily-check.sh --interactive   # diff vs registry, confirm before write

set -e

# Fail-soft policy (R4-001): this script runs inside session-start-hook.sh,
# where a non-zero exit makes the hook retry on every shell and report
# "Daily check FAILED". Every NON-CRITICAL command substitution (network
# fetches, advisory/report parsing, display helpers, jq parses of untrusted
# payloads, date/grep/sort chains) is therefore guarded with `|| true` or an
# explicit `|| var=<fallback>` so a transient tool/network failure degrades
# to a fallback value (plus a yellow notice where one exists) and the run
# still exits 0. Fail-loudly is kept only for genuinely critical paths:
# resolving SCRIPT_DIR, reading privacy-tier-registry.json (at startup and
# after writes), and the mktemp/write steps that update
# privacy-tier-registry.json (a broken registry dir must surface loudly).
#
# Write-path classes (site class → effect it feeds; failure policy):
#   own-registry → append           writes that extend privacy-tier-registry.json
#                                   (apply_registry_changes / write_verified_fields
#                                   mktemp+mv): FAIL-LOUD — unparseable OWN input
#                                   aborts with a non-zero exit and NO registry
#                                   write (no silent no-op success).
#   own-shim → append               the same-directory *.tmp.XXXXXX staging shim
#                                   carrying that append: FAIL-LOUD — rm + abort
#                                   on failure; a failed shim is never mv'd in.
#   curl → registry.*               fetched payloads feeding registry.* fields
#                                   (add-time limits/privacy verification):
#                                   FAIL-SOFT fetch + yellow notice; a degraded
#                                   source never stamps a VERIFIED claim.
#   comm/snapshot → date/count claims  diff/baseline output feeding printed
#                                   date/count/status claims: FAIL-SOFT via
#                                   warn_degraded (the DEGRADED flag gates every
#                                   success claim) — never a green "current" line
#                                   or a plausible "0 / 0" from a failed compare.

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
# Degraded-mode advisory (T3)
# ============================================================

# Set ONLY from the main shell: a warn_degraded call inside a $(...)
# substitution runs in a subshell and could not propagate the flag.
# Every success claim (green "current"/"complete" lines, count lines) is
# gated on it — a degraded run prints yellow advisories, never a confident
# claim the failed check could not back, and still exits 0 (see header policy).
DEGRADED=false

warn_degraded() {
    DEGRADED=true
    echo -e "${YELLOW}⚠ $1${NC}"
    return 0
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
# Upstream verification sources (fail-soft under set -e)
# The script runs inside session-start-hook.sh with output redirected to a
# log; a failed fetch must DEGRADE (empty payload + yellow notice on stderr,
# always return 0), never abort the run or make the hook see a non-zero exit.
# ============================================================

fetch_limits_doc() {
    local payload
    payload=$(curl -s --max-time 15 "https://models.dev/api.json" 2>/dev/null || true)
    # Validate structure, not just JSON syntax: a captive-portal or API error
    # page can be valid JSON without the .opencode.models map we depend on.
    if [ -z "$payload" ] || ! printf '%s' "$payload" | jq -e '.opencode.models | type == "object"' > /dev/null 2>&1; then
        echo -e "${YELLOW}⚠ Could not fetch a usable https://models.dev/api.json — limit verification skipped this run.${NC}" >&2
        return 0
    fi
    printf '%s\n' "$payload"
    return 0
}

fetch_privacy_doc() {
    local payload
    payload=$(curl -s --max-time 15 "https://raw.githubusercontent.com/anomalyco/opencode/dev/packages/web/src/content/docs/zen.mdx" 2>/dev/null || true)
    # raw.githubusercontent.com answers 404 with a non-empty body and curl -s
    # still exits 0, so non-empty is not enough — require the §Privacy heading.
    if [ -z "$payload" ] || ! printf '%s' "$payload" | grep -q '^## Privacy'; then
        echo -e "${YELLOW}⚠ Could not fetch the official OpenCode Zen docs — privacy verification skipped this run.${NC}" >&2
        return 0
    fi
    printf '%s\n' "$payload"
    return 0
}

# ============================================================
# Privacy classifier — the official Zen docs are the single source
# ============================================================

# Display name for a bare id (e.g. space-bunny-free) from the
# "| Model | Model ID |" pricing table. Empty result ⇒ no signal (fail-closed).
zen_display_name() {
    local id=$1 name=""
    if [ -z "$id" ] || [ -z "$PRIVACY_DOC" ]; then
        return 0
    fi
    name=$(printf '%s\n' "$PRIVACY_DOC" | awk -F'|' -v id="$id" '
        substr($0, 1, 1) == "|" {
            model = $2
            mid = $3
            gsub(/^[ \t]+|[ \t]+$/, "", model)
            gsub(/^[ \t]+|[ \t]+$/, "", mid)
            if (mid == id) { print model; exit }
        }
    ' 2>/dev/null) || name=""
    printf '%s' "$name"
    return 0
}

# Every line that LITERALLY starts with "- <display name>".
# Literal prefix match (awk index), never a regex: display names contain
# regex metacharacters such as "." and "+" (MiMo-V2.6-Flash Free, Jev 1.13).
privacy_statement() {
    local name=$1
    if [ -z "$name" ] || [ -z "$PRIVACY_DOC" ]; then
        return 0
    fi
    printf '%s\n' "$PRIVACY_DOC" | awk -v p="- $name" 'index($0, p) == 1' || true
    return 0
}

# Precedence is carried by an explicit numeric rank per rule — the LOWEST
# rank wins — so textual order inside this function is irrelevant: a maintainer
# may reorder, insert, or delete these blocks without changing any result.
#   rank 1. zero-retention + no training       → 1_strict
#   rank 2. explicit prompt use for training   → 4_explicit_training
#   rank 3. anonymous (not linked to identity) → 2_anonymous_improvement
#   rank 4. generic "improve the model"        → 3_model_improvement
# Load-bearing overlaps: Nemotron matches ranks 3 AND 4 → rank 3 wins (tier 2);
# Muse Spark 1.3 matches ranks 2 AND 4 → rank 2 wins (tier 4). Empty input or
# no match prints nothing: fail-closed, the caller keeps the current tier.
classify_privacy() {
    local text=$1 lc rank=99 tier=""
    if [ -z "$text" ]; then
        return 0
    fi
    lc=$(printf '%s' "$text" | tr '[:upper:]' '[:lower:]' || true)

    if printf '%s' "$lc" | grep -q 'zero-retention' \
        && printf '%s' "$lc" | grep -q 'does not use your data for model training' \
        && [ 1 -lt "$rank" ]; then
        rank=1
        tier="1_strict"
    fi
    if printf '%s' "$lc" | grep -qE 'permission to use your prompts|train future' \
        && [ 2 -lt "$rank" ]; then
        rank=2
        tier="4_explicit_training"
    fi
    if printf '%s' "$lc" | grep -qE 'not linked to your identity|not linked to identity' \
        && [ 3 -lt "$rank" ]; then
        rank=3
        tier="2_anonymous_improvement"
    fi
    if printf '%s' "$lc" | grep -q 'improve the model' \
        && [ 4 -lt "$rank" ]; then
        rank=4
        tier="3_model_improvement"
    fi

    if [ -n "$tier" ]; then
        echo "$tier"
    fi
    return 0
}

# Verbatim doc line that triggered the winning rule — used as registry evidence.
matched_line_for_tier() {
    local tier=$1 stmt=$2 pattern=""
    case "$tier" in
        1_strict)                pattern='zero-retention' ;;
        4_explicit_training)     pattern='permission to use your prompts|train future' ;;
        2_anonymous_improvement) pattern='not linked to your identity|not linked to identity' ;;
        3_model_improvement)     pattern='improve the model' ;;
        *) return 0 ;;
    esac
    printf '%s\n' "$stmt" | grep -iE -m1 "$pattern" 2>/dev/null || true
    return 0
}

# ============================================================
# Snapshot comparison
# ============================================================

# sort reads the file directly (not `cat | sort`): a pipeline would mask a
# read failure behind sort's exit status, making an unreadable baseline
# indistinguishable from a legitimate empty one. Returns non-zero on failure
# so the caller can warn_degraded instead of silently diffing against "".
load_snapshot() {
    if [ -f "$SNAPSHOT_FILE" ]; then
        sort "$SNAPSHOT_FILE"
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
    # Own-input integrity (T2): both lists are built by this very script, so a
    # parse failure is a bug, not a transient fault — fail loud BEFORE any
    # write (explicit error, non-zero exit, registry untouched). A silent
    # `|| added_arr="[]"` no-op success would hide the bug behind an empty diff.
    if ! added_arr=$(printf '%s' "$added" | jq -Rn '[inputs | select(length > 0)]'); then
        echo -e "${RED}Error: could not parse the added-model list (own input) — registry not written.${NC}" >&2
        exit 1
    fi
    if ! removed_arr=$(printf '%s' "$removed" | jq -Rn '[inputs | select(length > 0)]'); then
        echo -e "${RED}Error: could not parse the removed-model list (own input) — registry not written.${NC}" >&2
        exit 1
    fi
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
                # output_limit (not context_window) is the binding parameter
                # for subagents that emit large payloads — see selection_rules
                # in privacy-tier-registry.json.
                output_limit: 131072,
                tool_call: true,
                best_for: [],
                notes: "limits are add-time defaults pending models.dev verification (see selection_rules.limits_reverify)"
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
# Add-time verification — SECOND pass, immediately after
# apply_registry_changes. The add path keeps writing fail-closed defaults;
# this pass upgrades only what the upstream sources can affirm:
#   - limits known to models.dev   → real context_window/output_limit + note
#   - affirmative Zen-doc statement → classified tier + verbatim evidence + URL
# Anything upstream cannot confirm is left exactly as the add path wrote it
# (tier 4, UNVERIFIED evidence, add-time limit defaults) — fail-closed.
# R2-1 split: verify_new_models is a short orchestrator over three
# single-responsibility helpers:
#   verify_limits_for_ids    — models.dev → {id:{context,output}}
#                              (unavailable doc ⇒ {}; parse failure ⇒ return 1
#                              → orchestrator's __DEGRADED__ sentinel)
#   verify_privacy_for_added — Zen docs → [{id,tier,line}]
#                              (no matched statement ⇒ []; parse failure ⇒
#                              return 1 → orchestrator's __DEGRADED__ sentinel)
#   write_verified_fields    — one jq reduce + atomic mktemp-in-dir mv,
#                              registry write, then reg_json reload
# The jq reduce updates every added id in a single invocation; the write is
# atomic (mktemp-in-dir + mv), then reg_json is reloaded so the assignments
# table sees the updated state.
# ============================================================

verify_new_models() {
    local added=$1
    if [ -z "$added" ]; then
        return 0
    fi

    local ids_json today limits_json priv_arr
    ids_json=$(printf '%s' "$added" | jq -Rn '[inputs | select(length > 0)]') || ids_json="[]"
    if [ "$(jq 'length' <<<"$ids_json")" = "0" ]; then
        return 0
    fi

    # T1: evidence strings embed the date — an empty/unset one must never be
    # persisted as a verification date. No date ⇒ not verified this run:
    # keep the add-path defaults and say so instead of stamping blanks.
    today=$(date +%Y-%m-%d 2>/dev/null) || today=""
    if [ -z "$today" ]; then
        warn_degraded "could not determine today's date — add-time verification skipped, add-path defaults kept"
        log "Add-time verification skipped: date unavailable"
        return 0
    fi

    # T1: both substitutions are fail-loud seams — under `set -e` a helper
    # failure would abort the whole run here. The `||` guard turns failure
    # into a __DEGRADED__ sentinel instead, so it is distinguishable from a
    # legitimately empty result downstream.
    limits_json=$(verify_limits_for_ids "$ids_json") || limits_json="__DEGRADED__"
    priv_arr=$(verify_privacy_for_added "$added") || priv_arr="__DEGRADED__"
    if [ "$limits_json" = "__DEGRADED__" ] || [ "$priv_arr" = "__DEGRADED__" ]; then
        warn_degraded "could not verify limits/privacy for new models this run — fail-closed add-time defaults kept for the degraded part"
        log "Add-time verification degraded (sentinel)"
    fi
    # Consume the sentinel: empty results carry no verification claims into
    # write_verified_fields (fail-closed), they only make the pass a no-op.
    if [ "$limits_json" = "__DEGRADED__" ]; then
        limits_json="{}"
    fi
    if [ "$priv_arr" = "__DEGRADED__" ]; then
        priv_arr="[]"
    fi
    write_verified_fields "$ids_json" "$limits_json" "$priv_arr" "$today"
    log "Add-time verification pass for: $(printf '%s' "$added" | tr '\n' ' ')"
    return 0
}

verify_limits_for_ids() {
    local ids_json=$1 limits_json
    # models.dev payload → {id: {context, output}} for the added ids only.
    # Only complete entries (context AND output present) are ever applied.
    # T1: an unavailable doc is a legitimately empty result ({}), but a jq
    # parse failure is NOT — it returns 1 so the orchestrator can degrade via
    # the __DEGRADED__ sentinel instead of blurring failure into "no limits".
    limits_json="{}"
    if [ -n "$LIMITS_DOC" ]; then
        if ! limits_json=$(printf '%s' "$LIMITS_DOC" | jq -c --argjson ids "$ids_json" '
            [ .opencode.models | to_entries[]
              | select(.key as $k | $ids | index($k))
              | select(.value.limit.context != null and .value.limit.output != null)
              | {key: .key, value: {context: .value.limit.context, output: .value.limit.output}}
            ] | from_entries
        ' 2>/dev/null); then
            return 1
        fi
        if ! printf '%s' "$limits_json" | jq empty > /dev/null 2>&1; then
            return 1
        fi
    fi
    printf '%s\n' "$limits_json"
    return 0
}

verify_privacy_for_added() {
    local added=$1
    local priv_ndjson priv_arr entry id name stmt tier line
    # Zen docs → [{id, tier, line}] for added ids with an affirmative statement.
    priv_ndjson=""
    if [ -n "$PRIVACY_DOC" ]; then
        while IFS= read -r id; do
            if [ -z "$id" ]; then
                continue
            fi
            name=$(zen_display_name "$id")
            stmt=$(privacy_statement "$name")
            tier=$(classify_privacy "$stmt")
            # No display name / no statement / no classified tier ⇒ skip:
            # the fail-closed tier 4 + UNVERIFIED evidence stays untouched.
            if [ -z "$tier" ]; then
                continue
            fi
            line=$(matched_line_for_tier "$tier" "$stmt")
            if [ -z "$line" ]; then
                continue
            fi
            if entry=$(jq -c -n --arg id "$id" --arg tier "$tier" --arg line "$line" \
                '{id: $id, tier: $tier, line: $line}' 2>/dev/null); then
                priv_ndjson="${priv_ndjson}${entry}"$'\n'
            fi
        done <<< "$added"
    fi
    # T1: no matched statements is a legitimately empty result ([]), but a jq
    # parse failure is NOT — return 1 so the orchestrator degrades via the
    # __DEGRADED__ sentinel instead of blurring failure into "nothing found".
    if ! priv_arr=$(printf '%s' "$priv_ndjson" | jq -sc '.' 2>/dev/null); then
        return 1
    fi
    if ! printf '%s' "$priv_arr" | jq empty > /dev/null 2>&1; then
        return 1
    fi
    printf '%s\n' "$priv_arr"
    return 0
}

write_verified_fields() {
    local ids_json=$1 limits_json=$2 priv_arr=$3 today=$4
    local tmp_registry
    tmp_registry=$(mktemp "${REGISTRY_FILE}.tmp.XXXXXX")
    if jq -n \
        --argjson reg "$reg_json" \
        --argjson ids "$ids_json" \
        --argjson limits "$limits_json" \
        --argjson priv "$priv_arr" \
        --arg today "$today" '
        reduce $ids[] as $id ($reg;
            ("opencode/" + $id) as $key
            | if (.models | has($key) | not) then .
              else
                . as $root
                | ($root.models[$key]) as $m
                | ($limits[$id] // null) as $lim
                | ([$priv[] | select(.id == $id)] | .[0]) as $p
                | ($m
                    | (if $lim == null then .
                       else
                         .context_window as $oc
                         | .output_limit as $oo
                         | $lim.context as $nc
                         | $lim.output as $no
                         | ( if $oc != $nc and $oo != $no then "context \($oc)→\($nc), output \($oo)→\($no)"
                             elif $oc != $nc then "context \($oc)→\($nc)"
                             elif $oo != $no then "output \($oo)→\($no)"
                             else "limits confirmed unchanged"
                             end) as $delta
                         | .context_window = $nc
                         | .output_limit = $no
                         | .notes = ("Limits verified against models.dev " + $today + " (" + $delta + ")")
                       end)
                    | (if $p == null then .
                       else
                         .privacy_tier = $p.tier
                         | .evidence = ("VERIFIED " + $today + " against the official OpenCode Zen docs: \u0022" + $p.line + "\u0022")
                         | .privacy_url = "https://opencode.ai/docs/zen/#privacy"
                       end)
                ) as $newm
                | $root | .models[$key] = $newm
              end)
    ' > "$tmp_registry" 2>/dev/null; then
        mv "$tmp_registry" "$REGISTRY_FILE"
    else
        rm -f "$tmp_registry"
        echo -e "${YELLOW}⚠ Add-time verification could not be applied — keeping add-path defaults.${NC}" >&2
    fi

    reg_json=$(jq -c . "$REGISTRY_FILE")
    return 0
}

# ============================================================
# Upstream drift report — ADVISORY ONLY, NEVER mutates the registry.
# Existing entries are report-only: a wrong limit is a manual fix, and a
# tier downgrade would silently unlock a model — that is a human privacy
# decision, so mismatches are printed instead of applied. Models with no
# affirmative statement in the official docs are collected into ONE compact
# fail-closed line instead of one warning each.
# ============================================================

report_upstream_drift() {
    local reported=false
    local id key name stmt tier reg_tier line drift id_list
    local -a no_signal=()

    echo ""
    echo -e "${BOLD}Upstream verification (models.dev + opencode.ai/docs/zen)${NC}"

    # ── Limits half: registry vs models.dev ──
    if [ -z "$LIMITS_DOC" ]; then
        echo -e "  ${YELLOW}⚠ Limit verification skipped: https://models.dev/api.json was unreachable this run.${NC}"
    else
        drift=$(printf '%s' "$LIMITS_DOC" | jq -r --argjson reg "$reg_json" '
            . as $up
            | $reg.models | to_entries[]
            | (.key | sub("^opencode/"; "")) as $id
            | ($up.opencode.models[$id] // null) as $m
            | select($m != null and $m.limit.context != null and $m.limit.output != null)
            | (.value.context_window // -1) as $rc
            | (.value.output_limit // -1) as $ro
            | select($rc != $m.limit.context or $ro != $m.limit.output)
            | [$id, ($rc | tostring), ($m.limit.context | tostring), ($ro | tostring), ($m.limit.output | tostring)]
            | @tsv
        ' 2>/dev/null) || drift=""
        while IFS=$'\t' read -r id rc uc ro uo; do
            if [ -z "$id" ]; then
                continue
            fi
            reported=true
            echo -e "  ${YELLOW}⚠ $id: registry limits differ from models.dev${NC}"
            if [ "$rc" != "$uc" ]; then
                echo -e "      context_window: registry $rc vs models.dev $uc"
            fi
            if [ "$ro" != "$uo" ]; then
                echo -e "      output_limit:  registry $ro vs models.dev $uo"
            fi
            echo -e "      ${YELLOW}Correct privacy-tier-registry.json manually — the daily run never auto-fixes existing entries.${NC}"
        done <<< "$drift"
    fi

    # ── Privacy half: registry tier vs classifier ──
    if [ -z "$PRIVACY_DOC" ]; then
        echo -e "  ${YELLOW}⚠ Privacy verification skipped: the official OpenCode Zen docs were unreachable this run.${NC}"
    else
        while IFS=$'\t' read -r key reg_tier; do
            if [ -z "$key" ]; then
                continue
            fi
            id=${key#opencode/}
            name=$(zen_display_name "$id")
            stmt=$(privacy_statement "$name")
            tier=$(classify_privacy "$stmt")
            if [ -z "$tier" ]; then
                no_signal+=("$id")
            elif [ "$tier" != "$reg_tier" ]; then
                reported=true
                line=$(matched_line_for_tier "$tier" "$stmt")
                echo -e "  ${YELLOW}⚠ $id: registry tier $reg_tier vs Zen docs classify as $tier${NC}"
                echo -e "      ${DIM}$line${NC}"
                echo -e "      ${YELLOW}Review and update privacy-tier-registry.json manually — the daily run never rewrites existing tiers.${NC}"
            fi
        done < <(jq -r '.models | to_entries[] | "\(.key)\t\(.value.privacy_tier // "")"' <<<"$reg_json")

        if [ "${#no_signal[@]}" -gt 0 ]; then
            reported=true
            id_list=$(printf '%s\n' "${no_signal[@]}" | sort | paste -sd, - | sed 's/,/, /g' || true)
            echo -e "  ${YELLOW}⚠ No affirmative privacy statement in the official Zen docs — stays fail-closed at its current tier pending manual verification: ${id_list}${NC}"
        fi
    fi

    # Single green line only when BOTH sources were fetched and nothing to report.
    if [ "$reported" = false ] && [ -n "$LIMITS_DOC" ] && [ -n "$PRIVACY_DOC" ]; then
        echo -e "  ${GREEN}✓ Registry limits match models.dev; privacy tiers match the official Zen docs.${NC}"
    fi

    if [ "$reported" = true ]; then
        log "Upstream verification: drift reported (advisory only, registry untouched)"
    else
        log "Upstream verification: no drift"
    fi
    return 0
}

# ============================================================
# Chain staleness — ADVISORY ONLY, READ-ONLY (jq over reg_json, no writes).
# For each role_chains entry: when the FIRST chain entry's output_limit sits
# below selection_rules.thresholds.general_large_payload while some
# tier-eligible free model (opencode/big-pickle or *-free) in .models already
# meets that threshold, print one yellow advisory per stale chain. Threshold
# and tier values are read from the registry / config by key — never
# hardcoded. Every jq failure degrades to no advisory (guard like call sites).
# ============================================================

report_chain_staleness() {
    local stale_lines chain_id head_id head_limit threshold
    stale_lines=$(jq -r --arg max "${PRIVACY_TIER:-0}" '
        (.selection_rules.thresholds // {}) as $th
        | ($th.general_large_payload // empty) as $gen
        | ($gen | tonumber? // 0) as $min
        | (.models // {}) as $models
        | ((.role_chains // {}) | to_entries[]) as $e
        | ($e.value | if type == "array" then .[0] else empty end) as $head
        | select($head != null)
        | select($models | has($head))
        | (($models[$head].output_limit // 0) | tonumber? // 0) as $ol
        | select($ol < $min)
        | ([ $models | to_entries[]
             | select(.key == "opencode/big-pickle" or (.key | endswith("-free")))
             | ((.value.privacy_tier // "4") | tostring | split("_")[0] | tonumber? // 4) as $t
             | select($t <= ($max | tonumber? // 0))
             | ((.value.output_limit // 0) | tonumber? // 0)
             | select(. >= $min)
           ] | length) as $better
        | select($better > 0)
        | [$e.key, $head, ($ol | tostring), ($min | tostring)] | @tsv
    ' <<<"$reg_json" 2>/dev/null) || stale_lines=""

    if [ -n "$stale_lines" ]; then
        echo ""
        echo -e "${BOLD}Role chain staleness (advisory):${NC}"
        while IFS=$'\t' read -r chain_id head_id head_limit threshold; do
            [ -z "$chain_id" ] && continue
            echo -e "  ${YELLOW}⚠ role chain '$chain_id' starts at $head_id (output_limit $head_limit < general_large_payload $threshold) — a tier-eligible free model with more headroom is available.${NC}"
        done <<< "$stale_lines"
    fi
    return 0
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
# `|| true` is required: under `set -e` an assignment whose command
# substitution fails aborts the whole script, which made the fallback below
# unreachable dead code and made a transient Zen outage fail the entire run
# (the session hook then reported "Daily check FAILED" on every shell).
live_models=$(fetch_zen_models || true)
if [ -z "$live_models" ]; then
    echo -e "${YELLOW}⚠ Could not fetch live model list from OpenCode Zen.${NC}"
    echo -e "${DIM}  Continuing with local registry.${NC}"
    log "WARNING: Could not fetch live models from Zen"
    live_count=0
else
    live_count=$(echo "$live_models" | grep -c . || true)
fi

# ── Upstream verification sources ───────────────────────────────────────────
# Fetched once per run for both the add-time verification (T3) and the drift
# report (T4). Fail-soft: an empty payload skips that half of the verification
# with a yellow notice — the run itself always continues (and exits 0).
LIMITS_DOC=$(fetch_limits_doc)
PRIVACY_DOC=$(fetch_privacy_doc)

if [ "$INTERACTIVE" = true ]; then
    # ── Interactive: diff live list vs the registry (source of truth),
    # confirm before writing, then re-evaluate the assignments below.
    # Fetch warnings were already printed by the fetch step; stdout of
    # fetch_zen_models carries model ids only (no warning pollution).
    registry_models=$(jq -r '.models | keys[]' <<<"$reg_json" | sed 's|^opencode/||' | sort) || registry_models=""
    registry_count=$(echo "$registry_models" | grep -c . || true)

    echo -e "  Live models:     ${CYAN}$live_count${NC}"
    echo -e "  Registry models: ${CYAN}$registry_count${NC}"
    echo ""

    if [ "$live_count" -gt 0 ]; then
        # T3: a failed comm must never masquerade as "both lists empty" — that
        # is exactly the fail-blind path that printed a green "✓ Registry is
        # current" from a broken comparison.
        compare_ok=true
        added=$(comm -13 <(echo "$registry_models") <(echo "$live_models")) || compare_ok=false
        removed=$(comm -23 <(echo "$registry_models") <(echo "$live_models")) || compare_ok=false

        if [ "$compare_ok" = false ]; then
            warn_degraded "could not compare live list with the registry — diff skipped this run"
        elif [ -z "$added" ] && [ -z "$removed" ]; then
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
                # Second pass: real limits + doc-verified tier for the new ids.
                verify_new_models "$added"
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

    # Load previous snapshot (T3): a MISSING snapshot is a legitimate first
    # run (empty baseline, no warning); an UNREADABLE one is degraded — warn
    # instead of silently diffing every live model against an empty baseline.
    prev_snapshot=""
    if [ -f "$SNAPSHOT_FILE" ]; then
        if ! prev_snapshot=$(load_snapshot); then
            prev_snapshot=""
            warn_degraded "baseline unreadable — re-apply this session"
        fi
    fi
    prev_count=0
    if [ -n "$prev_snapshot" ]; then
        prev_count=$(echo "$prev_snapshot" | grep -c . || true)
    fi

    echo -e "  Live models found: ${CYAN}$live_count${NC}"
    echo -e "  Previous snapshot: ${CYAN}$prev_count${NC}"
    echo ""

    # Detect changes
    if [ "$live_count" -gt 0 ]; then
        # T3: same fail-blind guard as the interactive branch — a failed comm
        # must not turn into a green "✓ No changes detected".
        compare_ok=true
        added=$(comm -13 <(echo "$prev_snapshot" 2>/dev/null || echo "") <(echo "$live_models")) || compare_ok=false
        removed=$(comm -23 <(echo "$prev_snapshot" 2>/dev/null || echo "") <(echo "$live_models")) || compare_ok=false

        if [ "$compare_ok" = false ]; then
            warn_degraded "could not compare baseline with the live list — diff skipped this run"
        elif [ -n "$added" ] || [ -n "$removed" ]; then
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
            # `. as $id` before the select: inside `select(...)` the `|` would
            # rebind `.` to $reg.models, and `has("opencode/" + .)` would then
            # concatenate a string with an object (jq error 5 → silent report).
            added_arr=$(printf '%s' "$added" | jq -Rn '[inputs | select(length > 0)]') || added_arr="[]"
            while IFS= read -r model; do
                [ -n "$model" ] && echo -e "    ${GREEN}+ Added to registry: $model${NC} (default tier 4 — verify privacy to upgrade)"
            done < <(jq -rn --argjson reg "$reg_json" --argjson adds "$added_arr" \
                '$adds[] | . as $id | select((($reg.models // {}) | has("opencode/" + $id)) | not)')

            # Batch: add new, remove gone, stamp timestamp — single jq + one write.
            apply_registry_changes "$added" "$removed"
            # Second pass: real limits + doc-verified tier for the new ids.
            verify_new_models "$added"

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
# Upstream verification (advisory only — after the registry update,
# before the assignments table; never writes to the registry)
# ============================================================

report_upstream_drift
report_chain_staleness

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

# Count available (T3): `|| x=0` fabricated a plausible "0 / 0" from a failed
# jq — instead, one guarded compound: any failure degrades the whole line to
# "Available: n/a" + a yellow advisory, never a fake count.
total_count=""
available_count=""
if total_count=$(jq '.models | length' <<<"$reg_json") \
    && available_count=$(jq --arg max "$PRIVACY_TIER" '
        [.models | to_entries[] | select(
            ((.value.privacy_tier // "4" | tostring | split("_")[0] | tonumber? // 4)) <= ($max | tonumber)
        )] | length' <<<"$reg_json"); then
    echo -e "  ${DIM}Available: $available_count / $total_count models at tier $PRIVACY_TIER${NC}"

    if [ "$available_count" -lt 3 ]; then
        echo -e "  ${YELLOW}⚠ Low model count. Consider raising privacy tier with ./privacy-setup.sh${NC}"
    fi
else
    warn_degraded "model counts unavailable"
    echo -e "  ${DIM}Available: n/a models at tier $PRIVACY_TIER${NC}"
fi

echo ""
log "Daily check complete — ${available_count:-n/a} models available at tier $PRIVACY_TIER"
if [ "$DEGRADED" = true ]; then
    echo -e "${YELLOW}⚠ Daily check complete — some checks degraded (see advisories above).${NC}"
else
    echo -e "${GREEN}✓ Daily check complete.${NC}"
fi
