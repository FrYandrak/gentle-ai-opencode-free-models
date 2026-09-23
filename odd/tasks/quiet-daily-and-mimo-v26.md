# Feature: Quiet daily hook + prefer MiMo-V2.6 Flash

## Objective

Stop the first-terminal daily model report from flooding the shell, expose an
on-demand `models-status` command instead, and stop assigning the broken
`opencode/mimo-v2.5-free` model when `opencode/mimo-v2.6-flash-free` is the
one OpenCode actually serves.

## Problem / Why

- `session-start-hook.sh` (sourced from `~/.bashrc`) prints the full Daily
  Check banner, assignment table, and apply log on the first terminal of the
  day. The user does not want that report unless they ask for it.
- Registry `role_chains` still prefer `opencode/mimo-v2.5-free` for
  orchestrator/design/apply/default. That id is listed on Zen but every
  inference call fails with a server error; live sessions run
  `mimo-v2.6-flash-free` (confirmed via `opencode run` A/B and OpenCode logs).

## Scope

- IN: quiet hook + `models-status` helper; reorder chains so V2.6 precedes
  V2.5; annotate V2.5 as currently broken; re-apply `opencode.jsonc`; README
  hook docs; record prior T6 hash.
- OUT: privacy tier changes; removing V2.5 from the free-model pipeline
  (still listed on Zen); starting a new review lineage; pushing.

## Constraints

- Free-only + tier filter unchanged; Big Pickle stays chain terminal.
- Failures still surface on stderr; success stays silent.
- Artifacts/commit messages in English; no AI attribution.

## Tasks

- [x] Q1 Create this feature document and Engram mirror.
- [x] Q2 Silence `session-start-hook.sh`; log detail to
      `results/session-start.log`; define `models-status` before the
      once-per-day guard. Evidence: sourced hook stdout/stderr = 0 bytes on
      success and on already-stamped day; `models-status` prints full report.
- [x] Q3 Reorder `role_chains` so `mimo-v2.6-flash-free` precedes
      `mimo-v2.5-free` when both appear; note V2.5 server errors.
      Evidence: all chains swapped; select_role_model orchestrator/design/
      apply = `opencode/mimo-v2.6-flash-free` at tier 3.
- [x] Q4 Run `apply-model-config.sh`; verify generate/select/report show
      V2.6 for orchestrator/design/apply/top-level. Evidence: generate
      `_meta.top_level_model` + all mimo agent models = `opencode/
      mimo-v2.6-flash-free`; opencode.jsonc lines 60/186/216/261/266/311/395
      updated (takes effect next OpenCode restart).
- [x] Q5 Point README session-hook section at silent behavior +
      `models-status`.
- [x] Q6 Check off T6 and record hash `c6b8973` in
      `odd/tasks/model-agnostic-selection.md`.
- [x] Q7 Resume bound 4R review `review-47c8fab3bcb43f8d` collect (fresh
      OpenCode process — yesterday's FreeTier block may be gone).
      Bound STATUS reoffered 4/4 slots with unchanged revision; forecast +
      grouped capture next. 4/4 reviewers admitted; final reliability
      capture returned `approved` with 12 advisory non-blocking findings;
      exact `review.acknowledge-approved` executed once → envelope
      `gentle-ai.review-acknowledged/v1`, authority `burned`, consumed
      revision `sha256:c288e752…`.
- [ ] Q8 Work-unit commit(s) with verification evidence.

## Acceptance criteria

- Opening a new day's first shell prints nothing on success.
- `models-status` prints the full daily report.
- `select_role_model orchestrator|design|apply` and top-level model are
  `opencode/mimo-v2.6-flash-free` at tier 3.
- `opencode run --model opencode/mimo-v2.6-flash-free` succeeds.

## Progress

- 2026-09-23: created; diagnosis complete (V2.5 server error refs
  err_396187d8 / err_46609582 / err_ddea9ab1; V2.6 OK).
- 2026-09-23: Q1–Q7 done. Review `review-47c8fab3bcb43f8d` approved and
  acknowledged (authority burned). Next: Q8 work-unit commit(s).
