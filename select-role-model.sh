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
# Echoes the selected model id, or NONE when nothing qualifies. ALWAYS
# returns 0 — failure is signalled only by the NONE echo.
# Selection is criteria-driven for EVERY role (a single path), keyed on the
# canonical role (after role_aliases):
#   1. Candidates: free ids in .models (opencode/big-pickle or *-free) whose
#      numeric privacy_tier prefix <= MAX_TIER (missing privacy_tier counts
#      as tier 4) and whose output_limit >= min, where min =
#      selection_rules.thresholds.role_minimums[role] when the registry
#      defines one, else selection_rules.thresholds.general_large_payload.
#      The tier is a CEILING the caller chose — it FILTERS candidates and
#      never ranks them above a capable model it is allowed to use.
#   2. Sort: output_limit desc → context_window desc → best_for affinity
#      (0 when the canonical role is listed in that model's best_for, else 1)
#      → privacy tier asc → id asc. The first candidate wins. Affinity and
#      tier are tie-breaks BELOW both capability axes: a hand-written
#      best_for tag or a lower tier must not outrank a strictly stronger
#      model the ceiling already permits.
#      Canonical roles listed in selection_rules.context_first_roles swap
#      the first two keys — context_window desc → output_limit desc — then
#      the same three tie-breaks. That list is registry data; the selector
#      hardcodes no role names.
#   3. No candidate → fallback to role_chains[role] // role_chains.default:
#      first entry that is free AND exists in .models AND tier-eligible
#      (the chain keeps its usual opencode/big-pickle terminal append).
#   4. Still nothing → NONE.
# Fail-closed (R3-1): even when the registry file exists, a registry
# missing selection_rules.thresholds (general_large_payload + role_minimums)
# refuses selection — one WARNING on stderr, model stays empty → NONE.
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
            | (((.selection_rules // {}).thresholds // {}).general_large_payload // 0) as $general
            | (($role_minimums[$canon] // $general) | tonumber? // 0) as $min
            # context_first_roles is registry DATA, not code: a missing, null
            # or non-array value simply means "no role flips the key order".
            | (if (((($reg.selection_rules // {}).context_first_roles // []) | type) == "array")
               then (((($reg.selection_rules // {}).context_first_roles // []) | index($canon)) != null)
               else false
               end) as $ctx_first
            # Criteria-driven pick: free + tier-eligible + output_limit >= min.
            # Tier FILTERS here; it only ranks as a late tie-break. aff is 0
            # when the canonical role is listed in the best_for array
            # (missing/null/non-array best_for = no match, never an error).
            | ([ $models | to_entries[]
                | .key as $id
                | select($id == "opencode/big-pickle" or ($id | endswith("-free")))
                | ((.value.privacy_tier // "4") | tostring | split("_")[0] | tonumber? // 4) as $t
                | select($t <= $max)
                | ((.value.output_limit // 0) | tonumber? // 0) as $ol
                | select($ol >= $min)
                | (if (((.value.best_for // []) | type) == "array")
                   then (if ((.value.best_for // []) | index($canon)) != null then 0 else 1 end)
                   else 1
                   end) as $aff
                | {id: $id, t: $t, ol: $ol,
                   ctx: ((.value.context_window // 0) | tonumber? // 0),
                   aff: $aff}
              ]
              | sort_by(if $ctx_first
                        then [(-.ctx), (-.ol), .aff, .t, .id]
                        else [(-.ol), (-.ctx), .aff, .t, .id]
                        end)
              | (.[0].id // null)) as $picked
            | (if $picked != null
               then $picked
               else
                   # Chain fallback: role_chains[role] // role_chains.default —
                   # first free, existing, tier-eligible entry (big-pickle
                   # terminal append preserved).
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
                     | $id
                     ][0] // null
               end)
            | if . == null then empty else . end
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
