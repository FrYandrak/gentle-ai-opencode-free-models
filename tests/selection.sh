#!/bin/bash
# tests/selection.sh — functional gate for select_role_model.
#
# Plain bash, no framework, no network. Exits 0 when every case passes,
# non-zero otherwise, printing one ok/FAIL line per case plus a summary.
#
# Mechanism: select-role-model.sh resolves the registry from its own location
# (SELECT_ROLE_REGISTRY_FILE="$SELECT_ROLE_SCRIPT_DIR/privacy-tier-registry.json").
# So each fixture gets a throwaway directory containing a COPY of the library
# plus the fixture registry, and the copy is sourced. The library itself needs
# no env-var or path override — it stays untouched.
#
# Usage:
#   bash tests/selection.sh                  run every case
#   bash tests/selection.sh --update-golden  regenerate selection-golden.txt
#
# SELECT_TEST_REGISTRY overrides the registry the LIVE cases read. It exists so
# the golden gate can be proven to catch drift against a deliberately modified
# COPY of the registry, without editing the repo file. Unset in normal runs.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_SOURCE="$REPO_DIR/select-role-model.sh"
LIVE_REGISTRY="${SELECT_TEST_REGISTRY:-$REPO_DIR/privacy-tier-registry.json}"
GOLDEN_FILE="$SCRIPT_DIR/selection-golden.txt"

CANONICAL_ROLES="orchestrator explore research design spec tasks apply verify archive review"

PASSED=0
FAILED=0
CASE_NAME=""
CASE_FAILURES=""

if [ ! -f "$LIB_SOURCE" ]; then
    echo "FAIL setup: $LIB_SOURCE not found" >&2
    exit 1
fi

# --- harness -----------------------------------------------------------------

begin() {
    CASE_NAME="$1"
    CASE_FAILURES=""
}

# expect_eq LABEL EXPECTED ACTUAL
expect_eq() {
    if [ "$2" != "$3" ]; then
        CASE_FAILURES="${CASE_FAILURES}         - $1: expected [$2], got [$3]
"
    fi
}

# expect_not LABEL UNEXPECTED ACTUAL
expect_not() {
    if [ "$2" = "$3" ]; then
        CASE_FAILURES="${CASE_FAILURES}         - $1: expected anything but [$2]
"
    fi
}

# fail_line TEXT — record one indented failure bullet.
fail_line() {
    CASE_FAILURES="${CASE_FAILURES}         - $1
"
}

end() {
    if [ -z "$CASE_FAILURES" ]; then
        printf 'ok   %s\n' "$CASE_NAME"
        PASSED=$((PASSED + 1))
    else
        printf 'FAIL %s\n' "$CASE_NAME"
        printf '%s' "$CASE_FAILURES"
        FAILED=$((FAILED + 1))
    fi
}

note() { printf 'note %s\n' "$1"; }

# select_with REGISTRY_JSON ROLE MAX_TIER
# Sources a copy of the library against REGISTRY_JSON; result lands in
# SEL_OUT, anything the library wrote to stderr in SEL_ERR.
select_with() {
    local registry_json="$1" role="$2" max_tier="$3" dir
    dir="$(mktemp -d)"
    cp "$LIB_SOURCE" "$dir/select-role-model.sh"
    printf '%s' "$registry_json" > "$dir/privacy-tier-registry.json"
    SEL_OUT="$( cd "$dir" && source ./select-role-model.sh \
        && select_role_model "$role" "$max_tier" 2> "$dir/stderr" )"
    SEL_ERR="$(cat "$dir/stderr")"
    rm -rf "$dir"
}

# select_live ROLE MAX_TIER — same, but with the real repo registry.
select_live() {
    local dir
    dir="$(mktemp -d)"
    cp "$LIB_SOURCE" "$dir/select-role-model.sh"
    cp "$LIVE_REGISTRY" "$dir/privacy-tier-registry.json"
    SEL_OUT="$( cd "$dir" && source ./select-role-model.sh \
        && select_role_model "$1" "$2" 2>/dev/null )"
    SEL_ERR=""
    rm -rf "$dir"
}

