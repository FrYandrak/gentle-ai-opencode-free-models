# Feature: daily-check-hardening

## Objective
Make `daily-check.sh` degrade **detectably** instead of aborting or lying: guard every seam that can kill the run under `set -e`, replace fail-blind fallbacks (`x=$(fallo) || x=""`) with sentinel + yellow advisory patterns, and surface chain-staleness advisories.

## Problem
4R review of `daily-check-verify-advisory` (review-78b994b2b086584e, 22 advisory findings) identified two classes of latent defects:
1. **Unguarded seams**: L338-339 (`limits_json`, `priv_arr`) have no `|| fallback` — a jq failure inside `verify_limits_for_ids` (e.g. L351) kills the subshell under `set -e` before `return 0` → full abort (the T9 bug class via another door). L336 `today=$(date ... || true)` can persist an empty verification date.
2. **Fail-blind fallbacks**: `x=$(fallo) || x=""` is indistinguishable from legitimate empty → false success claims (green "✓ Registry is current" when `comm` failed; baseline-empty when snapshot load failed; "Available: 0 / 0" when counts failed; silent no-op when `added_arr` JSON is unparseable).

## Why
Policy header (L12-23) only classifies read sites, not sites feeding persisted writes. Fail-soft is allowed (advisory tool), fail-blind is not: degraded state must be detectably degraded.

## Scope (authorized)
- `daily-check.sh` ONLY (single file owner; no other file may be touched by this feature's tasks).
- Read-only use of `privacy-tier-registry.json` for the chain-staleness advisory (another feature edits it concurrently — do not write it).

## Constraints
- Cheap local checks only (`bash -n`, `jq empty`, smoke runs in a /tmp copy with shims) — no model-testing, no network calls against live sources in tests.
- Advisory character preserved: exits stay 0 for degraded display paths; only own-input integrity errors (T2) may exit non-zero.
- No new dependencies. Minimal, idiomatic bash; no slop (no dead vars, no stale comments).
- English for all code/comments; conventional commit.

## Tasks

### T1 — Guard the verify seams
- L338-339: add guards that **distinguish failure from empty**: sentinel (`__DEGRADED__` or equivalent), consumed downstream with a yellow `⚠ could not verify limits/privacy` advisory; never a "verified" claim when degraded; never a `set -e` abort path.
- L336: `today` must never persist an empty/unset verification date — empty → treated as not-verified + advisory.
- Route: direct inline → delegated (writer). Trigger: non-trivial edits in 1 file with design decisions.

### T2 — Fail loud on own-input parse failure
- L254-255 `added_arr=$(... ) || added_arr="[]"`: unparseable **own** input is an integrity error → non-zero exit + explicit error, NO registry write. Silent no-op success forbidden.
- Route: delegated (same writer).

### T3 — Fail-soft-with-sentinel for read-only display sites
- L628-636 (`comm`): failure → yellow `⚠ could not compare`, never green "✓ Registry is current".
- L691-703 (snapshot load): failure → yellow `⚠ baseline unreadable — re-apply this session`, counts not fabricated from empty baseline without warning.
- L801-805 (counts): failure → `Available: n/a`, never plausible `0 / 0`.
- Mechanism: one `warn_degraded` helper + `DEGRADED` flag; all success claims gated on it. Minimal footprint.
- Route: delegated (same writer).

### T4 — Extend policy header classification
- L12-23 header: add the write-path classes: `own-registry → append`, `own-shim → append`, `curl → registry.*`, `comm/snapshot → date/count claims`.
- Route: delegated (same writer).

### T5 — Chain-staleness advisory (B)
- For each `role_chains` entry: if the first entry's `output_limit < selection_rules.thresholds.general_large_payload` while some tier-eligible free model in `.models` meets the threshold → yellow advisory. Reads registry only (jq); numbers referenced via the thresholds keys, never hardcoded in prose.
- Route: delegated (same writer).

## Acceptance criteria
- [x] All five tasks implemented in `daily-check.sh` only (writer touched no other file; plus one same-class extension: the non-interactive comm guard).
- [x] `bash -n daily-check.sh` exit 0 (parent spot-check re-ran: OK); `jq empty` on fixtures OK.
- [x] No committed tests exist (prior "7-fixture" runs were ad-hoc); reconstructed classifier check: `classifier: 7/7 passed, exit 0`.
- [x] Smoke run in /tmp copy with dead curl shim: exit 0, 5 yellow advisories, 0 false green "Registry is current", 0 false "0 / 0"; healthy add-path still stamps `VERIFIED` + limits; T2 path exits 1 with registry sha unchanged; T5 positive path proven on a synthetic stale-chain fixture (current registry correctly inert).
- [x] No hardcoded thresholds (grep 64000/128000 in daily-check.sh → no matches); no new dependencies; comments match new behavior.

## Progress
- [x] T1..T5 implemented and verified (writer `general`, success; gatekeeper PASS: file-scope, spot checks re-run by parent)
- Work-unit commit: `6963fec` — `fix(daily-check): guard degraded seams and fail-blind fallbacks`
- RDD assess since boundary `f764a82`: risk `high` (process_boundary, shell_source) → `review_due=true` (high_risk); review covered the combined 8-path / 546-line slice (`6963fec` + `412bc59`).
- Native review `review-afd771313840f719` (target `sha256:d5f44fb2…`, high tier, correction budget 200) — all four lenses captured (`risk`, `resilience`, `readability`, `reliability`; every capture `admission_decision: completed`) followed by one refuter batch:
  - `R3-ADDED-VS-UNSORTED` (CRITICAL) → **refuted**: all three `comm` inputs are sorted at their producers (`fetch_zen_models | sort`, `jq | sed | sort`, `load_snapshot | sort`), both call sites carry the `compare_ok` guard, and a chmod-000 baseline run prints the yellow advisory and gates the final line.
  - `R3-DEGRADED-FLAG-SUB` (CRITICAL, `causal_disposition: unknown`) → **not refutable natively**: unknown causality escalates the batch instead of refuting it. Parent verification says the claim is false: at `daily-check.sh:833-838` `warn_degraded` runs in the `if ! …; then` body (main shell, not inside `$(…)`), so `DEGRADED=true` propagates — repro `/tmp/opencode/shellflag.sh` prints `DEGRADED=true` → the yellow "some checks degraded" line, and the refuter's own empirical run agreed.
  - Terminal outcome: `escalated` → `stop / native_stop_required`, `replayability: manual_action_required`, repair `unsupported`. Informational for the maintainer: no correction ran (budget unused), no approval burned, delivery unchanged (ordinary repo policy).
- Follow-up candidate (out of scope, NOT fixed): pre-existing jq bug in the `+ Added to registry` report loop (`daily-check.sh` ~L885): `($reg.models // {}) | has("opencode/" + .)` rebinds `.`, erroring `string and object cannot be added` — the line never prints when models are added. Needs its own task + user authorization.

## Delivery
- Strategy: `ask-on-risk`; forecast ≈ 100-150 authored changed lines (under 400 → single work unit, no chain expected).
