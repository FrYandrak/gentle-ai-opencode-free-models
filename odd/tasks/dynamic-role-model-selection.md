# Feature: dynamic-role-model-selection

## Objective
Make role→model selection **criteria-driven and dynamic for every role** (no hand-curated first-entry wins): given the chosen privacy tier (`.privacy-config privacy_max_tier`), automatically select the best available free model per role — best privacy first, then most headroom. Keeps `role_chains` as ordered fallback lists only.

## Problem
Root cause diagnosed 2026-09-28: `select_role_model` STATIC branch takes the first tier-eligible entry of hand-curated `role_chains`; `space-bunny-free` (tier 1, 1M ctx, 524288 output, tool_call) is in NO chain, so the orchestrator stayed on `mimo-v2.6-flash-free` (tier 3, 200k, 32000) long after the 2026-09-24 limits correction (mimo 128000→32000, "confirmed cause of the 4R lens finish=length failures") invalidated the chain orderings. Only `review` was dynamic (role_minimums.review) — that is the sole reason reviewers switched. `generate-agent-config.sh` currently emits 10 output_limit WARNINGs (orchestrator/design/apply 32000, spec/tasks/archive 32768, all < general_large_payload 64000).

## Why
The project's purpose ("la gracia") is automatic selection of the most adequate model per task according to the privacy grade chosen. Static chains are data frozen at write time and go stale whenever limits/tiers are corrected. Criteria-driven selection self-corrects.

## Selection decision (locked)
- Candidates: free ids (`opencode/big-pickle` or `*-free`) present in `.models`, `privacy_tier` numeric prefix ≤ `max_tier` (missing tier = 4), `output_limit ≥ min`.
- `min = selection_rules.thresholds.role_minimums[role] // selection_rules.thresholds.general_large_payload` (fail-closed registry guard unchanged).
- Sort: **privacy tier ascending → output_limit descending → context_window descending → id ascending** (privacy is the primary valued parameter; headroom second; deterministic tie-break).
- If no candidate: fall back to `role_chains[role] // role_chains.default`, first tier-eligible existing entry (preserve current big-pickle append semantics).
- If still none: `NONE` (contract: always return 0, echo model or NONE).

## Scope (authorized)
- `select-role-model.sh`, `privacy-tier-registry.json`, `generate-agent-config.sh`, `README.md` (+ `QUICK-REFERENCE.md` if it documents selection), read-only verify of `model-selector.sh`.
- NOT in scope: `~/.config/opencode/opencode.jsonc` (user-owned; orchestrator only reports the application step), live model probing, benchmarks (cancelled by free-token budget policy).

## Constraints
- `select_role_model` remains the single source of selection logic; callers unchanged.
- Registry prose must not restate threshold numbers independently of the thresholds object.
- `bash -n` + `jq empty` + `generate-agent-config.sh` exit 0; cheap fixture tests only (copy script + fixture registry to /tmp — registry file is resolved relative to the script, so a /tmp copy is self-contained).
- English for code/comments/docs; conventional commit; no slop (no stale STATIC-branch comments left behind).

## Tasks

### T1 — Dynamic selection for all roles in `select_role-model.sh`
- Implement the locked decision: single dynamic branch (min from thresholds) + chain fallback + NONE; remove the STATIC/dynamic split; update header comments/contract docs coherently.
- Route: delegated (writer).

### T2 — Registry data + prose
- Reorder every `role_chains` list by the same criteria (membership preserved, order becomes criteria-driven — space-bunny rises to first where eligible).
- Update `selection_rules` prose fields (`review_role_selection` → universal role selection description) without restating numbers; keep `thresholds` object untouched.
- Route: delegated (same writer).

### T3 — generate-agent-config.sh coherence
- Comments/guard still accurate under dynamic selection; NONE→big-pickle top-level fallback unchanged.
- Acceptance signal: regeneration emits **0 output_limit warnings** (was 10) and every agent resolves to a model (no NONE).
- Route: delegated (same writer).

### T4 — Docs
- README "Model selection rules" section (+ QUICK-REFERENCE if applicable): document criteria-driven selection, tier gate, sort order, fallback chains, thresholds keys.
- Route: delegated (same writer).

### T5 — Verification
- `bash -n` all touched scripts; `jq empty` registry; `./generate-agent-config.sh` → 0 warnings, all agents modeled.
- Selection matrix: roles × max_tier {1,2,3,4} via direct `select_role_model` calls → expected picks (tier-1 pool → space-bunny); fallback fixture (remove big models from /tmp copy of registry → chain fallback exercised); NONE path (impossible tier) still returns NONE with exit 0.
- Report each as `<command>: <observed result>`.

## Acceptance criteria
- [x] T1..T5 done; selection logic exists in exactly one place (`select_role_model`).
- [x] 10 generator warnings → 0 (parent spot-check re-ran: stderr empty, exit 0); orchestrator + all 18 agents + top-level resolve to `opencode/space-bunny-free` under tier 3.
- [x] Smoke checks pass: `bash -n` ×3 OK, `jq empty` OK (plus jq --indent 2 round-trip byte-identical), selection matrix 10 roles × tiers {1,2,3} = 30/30 correct with tier gate asserted, fallback fixture exercises chain fallback + tier gate, NONE path returns NONE exit 0; `model-selector.sh` smoke exit 0.
- [x] Known consequence (documented in README as intended): under `privacy_max_tier=3` all roles select `space-bunny-free` — privacy-first dominance is the rational outcome; chains remain ordered fallbacks.

## Progress
- [x] T1..T5 implemented and verified (writer `general`, success; gatekeeper PASS: file-scope = authorized set only, spot checks re-run by parent)
- Work-unit commit: `412bc59` — `feat(models): criteria-driven dynamic role model selection for every role`
- RDD assess since boundary `f764a82`: covered in the same high-risk slice as `6963fec` → native review `review-afd771313840f719` ran over the combined 8-path / 546-line slice. Four lenses + one refuter batch completed; terminal state `escalated` (`native_stop_required`, informational for the maintainer). No finding targets this feature's files — full closure record lives in `odd/tasks/daily-check-hardening.md`.
- Application step (user-owned, not run): `./apply-model-config.sh` must be run by the user to write the new assignments into `~/.config/opencode/opencode.jsonc` (orchestrator never edits that file; prereq warning: it will move top-level model and every agent model to `opencode/space-bunny-free`).

## Delivery
- Strategy: `ask-on-risk`; forecast ≈ 150-250 authored changed lines (under 400 → single work unit, no chain expected).