# legacy_pick REGISTRY_JSON — reproduce the PRE-change sort key
# [tier asc, output desc, context desc, id asc] over the same candidates, so
# the regression case can prove it actually discriminates.
legacy_pick() {
    printf '%s' "$1" | jq -r '
        .models | to_entries
        | map(select(.key == "opencode/big-pickle" or (.key | endswith("-free")))
              | {id: .key,
                 t: ((.value.privacy_tier // "4") | tostring | split("_")[0] | tonumber? // 4),
                 ol: ((.value.output_limit // 0) | tonumber? // 0),
                 ctx: ((.value.context_window // 0) | tonumber? // 0)})
        | sort_by([.t, (-.ol), (-.ctx), .id])[0].id
    '
}

# --- golden assignment table --------------------------------------------------

# live_assignment_table — the 10 canonical roles × tiers 1-4, resolved against
# the live registry, emitted in golden file format and canonical order.
live_assignment_table() {
    local tier role
    for tier in 1 2 3 4; do
        for role in $CANONICAL_ROLES; do
            select_live "$role" "$tier"
            printf '%s %s %s\n' "$tier" "$role" "$SEL_OUT"
        done
    done
}

# golden_body — the assignment lines of the golden file, comments stripped.
golden_body() {
    grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$GOLDEN_FILE" 2>/dev/null
}

# golden_header — the `#` comment lines, verbatim, to be preserved on rewrite.
golden_header() {
    grep '^[[:space:]]*#' "$GOLDEN_FILE" 2>/dev/null
}

# default_golden_header — used only when the golden file does not exist yet.
default_golden_header() {
    cat <<'HEADER'
# tests/selection-golden.txt — expected live role x tier assignment table.
#
# WHAT THIS IS
#   The expected output of select-role-model.sh against the CURRENT
#   privacy-tier-registry.json, for all 10 canonical roles at tiers 1-4
#   (40 combinations). It is a deliberate checkpoint: these are the models that
#   actually get written into the user's agent config on the next refresh.
#
# FORMAT
#   One line per combination: "<tier> <role> <model-id>"
#   Sorted by tier ascending, then by role in $CANONICAL_ROLES order
#   (orchestrator explore research design spec tasks apply verify archive review).
#   Lines starting with '#' are comments; the harness ignores them.
#
# WHAT A DIFF MEANS
#   A mismatch means the selector now assigns a DIFFERENT model than the
#   assignment this project has been operating under. Any drift is a drift:
#   there is no tolerance, no "update if better" heuristic, and a normal run
#   never auto-heals. One changed line can rewrite the model behind an agent.
#
#   The usual cause is legitimate. daily-check.sh ADDS newly published free
#   models to privacy-tier-registry.json, and by policy it never corrects drift
#   in EXISTING entries (selection_rules.limits_reverify). So this file is
#   EXPECTED TO GO STALE whenever the catalog changes, and regenerating it is a
#   CONSCIOUS act, never an automatic one:
#     1. read the diff and decide whether the new assignment is actually
#        correct — output headroom, context window, privacy tier;
#     2. only then run:
#          bash tests/selection.sh --update-golden
#
#   If a line changed and you did NOT expect a catalog change, suspect a
#   hand-edited or inflated output_limit / context_window in the registry:
#   those numbers decide every role now, and nothing corrects them for you.
HEADER
}

# report_golden_drift EXPECTED_FILE ACTUAL_FILE
# Prints one line per differing combination — "tier T role R: expected [X],
# actual [Y]" — then a final machine-readable
# "__SUMMARY__ <changed_combinations> <affected_roles>" line.
# Walks ACTUAL in file order, then reports golden entries that ACTUAL never
# produced, so the output is deterministic rather than hash-ordered.
report_golden_drift() {
    awk '
        FNR == NR { ek[++ec] = $0; em[$1 " " $2] = $3; next }
                 { ak[++ac] = $0; am[$1 " " $2] = $3 }
        END {
            changed = 0; affected = ""; n = 0
            for (i = 1; i <= ac; i++) {
                split(ak[i], f, " "); k = f[1] " " f[2]
                if (!(k in em)) {
                    printf "tier %s role %s: expected [no golden entry], actual [%s]\n", f[1], f[2], am[k]
                    changed++; if (!(f[2] in rset)) { rset[f[2]] = 1; affected = affected (affected == "" ? "" : ",") f[2] }
                } else if (em[k] != am[k]) {
                    printf "tier %s role %s: expected [%s], actual [%s]\n", f[1], f[2], em[k], am[k]
                    changed++; if (!(f[2] in rset)) { rset[f[2]] = 1; affected = affected (affected == "" ? "" : ",") f[2] }
                }
            }
            for (i = 1; i <= ec; i++) {
                split(ek[i], f, " "); k = f[1] " " f[2]
                if (!(k in am)) {
                    printf "tier %s role %s: expected [%s], actual [not produced]\n", f[1], f[2], em[k]
                    changed++; if (!(f[2] in rset)) { rset[f[2]] = 1; affected = affected (affected == "" ? "" : ",") f[2] }
                }
            }
            n = 0
            if (affected != "") n = split(affected, a, ",")
            print "__SUMMARY__ " changed " " n
        }
    ' "$1" "$2"
}

# drift_changed_count EXPECTED_FILE ACTUAL_FILE — first field of the summary.
drift_changed_count() {
    report_golden_drift "$1" "$2" | awk '/^__SUMMARY__/ { print $2; exit }'
}

# drift_affected_roles EXPECTED_FILE ACTUAL_FILE — second field of the summary.
drift_affected_roles() {
    report_golden_drift "$1" "$2" | awk '/^__SUMMARY__/ { print $3; exit }'
}

# write_golden ACTUAL_TEXT — header (preserved verbatim) + body, written
# atomically so an interrupted run cannot leave a truncated golden behind.
write_golden() {
    local tmp
    tmp="$GOLDEN_FILE.tmp.$$"
    {
        if [ -f "$GOLDEN_FILE" ]; then golden_header; else default_golden_header; fi
        echo
        printf '%s\n' "$1"
    } > "$tmp" || { rm -f "$tmp"; return 1; }
    mv "$tmp" "$GOLDEN_FILE" || { rm -f "$tmp"; return 1; }
    return 0
}

# update_golden — the ONLY supported way to change the golden. Prints how many
# lines changed and exits 0. Never invoked during a normal run.
update_golden() {
    local actual body_tmp old_tmp="" changed
    actual="$(live_assignment_table)"
    body_tmp="$(mktemp)"
    printf '%s\n' "$actual" > "$body_tmp"

    if [ -f "$GOLDEN_FILE" ]; then
        old_tmp="$(mktemp)"
        golden_body > "$old_tmp"
        changed="$(drift_changed_count "$old_tmp" "$body_tmp")"
    else
        changed="$(grep -c '' "$body_tmp")"
    fi

    if ! write_golden "$actual"; then
        echo "FAIL: could not write $GOLDEN_FILE" >&2
        rm -f "$body_tmp" "$old_tmp"
        return 1
    fi

    printf 'updated %s — %s of %s lines changed (header comments preserved)\n' \
        "${GOLDEN_FILE#"$REPO_DIR"/}" "$changed" "$(grep -c '' "$body_tmp")"
    rm -f "$body_tmp" "$old_tmp"
    return 0
}

# --- fixtures ----------------------------------------------------------------

# threshold shape shared by every fixture: general floor 64000, review 128000.
THRESHOLDS='"thresholds": { "general_large_payload": 64000, "role_minimums": { "review": 128000 } }'

# A tier-1 model with a small output_limit, a tier-2 model with a large one.
# Both clear the floor. Under the old tier-first sort the tier-1 model won.
REG_TIER_FILTER="{
  \"selection_rules\": { $THRESHOLDS },
  \"models\": {
    \"opencode/alpha-free\": { \"privacy_tier\": \"1_strict\", \"context_window\": 200000, \"output_limit\": 70000, \"best_for\": [] },
    \"opencode/beta-free\":  { \"privacy_tier\": \"2_anonymous_improvement\", \"context_window\": 200000, \"output_limit\": 200000, \"best_for\": [] }
  },
  \"role_chains\": {},
  \"role_aliases\": {}
}"

# A = big context / small output. B = big output / small context.
# Same tier, both above the floor, neither tagged.
REG_CAPABILITY="{
  \"selection_rules\": { $THRESHOLDS, \"context_first_roles\": [\"orchestrator\"] },
  \"models\": {
    \"opencode/ctx-heavy-free\": { \"privacy_tier\": \"2_anonymous_improvement\", \"context_window\": 1000000, \"output_limit\": 70000, \"best_for\": [] },
    \"opencode/out-heavy-free\": { \"privacy_tier\": \"2_anonymous_improvement\", \"context_window\": 128000, \"output_limit\": 300000, \"best_for\": [] }
  },
  \"role_chains\": {},
  \"role_aliases\": {}
}"

# Identical to REG_CAPABILITY but with NO context_first_roles key at all.
REG_CAPABILITY_NO_KEY="{
  \"selection_rules\": { $THRESHOLDS },
  \"models\": {
    \"opencode/ctx-heavy-free\": { \"privacy_tier\": \"2_anonymous_improvement\", \"context_window\": 1000000, \"output_limit\": 70000, \"best_for\": [] },
    \"opencode/out-heavy-free\": { \"privacy_tier\": \"2_anonymous_improvement\", \"context_window\": 128000, \"output_limit\": 300000, \"best_for\": [] }
  },
  \"role_chains\": {},
  \"role_aliases\": {}
}"

# Byte-for-byte tie on output, context and tier; only best_for differs, and the
# tagged id sorts LATER alphabetically so affinity cannot win by id order.
REG_AFFINITY="{
  \"selection_rules\": { $THRESHOLDS },
  \"models\": {
    \"opencode/aaa-free\": { \"privacy_tier\": \"1_strict\", \"context_window\": 200000, \"output_limit\": 100000, \"best_for\": [\"apply\"] },
    \"opencode/zzz-free\": { \"privacy_tier\": \"1_strict\", \"context_window\": 200000, \"output_limit\": 100000, \"best_for\": [] }
  },
  \"role_chains\": {},
  \"role_aliases\": {}
}"

