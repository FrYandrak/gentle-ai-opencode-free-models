# Feature: daily-check-verify-advisory (act on the 4R advisory findings R2-1, R4-001)

## Objective

Clear the two advisory non-blocking findings left by the approved 4R review
`review-6bcac0537eb2eb51` on the `daily-check-verify` feature:

1. **R2-1 (readability, WARNING)** — `verify_new_models` (daily-check.sh
   ~110 lines) combines limits verification, privacy classification, and
   registry mutation in a single bash+jq construct, obscuring the flow and
   making isolated changes risky.
2. **R4-001 (resilience, WARNING, informational)** — the `|| true` fail-soft
   pattern introduced for `live_models=$(fetch_zen_models)` (T9) must be the
   *consistent* policy for every non-critical command substitution under
   `set -e`, so no transient network/tool failure can abort the run and make
   the session hook report "Daily check FAILED".

User decision 2026-09-27: "tomalos" — take both advisory findings as tasks.

## Problem / Why

Both findings were advisory at approval time (never blocking), but they mark
real maintenance debt: the add-time verification pass is the piece most likely
to be edited next (new sources, new fields), and a single non-guarded
substitution anywhere in the script reintroduces the exact T9 outage bug
(fallback dead code, non-zero exit, hook retries every session).

## Scope

### IN

- **T1 (R2-1) Split `verify_new_models` into focused functions** in
  `daily-check.sh`, behavior-preserving:
  - `verify_limits_for_ids <ids_json>` → prints models.dev `{id:{context,output}}`
    for the added ids (extract + validation, fail-soft to `{}`).
  - `verify_privacy_for_added <added>` → prints `[{id,tier,line}]` NDJSON→array
    for added ids with an affirmative Zen-doc statement (fail-soft to `[]`).
  - `write_verified_fields <ids_json> <limits_json> <priv_arr> <today>` → the
    single jq reduce + atomic mktemp-in-dir `mv` + `reg_json` reload + failure
    warning.
  - `verify_new_models` becomes a short orchestrator: empty guard → `ids_json`
    → `today` → call the three helpers → `log` line.
  - The jq reduce program itself may stay intact inside the writer helper; the
    goal is separation of concerns, not rewriting jq.
- **T2 (R4-001) Fail-soft audit + consistent guards**: audit every command
  substitution in `daily-check.sh` for `set -e` abort risk; apply the T9
  pattern (`|| true` or a function that always returns 0, plus a sensible
  fallback value) to every non-critical substitution (network fetches, advisory
  report parsing, display helpers). Critical-path writes that must fail loudly
  keep failing loudly ONLY if they are already covered by an explicit warning
  path. Document the policy in the script header.
- **T3 Verification** (cheap only): `bash -n`; ground-truth classifier 7/7
  (incl. shuffled-block run); synthetic add-path test must reproduce the T7
  evidence exactly (unknown id → tier 4 + UNVERIFIED + defaults;
  `space-bunny-free` → `1_strict` + verbatim evidence + limits 1048576/524288);
  fail-soft run with a dead-network `curl` shim → exit 0 with yellow notices.
- **T4** Work-unit commit + RDD assess (base = current HEAD `319e9bb`).

### OUT

- Any change to classification rules, tiers, limits, thresholds, or registry
  data.
- `report_upstream_drift` logic changes beyond guard fixes (it is report-only).
- Other scripts (`check-upstream.sh` already has its own guards from F1–F6).
- Model evaluation of any kind (free-token budget policy).
- Editing `~/.config/opencode/opencode.jsonc`.

## Constraints

- English artifacts; conventional commits; no AI attribution.
- Behavior-preserving refactor: the T7/T8 acceptance evidence must still hold
  after T1.
- Cheap checks only (`bash -n`, `jq empty`, smokes, shim runs).
- RDD on (global): assess the work-unit commit with
  `gentle-ai review assess --agent opencode --committed-only --base-ref 319e9bb`.
- Direct commits on `master` (repo ordinary policy); push only on explicit
  user go-ahead.
- One writer delegation; orchestrator verifies.

## Tasks

- [x] T0 Create this feature document + Engram mirror (before first source
      write). Mirror topic: `odd/daily-check-verify-advisory/tasks`.
- [x] T1 Split `verify_new_models` into helpers (R2-1).
- [x] T2 Fail-soft audit + consistent `|| true` guards + header policy note
      (R4-001).
- [x] T3 Verification battery (bash -n, ground truth 7/7 + shuffled, synthetic
      add path, dead-network fail-soft run).
- [x] T4 Work-unit commit + RDD assess (+ follow native review if due).

## Acceptance criteria

- `verify_new_models` is a short orchestrator (≤ ~25 lines) delegating to
  three named helpers; each helper has a single responsibility.
- Every non-critical command substitution in `daily-check.sh` is guarded so a
  tool/network failure degrades to a fallback value + yellow notice instead of
  aborting; header documents the policy.
- T7/T8 evidence still reproduces: classifier ground truth exact, synthetic
  add path identical, dead-network run exits 0.
- `bash -n daily-check.sh` green.

## Progress

- 2026-09-27: created (T0). Source: user approved taking both advisory
  findings from `review-6bcac0537eb2eb51` ("tomalos").
- 2026-09-27: T1–T3 done (bounded writer). `verify_new_models` is now a
  19-line orchestrator over `verify_limits_for_ids` / `verify_privacy_for_added`
  / `write_verified_fields` (jq reduce moved byte-for-byte). Fail-soft audit
  covered all ~52 `$(` sites: 16 new guards added, header policy note
  documented; fail-loud kept only for SCRIPT_DIR, registry reads, and the
  registry mktemp/write steps. Verified: `bash -n` green; `jq empty` green;
  classifier 7/7 (incl. shuffled-block run); synthetic add path old≡new
  (stdout, stderr, registry bytes identical) with all T7 assertions passing;
  dead-network `curl` shim run exit 0 with yellow notices; `git status`
  shows only daily-check.sh + this doc. T4 pending (orchestrator).
- 2026-09-28: T4 gatekeeper (orchestrator) re-ran the checks independently —
  diff read (split + 16 guards, jq reduce byte-identical move), `bash -n` exit 0,
  `jq empty` OK, classifier 7/7 with correct fixtures, dead-network `curl` shim
  run in a /tmp copy exit 0 with 3 yellow notices, real worktree still only the
  2 intended files. Work-unit commit: `refactor(daily-check): split
  verify_new_models and guard non-critical substitutions` (base `319e9bb`).
