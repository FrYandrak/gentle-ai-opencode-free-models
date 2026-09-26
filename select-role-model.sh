#!/bin/bash
# select-role-model.sh — shared registry-driven role → model selection.
# Sourced by model-selector.sh, generate-agent-config.sh, and daily-check.sh.
#
# Contract (all callers run under `set -e`):
#   - select_role_model ALWAYS returns 0. Failure is signalled ONLY by
#     echoing the string NONE — never by a non-zero exit status.
#   - load_privacy_tier ALWAYS returns 0. Missing/invalid config handling
#     stays in each caller (outside this lib).

# Resolve paths from this file's location — works from any cwd.
SELECT_ROLE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELECT_ROLE_REGISTRY_FILE="$SELECT_ROLE_SCRIPT_DIR/privacy-tier-registry.json"
SELECT_ROLE_CONFIG_FILE="$SELECT_ROLE_SCRIPT_DIR/.privacy-config"

# Source .privacy-config and set PRIVACY_TIER ("" if missing/invalid).
# Callers keep their own missing-config behavior (exit / bootstrap / return).
load_privacy_tier() {
    PRIVACY_TIER=""
    if [ -f "$SELECT_ROLE_CONFIG_FILE" ]; then
        # shellcheck source=/dev/null
        source "$SELECT_ROLE_CONFIG_FILE"
        PRIVACY_TIER="${privacy_max_tier:-}"
    fi
    return 0
}

# registry_thresholds_present — shared fail-closed predicate (R3-1):
# succeeds only when selection_rules.thresholds has both
# general_large_payload and role_minimums. Used by select_role_model and
# by callers that must refuse to operate on a registry without thresholds.
registry_thresholds_present() {
    jq -e '.selection_rules.thresholds.general_large_payload
        and .selection_rules.thresholds.role_minimums' \
        "$SELECT_ROLE_REGISTRY_FILE" >/dev/null 2>&1
}

# select_role_model ROLE MAX_TIER
# Echoes the selected model id, or NONE when no candidate passes all gates
# (free-only AND exists in .models AND numeric privacy_tier prefix
# <= MAX_TIER; missing privacy_tier counts as tier 4).
# Two selection modes, keyed on the canonical role (after role_aliases):
#   - DYNAMIC (role has an entry in selection_rules.thresholds.role_minimums):
#     candidates are all free models (.models ids opencode/big-pickle or
#     *-free) that are tier-eligible AND meet the role's output_limit
#     minimum; highest output_limit wins (ties: id ascending). No
#     big-pickle append. None qualify → NONE.
#   - STATIC (everything else): first match in role_chains.<role> (with the
#     usual big-pickle append) wins.
# Always returns 0.
# Fail-closed (R3-1): even when the registry file exists, a registry
# missing selection_rules.thresholds (general_large_payload + role_minimums)
# refuses selection — one WARNING on stderr, model stays empty → NONE.
# Note: this gate is tier-driven; for roles without a threshold entry,
# output_limit remains the caller's concern (chain via role_chains /
# selection_rules), not a filter here.
select_role_model() {
    local role="${1:-}"
    local max_tier="${2:-}"
    local model=""

    if [ -n "$role" ] && [ -n "$max_tier" ] && [ -f "$SELECT_ROLE_REGISTRY_FILE" ]; then
        if ! registry_thresholds_present; then
            echo "WARNING: privacy-tier-registry.json is missing selection_rules.thresholds — refusing role selection (NONE)." >&2
            model=""
        else
        model=$(jq -r --arg role "$role" --arg max_tier "$max_tier" '
            ($max_tier | tonumber? // 0) as $max
            | (.role_aliases // {}) as $aliases
            | ($aliases[$role] // $role) as $canon
            | . as $reg
            | ($reg.models // {}) as $models
            | (((.selection_rules // {}).thresholds // {}).role_minimums // {}) as $role_minimums
            | (if ($role_minimums | has($canon))
               then
                   # DYNAMIC branch (see selection_rules.thresholds.role_minimums):
                   # highest output_limit among free, tier-eligible models
                   # meeting the minimum; NO big-pickle append; empty → NONE.
                   (($role_minimums[$canon] | tonumber? // 0)) as $min
                   | [ $models | to_entries[]
                       | .key as $id
                       | select($id == "opencode/big-pickle" or ($id | endswith("-free")))
                       | ((.value.privacy_tier // "4") | tostring | split("_")[0] | tonumber? // 4) as $t
                       | select($t <= $max)
                       | ((.value.output_limit // 0) | tonumber? // 0) as $ol
                       | select($ol >= $min)
                       | {id: $id, ol: $ol}
                     ]
                   | sort_by([(-.ol), .id])
                   | (.[0].id // empty)
               else
                   (($reg.role_chains // {})[$canon] // ($reg.role_chains // {}).default // []) as $chain0
                   | (if (($chain0 | length) == 0 or ($chain0[-1] != "opencode/big-pickle"))
                      then ($chain0 + ["opencode/big-pickle"])
                      else $chain0
                      end) as $chain
                   | [ $chain[]
                     | . as $id
                     | select($id == "opencode/big-pickle" or ($id | endswith("-free")))
                     | select($models | has($id))
                     | (($reg.models[$id].privacy_tier // "4") | tostring | split("_")[0] | tonumber? // 4) as $t
                     | select($t <= $max)
                     ][0] // empty
               end)
        ' "$SELECT_ROLE_REGISTRY_FILE" 2>/dev/null) || model=""
        fi
    fi

    if [ -n "$model" ]; then
        echo "$model"
    else
        echo "NONE"
    fi
    return 0
}