# Same capability tie, different tiers, neither tagged.
REG_TIER_TIE="{
  \"selection_rules\": { $THRESHOLDS },
  \"models\": {
    \"opencode/aaa-free\": { \"privacy_tier\": \"1_strict\", \"context_window\": 200000, \"output_limit\": 100000, \"best_for\": [] },
    \"opencode/zzz-free\": { \"privacy_tier\": \"2_anonymous_improvement\", \"context_window\": 200000, \"output_limit\": 100000, \"best_for\": [] }
  },
  \"role_chains\": {},
  \"role_aliases\": {}
}"

# Total tie: same output, same context, same tier, neither tagged.
REG_ID_TIE="{
  \"selection_rules\": { $THRESHOLDS },
  \"models\": {
    \"opencode/aaa-free\": { \"privacy_tier\": \"1_strict\", \"context_window\": 200000, \"output_limit\": 100000, \"best_for\": [] },
    \"opencode/zzz-free\": { \"privacy_tier\": \"1_strict\", \"context_window\": 200000, \"output_limit\": 100000, \"best_for\": [] }
  },
  \"role_chains\": {},
  \"role_aliases\": {}
}"

# The tagged model is BELOW the general floor; the other clears it.
REG_FLOOR_GUARD="{
  \"selection_rules\": { $THRESHOLDS },
  \"models\": {
    \"opencode/small-tagged-free\": { \"privacy_tier\": \"1_strict\", \"context_window\": 1000000, \"output_limit\": 32000, \"best_for\": [\"apply\"] },
    \"opencode/ok-free\":           { \"privacy_tier\": \"1_strict\", \"context_window\": 200000, \"output_limit\": 100000, \"best_for\": [] }
  },
  \"role_chains\": {},
  \"role_aliases\": {}
}"

