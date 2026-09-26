# Feature: check-upstream-review-fixes (remediate admitted 4R findings)

## Objective

Remediate the genuine, candidate-caused findings from the native 4R review of the
check-upstream scope (lineage `review-3f9c2a71b5d4e806`, terminal state
`escalated`, maintainer action informational), then deliver the 6-commit stack
by pushing to `origin/master`.

## Problem / Why

The review admitted 4/4 lenses (risk 0, resilience 4, readability 8,
reliability 13 findings). Native escalation came from two CRITICAL reliability
findings with `causal_disposition: unknown` (R3-6, R3-8); the reducer also
recorded fix set `R2-1, R2-2, R3-1..R3-5`. Triage against the actual patch
shows a smaller actionable core: input-validation gaps, a temp-file leak, magic
numbers, and two registry strings that cite evidence outside the repository.
Everything else is a documented design decision, a factually incorrect claim, or
out-of-scope for v1 — recorded under Declined findings with evidence.

## Scope

### IN — fixes

- **F1 (R3-5, R3-2)** `check-upstream.sh` Check 1: validate the fetched
  upstream tag against `^v[0-9]+(\.[0-9]+)+([-+][0-9A-Za-z.-]+)?$`. Invalid
  format → yellow warning + `log` + `WARN_COUNT`, and leave `UPSTREAM_TAG` /
  `UPSTREAM_VER` empty so Checks 2/3/4 skip through their existing `-z` guards.
- **F2 (R3-2)** `compare_versions()`: validate both version strings against
  `^[0-9]+(\.[0-9]+)+([-+][0-9A-Za-z.-]+)?$` **before** ordering; on failure
  set `VERDICT="invalid"` and return 0 (script runs under `set -e`, so the
  function must never fail). Check 2 `case` gains an `invalid)` branch with a
  yellow warning; Check 3 fetches the compare surface only when
  `VERDICT=behind`, otherwise prints a yellow skip line.
- **F3 (R4-1)** Check 5 JSONC fallback: delete `mktemp`/`rm -f` entirely —
  pipe the comment-stripped stream into `jq` on stdin
  (`sed 's|^[[:space:]]*//.*||' file | jq -r ... 2>/dev/null || true`).
  Removes the SIGTERM temp-file leak and two lines of lifecycle code.
- **F4 (R2-4)** Named constants next to `GENTLE_AI_BIN`:
  `CURL_MAX_TIME=15`, `RELEASES_PER_PAGE=10`, `MAX_DIFF_SHOWN=30`; replace the
  5 `--max-time 15`, 1 `per_page=10`, and 2 hard-coded `30` comparison sites.
- **F5 (R3-9)** `privacy-tier-registry.json` `selection_rules.output_limit_rule`:
  stop citing `opencode.db` (not a repository artifact) as evidence; restate the
  `finish: "length"` observation as provider stop-reason behavior seen locally,
  keeping the historical-failure lesson.
- **F6 (R3-8)** `privacy-tier-registry.json` `selection_rules`: add a
  `limits_reverify` string — concrete re-verification procedure (fetch
  `https://models.dev/api.json`, compare `context_window`/`output_limit` for
  every model referenced by `role_chains`, refresh `last_updated`). Update
  `last_updated` to the current local timestamp.

### OUT — declined findings (with evidence)

- **R2-1 (CRITICAL)**: the "4th copy of helpers" duplication marker is the
  design decision the maintainer explicitly requested; extraction is deferred
  until a 5th consumer (recorded in `odd/tasks/check-upstream.md`).
- **R3-1 (BLOCKER)**: stamp written after all checks is the point of
  stamp-gating — a crashed run must not stamp, and re-running after an
  incomplete run is the correct behavior; flock + double-check already
  serializes concurrency.
- **R3-3 (CRITICAL)**: every `fetch_*` resets `FETCH_OK`/`FETCH_SOURCE` at
  entry; the script is single-threaded, `flock` serializes runs, and no
  `fetch_*` function calls another — no corruption path exists.
- **R3-4 (CRITICAL)**: flag parsing (including `--help` exit) happens before
  `exec 9>"$LOCK_FILE"`, so fd 9 is not open at those exits.
- **R3-6 (CRITICAL, unknown)**: `$model` is a jq *variable* bound from data
  (`.value.model as $model`), not text interpolated into the filter — jq
  metacharacters cannot break the lookup.
- **R3-10 (WARNING)**: `curl --max-time 15` bounds the whole operation
  including DNS/connect, so no indefinite connect hang exists.
- **R4-2 / R4-3 (WARNING)**: `mkdir -p` failure aborts under `set -e`;
  lock-open failure prints a yellow warning; the summary already reports
  `WARN_COUNT` with a "re-run later" line and logs every warning — nothing is
  masked as clean.
- **Style/scope declines**: R2-2, R2-3 (globals + long function are the
  documented v1 design, commented in-script), R2-5 (guard parses captured
  output by design to keep stdout pure JSON), R2-6 (enforcement already lives
  in the guard), R2-7, R2-8 (README summary intentionally mirrors the
  registry), R3-7, R3-11 (once/day × ~10 calls vs 60/hr unauthenticated limit),
  R3-13 (advisory scan is human-judged), R4-4 (retry is v2), R3-12 (native
  disposition `pre-existing` → follow-up).

## Constraints

- English artifacts; conventional commits; no AI attribution.
- Cheap checks only (`bash -n`, `jq empty`, smoke runs) — no model evaluation.
- RDD is on (global): assess the work-unit commit against
  `--base-ref 97ce0c1 --committed-only` and follow the returned transition.
- Stay on `master` (repo's ordinary policy: direct commits, `origin/master`
  upstream; the existing 4 unpushed commits already live there).
- Do not touch `~/.config/opencode/opencode.jsonc`.

## Tasks

- [x] T0 Create this feature document + Engram mirror (before first source write).
- [x] T1 Implement F1–F4 in `check-upstream.sh` (+ parent follow-up: the
      "… and N more" arithmetic now uses `MAX_DIFF_SHOWN` too).
- [x] T2 Implement F5–F6 in `privacy-tier-registry.json`.
- [x] T3 Verification: `bash -n check-upstream.sh` OK, `jq empty
      privacy-tier-registry.json` OK, `./check-upstream.sh --help` exit 0,
      `grep -c mktemp` = 0, no hard-coded `--max-time 15`/`per_page=10`/`30`
      comparison literals, `compare_versions` smoke → behind/ahead/in-sync/
      invalid/invalid, live `./check-upstream.sh --force` exit 0 with WARN_COUNT
      0 (real tag `v3.7.0` passed F1) and 3 expected drift advisories.
      Parent spot check re-ran `bash -n`, `jq empty`, and the
      `compare_versions` smoke — all green.
- [ ] T4 Work-unit commit + RDD assess (`--base-ref 97ce0c1 --committed-only`).
- [ ] T5 Push the stack to `origin/master`.

## Acceptance criteria

- Malformed upstream tag or version string degrades to a yellow warning and a
  skipped verdict — never an invalid compare URL or a wrong drift verdict.
- No temp file is created by the JSONC fallback path.
- No hard-coded 15/10/30 literals remain in `check-upstream.sh`.
- Registry strings are verifiable from repository content alone and carry a
  re-verification procedure.
- All cheap checks green; commit + push recorded below.

## Progress

- 2026-09-25: created after the review closed `escalated`; fix set F1–F6 and
  the decline rationale triaged against the admitted lens results.
