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

# select_role_model ROLE MAX_TIER
# Echoes the selected model id, or NONE when no chain member passes all
# gates (free-only AND exists in .models AND numeric privacy_tier prefix
# <= MAX_TIER; missing privacy_tier counts as tier 4). First match wins.
# Always returns 0.
select_role_model() {
    local role="${1:-}"
    local max_tier="${2:-}"
    local model=""

    if [ -n "$role" ] && [ -n "$max_tier" ] && [ -f "$SELECT_ROLE_REGISTRY_FILE" ]; then
        model=$(jq -r --arg role "$role" --arg max_tier "$max_tier" '
            ($max_tier | tonumber? // 0) as $max
            | (.role_aliases // {}) as $aliases
            | ($aliases[$role] // $role) as $canon
            | ((.role_chains // {})[$canon] // (.role_chains // {}).default // []) as $chain0
            | (if (($chain0 | length) == 0 or ($chain0[-1] != "opencode/big-pickle"))
               then ($chain0 + ["opencode/big-pickle"])
               else $chain0
               end) as $chain
            | . as $reg
            | [ $chain[]
              | . as $id
              | select($id == "opencode/big-pickle" or ($id | endswith("-free")))
              | select(($reg.models // {}) | has($id))
              | ((($reg.models[$id].privacy_tier // "4") | tostring | split("_")[0] | tonumber? // 4)) as $t
              | select($t <= $max)
              ][0] // empty
        ' "$SELECT_ROLE_REGISTRY_FILE" 2>/dev/null) || model=""
    fi

    if [ -n "$model" ]; then
        echo "$model"
    else
        echo "NONE"
    fi
    return 0
}