# Only one model, at 100000 output: eligible for apply, below the review floor.
# opencode/big-pickle is absent, so the chain fallback has nothing either.
REG_REVIEW_FLOOR="{
  \"selection_rules\": { $THRESHOLDS },
  \"models\": {
    \"opencode/mid-free\": { \"privacy_tier\": \"1_strict\", \"context_window\": 200000, \"output_limit\": 100000, \"best_for\": [] }
  },
  \"role_chains\": {},
  \"role_aliases\": {}
}"

# Nothing clears the floor; the chain's first entry is absent from .models, so
# selection must walk to the second one.
REG_CHAIN="{
  \"selection_rules\": { $THRESHOLDS },
  \"models\": {
    \"opencode/tiny-free\": { \"privacy_tier\": \"1_strict\", \"context_window\": 200000, \"output_limit\": 32000, \"best_for\": [] }
  },
  \"role_chains\": { \"apply\": [\"opencode/absent-free\", \"opencode/tiny-free\"] },
  \"role_aliases\": {}
}"

# No selection_rules.thresholds at all — the fail-closed path.
REG_NO_THRESHOLDS="{
  \"selection_rules\": { \"output_limit_rule\": \"prose only\" },
  \"models\": {
    \"opencode/alpha-free\": { \"privacy_tier\": \"1_strict\", \"context_window\": 200000, \"output_limit\": 200000, \"best_for\": [] }
  },
  \"role_chains\": {},
  \"role_aliases\": {}
}"

