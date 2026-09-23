#!/bin/bash
# Generate OpenCode agent model assignments from privacy tier + registry
# Output: JSON snippet with "model" field for each sdd-*-free-models agent
# Used by apply-model-config.sh to patch opencode.jsonc

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/.privacy-config"
REGISTRY_FILE="$SCRIPT_DIR/privacy-tier-registry.json"

# Shared registry-driven role selection (load_privacy_tier, select_role_model)
source "$SCRIPT_DIR/select-role-model.sh"

# ─── Load privacy tier ──────────────────────────────────────────────────────

if [ ! -f "$CONFIG_FILE" ]; then
    echo '{"error": "No .privacy-config found. Run ./privacy-setup.sh first."}' >&2
    exit 1
fi

load_privacy_tier
TIER="$PRIVACY_TIER"

if [ -z "$TIER" ]; then
    echo '{"error": "Invalid .privacy-config: privacy_max_tier is empty."}' >&2
    exit 1
fi

# ─── Generate agent config ──────────────────────────────────────────────────

# Map agent name suffix → role for model selection.
# Only non-identity mappings live here: the ${AGENT_ROLES[$suffix]:-$suffix}
# fallback already handles every suffix that equals its own role name.
declare -A AGENT_ROLES=(
    ["init"]="spec"
    ["onboard"]="orchestrator"
    ["propose"]="design"
)

# Agent names that exist in opencode.jsonc as sdd-*-free-models
AGENT_NAMES=(
    "gentle-orchestrator"
    "sdd-orchestrator-free-models"
    "sdd-explore-free-models"
    "sdd-research-free-models"
    "sdd-design-free-models"
    "sdd-spec-free-models"
    "sdd-tasks-free-models"
    "sdd-apply-free-models"
    "sdd-verify-free-models"
    "sdd-archive-free-models"
    "sdd-init-free-models"
    "sdd-onboard-free-models"
    "sdd-propose-free-models"
)

# Also emit agent → role pairs for the single jq pass below
# (gentle-orchestrator → orchestrator; sdd-<suffix>-free-models → suffix,
# with the AGENT_ROLES override for non-identity mappings).
pairs=""
for agent_name in "${AGENT_NAMES[@]}"; do
    if [ "$agent_name" = "gentle-orchestrator" ]; then
        role="orchestrator"
    else
        suffix="${agent_name#sdd-}"
        suffix="${suffix%-free-models}"
        role="${AGENT_ROLES[$suffix]:-$suffix}"
    fi
    pairs+="${agent_name}|${role}"$'\n'
done

# Single jq pass: role→model selection for every agent (mirrors the chain
# algorithm in select-role-model.sh), one name lookup per agent, and JSON
# emission via jq -n --arg (no string concatenation). The top-level
# NONE → big-pickle fallback is intentional (always-free default) and
# must stay exactly as written here.
jq -n \
    --slurpfile reg "$REGISTRY_FILE" \
    --arg pairs "$pairs" \
    --argjson tier "$TIER" \
    --arg generated_at "$(date -Iseconds)" '
    $reg[0] as $r
    | ($r.role_aliases // {}) as $aliases
    | ($r.role_chains // {}) as $chains
    | ($r.models // {}) as $models
    | def pick($role; $max):
        ($aliases[$role] // $role) as $canon
        | ($chains[$canon] // $chains.default // []) as $chain0
        | (if (($chain0 | length) == 0 or ($chain0[-1] != "opencode/big-pickle"))
           then ($chain0 + ["opencode/big-pickle"])
           else $chain0 end) as $chain
        | [ $chain[]
            | . as $id
            | select($id == "opencode/big-pickle" or ($id | endswith("-free")))
            | select($models | has($id))
            | ((($models[$id].privacy_tier // "4") | tostring | split("_")[0] | tonumber? // 4)) as $t
            | select($t <= $max)
          ][0] // empty;
    ($pairs | split("\n")
        | map(select(length > 0) | split("|") | {key: .[0], value: .[1]})
        | from_entries) as $agent_roles
    | (pick("orchestrator"; $tier) // "") as $orch
    | {
        _meta: {
            generated_by: "generate-agent-config.sh",
            privacy_tier: $tier,
            generated_at: $generated_at,
            top_level_model: (
                if ($orch == "" or $orch == "NONE") then "opencode/big-pickle"
                else $orch end
            )
        },
        agents: (
            reduce ($agent_roles | to_entries[]) as $e ({};
                (pick($e.value; $tier) // "NONE") as $m
                | .[$e.key] = {
                    model: $m,
                    name: (if $m == "NONE" then $m else ($models[$m].name // $m) end),
                    role: $e.value
                })
        )
    }
'
