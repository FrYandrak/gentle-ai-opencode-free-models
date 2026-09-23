# Feature: Quiet daily hook + prefer MiMo-V2.6 Flash

## Objective

Stop the first-terminal daily model report from flooding the shell, expose an
on-demand `models-apply` command instead (renamed from `models-status` after
PR #1 — the command also writes config), and stop assigning the broken
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

- IN: quiet hook + `models-apply` helper (was `models-status`); reorder chains so V2.6 precedes
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
      `results/session-start.log`; define `models-apply` before the
      once-per-day guard. Evidence: sourced hook stdout/stderr = 0 bytes on
      success and on already-stamped day; `models-apply` (then `models-status`) prints full report.
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
      `models-apply`.
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
- [x] Q8 Work-unit commit(s) with verification evidence.
      Evidence: commit `b7e63f6` on `feat/quiet-daily-hook`
      (5 files, +182/−29). Focused checks: `bash -n session-start-hook.sh`
      OK; sourced hook 0-byte success; `models-apply` full report;
      `select_role_model` orchestrator/design/apply →
      `opencode/mimo-v2.6-flash-free` tier 3; `jq empty`
      privacy-tier-registry.json OK. Runtime: `models-apply` printed the
      daily report on demand. Rollback: revert `session-start-hook.sh`,
      `privacy-tier-registry.json`, `README.md`, and the two `odd/tasks/`
      docs in `b7e63f6` without touching unrelated work. Delivery:
      ask-on-risk, 211 authored lines < 400 → single PR, no chain.
      RDD high_risk on b7e63f6; consent granted; 4R review
      `review-1c359e6ebf4b97d0` approved and acknowledged (authority
      burned).

## Acceptance criteria

- Opening a new day's first shell prints nothing on success.
- `models-apply` prints the full daily report.
- `select_role_model orchestrator|design|apply` and top-level model are
  `opencode/mimo-v2.6-flash-free` at tier 3.
- `opencode run --model opencode/mimo-v2.6-flash-free` succeeds.

## Progress

- 2026-09-23: created; diagnosis complete (V2.5 server error refs
  err_396187d8 / err_46609582 / err_ddea9ab1; V2.6 OK).
- 2026-09-23: Q1–Q7 done. Prior review `review-47c8fab3bcb43f8d` on
  `c6b8973` approved and acknowledged (authority burned).
- 2026-09-23: Q8 done — commit `b7e63f6` on `feat/quiet-daily-hook`
  (branch later renamed from `feat/quiet-daily-mimo-v26`).
  Feature complete; delivery strategy ask-on-risk / single PR (211 lines).
- 2026-09-23: RDD assess on `b7e63f6` vs `c6b8973` → risk `high`
  (`session-start-hook.sh` shell_process). Consent granted; 4R review
  `review-1c359e6ebf4b97d0` approved (10 advisory non-blocking findings);
  exact acknowledge executed → authority `burned`, consumed revision
  `sha256:520b51ea…`. Delivery still human-owned under ordinary policy.