# Aliases resolve BEFORE the key order is chosen: conductor -> orchestrator
# must land in context_first_roles, documentation -> spec must not.
REG_ALIAS="{
  \"selection_rules\": { $THRESHOLDS, \"context_first_roles\": [\"orchestrator\"] },
  \"models\": {
    \"opencode/ctx-heavy-free\": { \"privacy_tier\": \"2_anonymous_improvement\", \"context_window\": 1000000, \"output_limit\": 70000, \"best_for\": [] },
    \"opencode/out-heavy-free\": { \"privacy_tier\": \"2_anonymous_improvement\", \"context_window\": 128000, \"output_limit\": 300000, \"best_for\": [] }
  },
  \"role_chains\": {},
  \"role_aliases\": { \"conductor\": \"orchestrator\", \"documentation\": \"spec\" }
}"

# --- cases -------------------------------------------------------------------

case "${1:-}" in
    "")
        ;;
    --update-golden)
        # Refuse to write the golden from an overridden registry: that path
        # exists to prove drift detection, and baking its output into the
        # committed file is exactly the silent reassignment this gate forbids.
        if [ -n "${SELECT_TEST_REGISTRY:-}" ]; then
            echo "refusing to update the golden from SELECT_TEST_REGISTRY=$SELECT_TEST_REGISTRY — unset it to regenerate from the real registry" >&2
            exit 2
        fi
        update_golden
        exit $?
        ;;
    *)
        echo "usage: bash tests/selection.sh [--update-golden]" >&2
        exit 2
        ;;
esac

echo "# tests/selection.sh — select_role_model functional gate"
echo

begin "tier_is_a_filter_not_a_ranking_key"
# The regression case for the whole feature: under the old key order
# [tier asc, output desc, ...] this fixture resolved to the tier-1 model.
expect_eq "legacy sort would pick tier-1" "opencode/alpha-free" "$(legacy_pick "$REG_TIER_FILTER")"
select_with "$REG_TIER_FILTER" apply 2
expect_eq "apply@2 under new sort" "opencode/beta-free" "$SEL_OUT"
end

