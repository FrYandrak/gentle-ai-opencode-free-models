# Feature: daily-check-added-report-bug

## Objective
Make the `+ Added to registry` report loop actually print: fix the jq `.` rebind that crashes it every time models are added.

## Problem
`daily-check.sh:885-886` (HEAD) runs:

```jq
$adds[] | select(($reg.models // {}) | has("opencode/" + .) | not)
```

Inside `select(...)`, the `|` rebinds `.` to the models **object**, so `has("opencode/" + .)` evaluates `"opencode/" + <object>` and jq aborts:

```
jq: error (at <unknown>): string ("opencode/") and object ({"opencode/…) cannot be added
exit=5
```

The `while IFS= read -r model` loop above it therefore never receives a line: the green `+ Added to registry: <id> (default tier 4 — verify privacy to upgrade)` line never prints, while the run still exits 0 (the process substitution swallows the jq failure). Discovered by the 4R review of `review-afd771313840f719` (`R3-BASE-JQ-REPORT-BUG`, `pre-existing`) and confirmed with a live repro.

**Location note:** this loop sits in the **non-interactive** branch (`else` of `INTERACTIVE`, L850-898) — the session-hook path. The interactive path (L749-826) has no such report loop, which is why a `--interactive` smoke never reaches it.

## Why
It is a fail-blind display path: the report claims a benefit the run never delivered, which is exactly the defect class the `daily-check-hardening` feature set out to eliminate. It is also the only remaining hardcoded-prefix id construction in the report path.

## Scope (authorized)
- `daily-check.sh` ONLY — the report loop at L885-889 (non-interactive branch).
- NOT in scope: `~/.config/opencode/opencode.jsonc`, registry writes, any other report loop.
- Deliberate non-change: L885 `added_arr=$(…) || added_arr="[]"` stays fail-soft. It is a display-only site (the value feeds the echo loop, never a registry write), so the hardening feature's T2 fail-loud policy — which targets registry-writing paths — does not apply, and its input is script-generated and newline-safe.

## Constraints
- Cheap local checks only (`bash -n`, fixture runs in a /tmp copy with a `curl` shim). No network calls against live sources in tests.
- Advisory character preserved: the loop stays display-only; exit status and registry write behavior do not change.
- English for code/comments; conventional commit; no slop.

## Tasks

### T1 — Fix the jq rebind
Bind the element before the `has` test so the prefix concatenation sees a string:

```jq
$adds[] | . as $id | select((($reg.models // {}) | has("opencode/" + $id)) | not)
```

Semantics preserved: only ids absent from the registry are reported; ids already present stay silent.

- Route: direct inline → delegated (writer). Trigger: single mechanical expression, already-understood fix.

### T2 — Verify
- `bash -n daily-check.sh` → exit 0.
- Unit repro of the expression: buggy form exits 5 with the `string and object cannot be added` error; fixed form exits 0 and emits only the genuinely new id (and nothing when every id already exists).
- End-to-end: /tmp copy of the script + registry with a `curl` shim whose Zen payload carries one id absent from the registry → the green `+ Added to registry:` line prints, no jq error on stderr, script exit 0.
- Report each as `<command>: <observed result>`.

## Acceptance criteria
- [x] `bash -n daily-check.sh` → exit 0 (parent spot-check re-ran: OK).
- [x] The expression no longer errors on `"opencode/" + .`, and filters correctly: only the genuinely new id is reported, ids already in the registry stay silent.
- [x] End-to-end smoke prints `+ Added to registry:` for the shimmed new id with zero jq errors.
- [x] No other line of `daily-check.sh` changed (`git diff --stat` → 4 insertions, 1 deletion, one hunk); repo `privacy-tier-registry.json` untouched (`git status` shows only `daily-check.sh` + this document).

## Verification (observed results)
- `bash -n daily-check.sh`: **exit 0**.
- Expression repro (registry with `mimo-v2.6-flash-free` only, adds `["space-bunny-free","mimo-v2.6-flash-free"]`):
  - HEAD expression → `jq: error … string ("opencode/") and object … cannot be added`, **exit 5**.
  - Fixed expression → **exit 0**, no output (both ids already in the registry — correct silence).
- End-to-end, plain mode, /tmp fixture + `curl` shim (Zen payload = `mimo-v2.6-flash-free`, `zzz-brand-new-free`, `big-pickle`; `zzz-*` absent from the registry):
  - **HEAD**: `Registry will be updated…` printed, **0** `Added to registry` lines, **1** `cannot be added` error on stderr, script **exit 0** (fail-blind).
  - **Fixed**: **1** line `+ Added to registry: zzz-brand-new-free (default tier 4 — verify privacy to upgrade)`, **0** jq errors, script **exit 0**; `mimo-v2.6-flash-free` and `big-pickle` correctly silent.
- Both fixtures write only inside `/tmp/opencode/l885*`; the repository registry sha is unchanged.

## Progress
- [x] Feature document created (ODD step 5) before the first source write.
- [x] T1 fix applied — route: **direct inline** (single mechanical expression, already-understood fix; no research or design decision, so no writer delegation needed; documented here so the skipped delegation is observable).
- [x] T2 verification recorded above as `<command>: <observed result>`.
- Pending: work-unit commit + RDD assess.

## Delivery
- Strategy: `ask-on-risk`; forecast ≈ 1-5 authored changed lines (far under 400 → single work unit).
