# Feature: review-lens-model (fix 4R lens `finish=length` exhaustion)

## Objective

Give the Gentle-AI 4R review lens agents (`review-risk`, `review-readability`,
`review-reliability`, `review-resilience`, `review-refuter`) an explicit model
with enough OUTPUT headroom, so lens captures stop dying with
`opencode_task_output_empty`, and propagate the fix + root-cause data into this
project so anyone hitting the same wall benefits.

## Problem / Why

During lineage `review-84f89121c9908a08` (candidate `check-upstream.sh`, 4
paths, ~591 lines), resilience and reliability lens captures failed ~6 times
each with `opencode_task_output_empty`. Root cause confirmed in
`~/.local/share/opencode/opencode.db`: the reviewer session ends with
`finish: "length"` — reasoning consumed the whole output budget before any JSON
was emitted (`reasoning: 32000, output: 0`).

The lens agents had **no `model`** of their own, so they inherited the global
default `opencode/mimo-v2.6-flash-free`, whose **output limit is 32000 tokens**
(per models.dev — NOT the 128000 currently recorded in
`privacy-tier-registry.json`). Not a context-window problem: the composed
prompt fits easily; the model runs out of *output* tokens while still thinking.

## Scope

- IN:
  - **[done locally]** `~/.config/opencode/opencode.jsonc`: explicit
    `"model": "opencode/nemotron-3-ultra-free"` on the 5 review agents
    (backup: `/tmp/opencode/opencode.jsonc.bak-lens-model`). Rationale:
    models.dev output 128000 (4x mimo), 1M context, reasoning + tool_call,
    privacy tier 2 (stricter than mimo's tier 3), "excellent instruction
    following" per our own registry.
  - Correct stale `output_limit` / `context_window` values in
    `privacy-tier-registry.json` against models.dev (known wrong: mimo-v2.6
    128000→32000, nemotron-3-ultra 32000→128000, nemotron-3.5-lightning
    32000→262144, ling-3.0-flash-fin 262144→**32768** — the last one means ling
    would have been a BAD pick for this failure mode).
  - Manage `review-*` agents in `generate-agent-config.sh` (add to
    `AGENT_NAMES` + a `review` role chain in the registry) so the project
    assigns them a capable model instead of relying on a hand edit.
  - README Troubleshooting row: lens `opencode_task_output_empty` →
    `finish:length` → output limit too small → assign the lens agents a model
    with a large `output_limit`.
  - **Warning**: the `review-*` blocks are `__managed_by: gentle-ai/sdd` —
    `gentle-ai sync` may overwrite the hand edit; the project-managed path
    (generate/apply-model-config) is the durable fix.
- OUT:
  - Restarting OpenCode (separate user decision; config is not hot-reloaded).
  - Touching `review-validator` (different phase, low token profile).
  - Model-quality scoring of any kind (cancelled per AGENTS.md).

## Constraints

- English artifacts; conventional commits; no AI attribution.
- Cheap checks only (`bash -n`, `jq empty`); no free-token model evaluation.
- RDD on: assess after each work-unit commit.
- Never assign paid models; free = `-free` suffix or big-pickle whitelist.

## Tasks

- [x] T0 Create this feature document (registration of the next todo).
- [x] T1 Local config fix: `model` on 5 review agents (validated `jq empty`).
- [x] T2 Correct stale `output_limit`/`context_window` in
      `privacy-tier-registry.json` against models.dev. (Evidence: `jq empty`
      OK; all corrected values match models.dev fetched 2026-09-24; top-level
      `selection_rules` block added with the output_limit rule verbatim.)
- [x] T3 Manage `review-*` in `generate-agent-config.sh` (`review` role chain)
      + README Troubleshooting entry; run `bash -n` + `jq empty` + regen smoke.
      (Evidence: `review` chain = nemotron-3-ultra + nemotron-3.5-lightning;
      regen smoke emits valid JSON with `review-*` → nemotron-3-ultra-free and
      prints output_limit warnings on stderr; README "Model selection rules"
      subsection + troubleshooting row added; `bash -n` clean on all 3 scripts.)
- [ ] T4 Work-unit commit(s) + RDD assess.

## Acceptance criteria

- Registry limits match models.dev for every model used in role chains.
- `review-*` agents get an explicit model from the registry chain (no reliance
  on a hand edit that `gentle-ai sync` can revert).
- README documents the `finish:length` failure mode and the fix.

## Progress

- 2026-09-24: created. Diagnosis: 4R lens failures are output-limit
  exhaustion (`finish=length`), not context-window. T1 applied locally after
  user approval ("cambiar de modelo... dejarlo bien registrado").
- 2026-09-24: T2 done (registry limits corrected vs models.dev +
  `selection_rules` block) and T3 done (`review` role chain, `review-*` in
  `generate-agent-config.sh` with OUTPUT_LIMIT GUARD, README selection-rules
  subsection + troubleshooting row, markers in `daily-check.sh` /
  `select-role-model.sh`). Verification: `bash -n` ×3 OK, `jq empty` OK,
  regen smoke OK (stdout pure JSON, warnings on stderr). Commits recorded in
  T4; RDD assess left to orchestrator.