begin "tier_ceiling_excludes"
select_with "$REG_TIER_FILTER" apply 1
expect_eq "apply@1 filters the tier-2 model out" "opencode/alpha-free" "$SEL_OUT"
end

begin "orchestrator_prefers_context"
select_with "$REG_CAPABILITY" orchestrator 2
expect_eq "orchestrator ranks context first" "opencode/ctx-heavy-free" "$SEL_OUT"
end

begin "other_roles_prefer_output"
for role in apply spec verify review tasks archive design explore; do
    select_with "$REG_CAPABILITY" "$role" 2
    expect_eq "$role ranks output first" "opencode/out-heavy-free" "$SEL_OUT"
done
end

begin "context_first_roles_is_data"
select_with "$REG_CAPABILITY_NO_KEY" orchestrator 2
expect_eq "without the key, orchestrator ranks output first" "opencode/out-heavy-free" "$SEL_OUT"
select_with "$REG_CAPABILITY" orchestrator 2
expect_eq "with the key, orchestrator ranks context first" "opencode/ctx-heavy-free" "$SEL_OUT"
end

begin "affinity_breaks_exact_ties"
select_with "$REG_AFFINITY" apply 1
expect_eq "tagged model wins a total capability tie" "opencode/aaa-free" "$SEL_OUT"
end

begin "tier_breaks_ties_after_capability"
select_with "$REG_TIER_TIE" apply 2
expect_eq "lower tier wins when capability ties" "opencode/aaa-free" "$SEL_OUT"
end

begin "id_breaks_remaining_ties"
select_with "$REG_ID_TIE" apply 1
expect_eq "lower id wins when everything else ties" "opencode/aaa-free" "$SEL_OUT"
end

begin "role_floor_excludes_even_when_tagged"
select_with "$REG_FLOOR_GUARD" apply 1
expect_eq "below-floor model is never picked" "opencode/ok-free" "$SEL_OUT"
end

begin "review_floor_is_enforced"
select_with "$REG_REVIEW_FLOOR" apply 1
expect_eq "apply accepts the 100000-output model" "opencode/mid-free" "$SEL_OUT"
select_with "$REG_REVIEW_FLOOR" review 1
expect_eq "review rejects it and has no candidate" "NONE" "$SEL_OUT"
end

begin "chain_fallback_when_no_candidate"
select_with "$REG_CHAIN" apply 1
expect_eq "chain entry is used when nothing clears the floor" "opencode/tiny-free" "$SEL_OUT"
end

begin "missing_thresholds_returns_NONE"
select_with "$REG_NO_THRESHOLDS" apply 2
expect_eq "fail-closed" "NONE" "$SEL_OUT"
case "${SEL_ERR#*WARNING}" in
    "$SEL_ERR") add_failure_missing=1 ;;
    *) add_failure_missing=0 ;;
esac
if [ "$add_failure_missing" -eq 1 ]; then
    CASE_FAILURES="${CASE_FAILURES}         - no WARNING on stderr
"
fi
end

begin "role_alias_is_resolved"
select_with "$REG_ALIAS" conductor 2
expect_eq "conductor -> orchestrator inherits context_first" "opencode/ctx-heavy-free" "$SEL_OUT"
select_with "$REG_ALIAS" documentation 2
expect_eq "documentation -> spec keeps output first" "opencode/out-heavy-free" "$SEL_OUT"
select_with "$REG_ALIAS" orchestrator 2
expect_eq "canonical role gives the same answer as its alias" "opencode/ctx-heavy-free" "$SEL_OUT"
end

begin "live_registry_resolves_every_role"
# The assertion is a DIFF against tests/selection-golden.txt, not "resolves to
# something". A mass reassignment — the failure mode a bare non-NONE check
# cannot see, because the selector happily returns a different valid model —
# is the thing this case exists to catch.
LIVE_TABLE="$(live_assignment_table)"
ACTUAL_TMP="$(mktemp)"
printf '%s\n' "$LIVE_TABLE" > "$ACTUAL_TMP"
TOTAL_COMBOS="$(grep -c '' "$ACTUAL_TMP")"

