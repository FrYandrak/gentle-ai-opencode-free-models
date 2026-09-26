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

# Registry must expose selection_rules.thresholds (general_large_payload +
# role_minimums) — the GUARD reads it and select_role_model is fail-closed
# without it. No numeric fallback: a missing object is a hard error, not a
# silent default. Uses the shared predicate in select-role-model.sh — R3-1
# consistency (both callers refuse the same way).
if ! registry_thresholds_present; then
    echo '{"error": "privacy-tier-registry.json is missing selection_rules.thresholds (general_large_payload + role_minimums) — required by generate-agent-config.sh."}' >&2
    exit 1
fi

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
# review-* agents emit large JSON payloads; their model must clear
# selection_rules.thresholds.role_minimums.review — enforced by
# select_role_model in select-role-model.sh (single source of selection).
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
    "review-risk"
    "review-readability"
    "review-reliability"
    "review-resilience"
    "review-refuter"
)

# Select models in bash via the shared lib (single source of truth — the
# role→model algorithm lives ONLY in select-role-model.sh) and collect
# agent|role|model triples for the JSON emission pass below
# (gentle-orchestrator → orchestrator; review-* → review;
# sdd-<suffix>-free-models → suffix, with the AGENT_ROLES override for
# non-identity mappings).
selections=""
for agent_name in "${AGENT_NAMES[@]}"; do
    if [ "$agent_name" = "gentle-orchestrator" ]; then
        role="orchestrator"
    elif [[ "$agent_name" == review-* ]]; then
        # review-* → review: dynamic selection via
        # selection_rules.thresholds.role_minimums (highest output_limit)
        role="review"
    else
        suffix="${agent_name#sdd-}"
        suffix="${suffix%-free-models}"
        role="${AGENT_ROLES[$suffix]:-$suffix}"
    fi
    model="$(select_role_model "$role" "$TIER")"
    selections+="${agent_name}|${role}|${model}"$'\n'
done

# JSON emission only — NO model selection happens here. Model selection
# lives in select-role-model.sh (select_role_model) as the single source of
# truth; this jq pass merely splits the agent|role|model triples computed
# above and looks up display names. The top-level NONE → big-pickle fallback
# is intentional (always-free default) and must stay exactly as written
# here. Output is captured so the guard below can inspect it before it
# reaches stdout (stdout must stay pure JSON for apply-model-config.sh).
generated=$(jq -n \
    --slurpfile reg "$REGISTRY_FILE" \
    --arg selections "$selections" \
    --argjson tier "$TIER" \
    --arg generated_at "$(date -Iseconds)" '
    ($reg[0].models // {}) as $models
    | ($selections | split("\n")
        | map(select(length > 0) | split("|")
            | {key: .[0], value: {role: .[1], model: .[2]}})
        | from_entries) as $sel
    | ($sel["gentle-orchestrator"].model // "") as $orch
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
            $sel | with_entries(
                .value.model as $m
                | .value = {
                    model: $m,
                    name: (if $m == "NONE" then $m else ($models[$m].name // $m) end),
                    role: .value.role
                })
        )
    }
')

# OUTPUT_LIMIT GUARD — see odd/tasks/review-lens-model.md
# Warn (stderr only — stdout stays pure JSON for apply-model-config.sh) when
# an assigned model cannot emit large payloads. Thresholds come from
# selection_rules.thresholds in the registry: per agent,
# max(general_large_payload, role_minimums[role] // 0). Warning only — a
# regeneration never hard-fails (exit stays 0).
while IFS=$'\t' read -r guard_agent guard_model guard_limit guard_threshold; do
    [ -n "$guard_agent" ] || continue
    echo "WARNING: agent '$guard_agent' assigned model '$guard_model' with output_limit=$guard_limit (< threshold $guard_threshold)." >&2
    echo "  Large-payload subagents need a bigger budget — see \"Model selection rules\" in README / selection_rules.thresholds in privacy-tier-registry.json." >&2
done < <(jq -r --slurpfile reg "$REGISTRY_FILE" '
    ($reg[0].selection_rules.thresholds.general_large_payload | tonumber) as $general
    | ($reg[0].selection_rules.thresholds.role_minimums // {}) as $role_minimums
    | .agents | to_entries[]
    | select(.value.model != "NONE")
    | .key as $agent | .value.model as $model | .value.role as $role
    | ($reg[0].models[$model].output_limit // 0) as $ol
    | ([$general, (($role_minimums[$role] // 0) | tonumber)] | max) as $thr
    | select($ol < $thr)
    | [$agent, $model, $ol, $thr] | @tsv
' <<<"$generated")

printf '%s\n' "$generated"