if [ ! -f "$GOLDEN_FILE" ]; then
    fail_line "golden file tests/selection-golden.txt does not exist — generate it with: bash tests/selection.sh --update-golden"
else
    GOLDEN_TMP="$(mktemp)"
    golden_body > "$GOLDEN_TMP"
    CHANGED="$(drift_changed_count "$GOLDEN_TMP" "$ACTUAL_TMP")"
    AFFECTED="$(drift_affected_roles "$GOLDEN_TMP" "$ACTUAL_TMP")"

    if [ "$CHANGED" -eq 0 ]; then
        # Every value matches. A golden that is not exactly one line per
        # combination was hand-weakened (a dropped row, a duplicated one), so
        # that is drift too even though no value differs.
        GOLDEN_LINES="$(grep -c '' "$GOLDEN_TMP")"
        if [ "$GOLDEN_LINES" -ne "$TOTAL_COMBOS" ]; then
            fail_line "golden lists $GOLDEN_LINES combinations, live run produced $TOTAL_COMBOS — the golden is not a complete 1-line-per-combination table"
        fi
    else
        fail_line "live assignments drifted from tests/selection-golden.txt — $CHANGED of $TOTAL_COMBOS combinations changed ($AFFECTED of 10 roles affected). If this is a legitimate catalog change, review the diff, then regenerate with: bash tests/selection.sh --update-golden"
        # Herestring, not a pipe: a `cmd | while read` loop runs in a subshell
        # and would throw away everything fail_line appends to CASE_FAILURES.
        DRIFT_TEXT="$(report_golden_drift "$GOLDEN_TMP" "$ACTUAL_TMP" | grep -v '^__SUMMARY__')"
        while IFS= read -r line; do
            [ -n "$line" ] || continue
            fail_line "$line"
        done <<< "$DRIFT_TEXT"
        fail_line "a change you did not expect usually means a hand-edited or inflated output_limit / context_window in privacy-tier-registry.json (selection_rules.limits_reverify: existing-entry drift is never auto-corrected)"
    fi
    rm -f "$GOLDEN_TMP"
fi
rm -f "$ACTUAL_TMP"

# Intent note, not a coincidence pin: the orchestrator flip is a rule, and on
# THIS registry it happens to be a no-op because space-bunny-free dominates
# both capability axes. Case orchestrator_prefers_context is the fixture that
# would differ, and it is asserted above. Read from the same table the golden
# is diffed against, so the note and the assertion can never disagree.
LIVE_ORCH="$(printf '%s\n' "$LIVE_TABLE" | awk '$1 == 2 && $2 == "orchestrator" { print $3 }')"
LIVE_APPLY="$(printf '%s\n' "$LIVE_TABLE" | awk '$1 == 2 && $2 == "apply" { print $3 }')"
if [ "$LIVE_ORCH" = "$LIVE_APPLY" ]; then
    note "on the live registry context_first_roles is currently a no-op: orchestrator and apply both resolve to $LIVE_ORCH (single Pareto-dominant model)"
else
    note "on the live registry orchestrator ($LIVE_ORCH) already differs from apply ($LIVE_APPLY)"
fi
end

begin "deterministic_across_runs"
select_live orchestrator 3
FIRST="$SEL_OUT"
select_live orchestrator 3
expect_eq "repeat call is identical" "$FIRST" "$SEL_OUT"
select_live orchestrator 3
expect_eq "third call is identical" "$FIRST" "$SEL_OUT"
end

# --- summary -----------------------------------------------------------------

echo
if [ "$FAILED" -eq 0 ]; then
    printf 'PASS — %d/%d cases green\n' "$PASSED" "$PASSED"
    exit 0
fi
printf 'FAIL — %d green, %d red (of %d)\n' "$PASSED" "$FAILED" "$((PASSED + FAILED))"
exit 1
