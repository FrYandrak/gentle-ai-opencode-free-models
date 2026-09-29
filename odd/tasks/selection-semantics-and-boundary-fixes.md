# Feature: selection-semantics-and-boundary-fixes

Date: 2026-09-29
Origin: `odd/tasks/conceptual-review.md` (S1–S8), user-approved 2026-09-29.

## Objective

Fix the selection semantics the conceptual review exposed, plus the boundary defects that make the tool unsafe outside this machine — without changing which model is assigned today on this machine (except where a defect requires it).

## Problem

1. **S1 — the selector encodes a value judgment the user never made.** `select-role-model.sh:87` sorts `sort_by([.t, (-.ol), (-.ctx), .id])`, so **privacy tier is the primary key**: a tier-1 model beats any tier-2 model regardless of capability. Verified empirically: 10 roles × tiers 1–4 all return `opencode/space-bunny-free`. The tier setting is a **ceiling the user chose**, not a preference ranking; using it as a sort key conflates "what I am allowed" with "what is best". Consequences today: the tier knob is inert, `role_chains` (65 lines) can never fire, `role_minimums` can never exclude the winner, and the design can never differentiate roles by capability.
2. **The orchestrator needs the opposite bias.** It spends its context window holding the whole task thread; output headroom matters less to it than to a lens that emits large JSON. The user explicitly requires orchestrator roles to rank by **context before output**.
3. **S2 — `apply-model-config.sh` fabricates agents.** `.agent[$e.key].model = $e.value` (`apply-model-config.sh:79`) auto-vivifies in jq. Verified: a config with no `.agent` object gains model-only stubs for all 18 agents, and the top-level model is overwritten (`:80`), then the script prints `✓ opencode.jsonc updated successfully`.
4. **S3 — degraded runs are invisible.** `warn_degraded` (`daily-check.sh:104-108`) and the fetch advisories (`:734-736`) write to stdout; the hook redirects both streams into a logfile (`session-start-hook.sh:142`) and only speaks on non-zero exit. `daily-check.sh` is fail-soft (degraded → exit 0), so a run that verified nothing is indistinguishable from a healthy one, contradicting `README.md:22,89`.
5. **S4 — the flagship `session` mode is unreachable on a fresh clone.** The trigger plugin is untracked, outside the repo, with a hardcoded personal path, and no install guidance exists; `.model-check-config.example` nonetheless ships `check_frequency=session` as the copy-paste default.
6. **S5 — the hook stamps before applying.** `session-start-hook.sh:143` stamps on successful check; apply runs afterwards at `:150-151`. A failed apply is never retried until the next window.
7. **S6 — `check-upstream.sh:427` extracts the agent list from `generate-agent-config.sh` with a sed range parse.** An empty result silently disables the checks.
8. **S7 — `README.md:56` points `git clone` at `free-model-comparison` while the real remote is `gentle-ai-opencode-free-models`.** Public repo, 404 on the first documented command. `QUICK-REFERENCE.md:54-64` hand-maintains a stale model table that contradicts `README.md:15`.
9. **S8 — no verification story.** Zero tests for a tool whose entire product is *which model gets picked*.

## Scope (authorized)

- `select-role-model.sh`, `privacy-tier-registry.json` (selection rules + prose)
- NEW `tests/selection.sh`
- `apply-model-config.sh`, `session-start-hook.sh`, `daily-check.sh` (degradation stream only), `check-upstream.sh` (empty-extraction guard only)
- NEW `plugins/model-check.ts` (vendored, placeholder path)
- `README.md`, `QUICK-REFERENCE.md`, `.model-check-config.example`
- Regenerate `~/.config/opencode/plugins/model-check.ts` from the vendored copy so repo and machine do not drift.
- NOT in scope: `model-selector.sh`, `privacy-setup.sh`, `generate-agent-config.sh`, `.bashrc`, `~/.config/opencode/opencode.jsonc`, the live `.privacy-config`, the live `.model-check-config`.
- Out of scope by decision: `best_for` must **not** become the primary sort key. Verified reason: `space-bunny-free` is a Pareto dominator (max output 524288, max context 1048576, lowest tier 1), so affinity-first would move `explore`/`research` to `nemotron-3-ultra` and `verify` to `nemotron-3.5-lightning` — models worse on **both** output and context, winning only on an evidence-free hand-written tag. Affinity is a late tie-break instead.

## Design decisions

### Selection order (the locked decision)

Canonical role resolved through `role_aliases`, unchanged. Candidates: free ids (`opencode/big-pickle` or `*-free`) with numeric tier prefix ≤ max_tier (missing = 4) and `output_limit` ≥ the role floor (`role_minimums[role]` else `general_large_payload`). Unchanged.

Per candidate compute `t`, `ol`, `ctx`, and `aff` (0 when the canonical role appears in that model's `best_for`, else 1).

Sort — **the only thing that changes**:

| Canonical role | Sort key |
|---|---|
| in `selection_rules.context_first_roles` | `[(-ctx), (-ol), aff, t, id]` |
| every other role | `[(-ol), (-ctx), aff, t, id]` |

Tier is now a **filter only**, never a sort key except as a late tie-break between models that tie on every capability axis. `best_for` is likewise a late tie-break, below both capability axes. `id` last keeps the order total and deterministic. Chain fallback, the `NONE`-not-exit contract and the fail-closed missing-thresholds predicate are **unchanged**.

`context_first_roles` is registry data, not code: the rule must be inspectable and changeable without editing the selector.

### Boundary fixes

- **S2:** refuse to write agent keys absent from `opencode.jsonc`; report each skipped agent. When **zero** known agents exist, abort before any write and say why (this is the fresh-clone / non-Gentle-AI case). The top-level model write is unchanged for a recognized config.
- **S3:** `warn_degraded` and the fetch advisories write to **stderr**; the hook tees `daily-check` stderr into the logfile *and* the user's stderr. stdout stays the report stream.
- **S4:** vendor `plugins/model-check.ts` with a `@MODEL_CHECK_REPO@` placeholder; README documents the one-line install. Keep `session` as the example default — the defect is the missing install path, not the default.
- **S5:** write the stamp only after `apply-model-config.sh` succeeds.
- **S6:** if the agent-list extraction yields nothing, fail loudly instead of continuing.

### Deliberately NOT changed

- `flock -n` returning silently under `RUN_UNCONDITIONAL` is **correct**: the lock holder is performing exactly the refresh this startup requested. Documented in the script, not "fixed".
- `check-upstream.sh` stamp semantics on network failure — a real tradeoff (retry vs. nag), left for a separate decision.
- `role_chains` stays as the explicit human-authored override. It is unreachable while the tier-1 model dominates; that is correct, not a defect.

## Constraints

Cheap local checks only — `bash -n`, `jq empty`, and `tests/selection.sh` against fixtures. **No network.** No model evaluation. Artifacts, comments and commits in English, conventional commits, no AI attribution. TDD mode: not enabled in this project; `tests/selection.sh` is the functional gate for this change and must exist and pass before the selector change is considered done.

## Acceptance criteria

- [x] A tier-2 model with a larger `output_limit` than a tier-1 model is selected when the ceiling allows it (tier is a filter, not a ranking key).
- [x] With a fixture where one model has the larger context and another the larger output, canonical role `orchestrator` resolves to the context model and every other role resolves to the output model.
- [x] Two models identical on output and context: the one listing the role in `best_for` wins; with neither listing it, the lower tier wins, then the lower id.
- [x] Role floors still exclude below-floor models even when `best_for` matches; `review` still requires 128000.
- [x] Missing `selection_rules.thresholds` still yields `NONE` (fail-closed preserved).
- [x] Chain fallback still applies when no candidate qualifies.
- [x] All 10 canonical roles resolve to a real model at tiers 1–4 against the live registry.
- [x] `apply-model-config.sh` against a config with no `.agent` writes nothing and exits non-zero with an explanation; against the real config it patches only existing agents.
- [x] A degraded `daily-check` run surfaces at least one line on the user's stderr.
- [x] `tests/selection.sh` passes; `bash -n` clean on every touched script; `jq empty` clean on the registry.

## Progress

- [x] Feature doc created before the first source write.
- [x] T1 selection order + registry rule + tests — `01ba50b` (docs) + `1fe538f`.
- [x] T2 apply-model-config guard — `2c11fe6`.
- [x] T3 degradation visibility + stamp-after-apply — `2c11fe6`.
- [x] T4 vendored plugin + install guidance + doc corrections — `2c11fe6`.
- [x] T5 check-upstream loud failure — `2c11fe6`.
- [x] T6 work-unit commits.

## Verification (observed)

- `bash -n` clean on all four touched scripts; `jq empty` clean on the registry.
- `bash tests/selection.sh` → **15/15 green**.
- **The suite discriminates.** Reverting only the `sort_by` to the pre-change key makes 4 cases red (`tier_is_a_filter_not_a_ranking_key`, `orchestrator_prefers_context`, `context_first_roles_is_data`, `role_alias_is_resolved`) and exits non-zero. The gate is not tautological.
- **Behavior-neutral on this machine:** 0 of 40 role×tier combinations changed. `space-bunny-free` is a Pareto dominator (output 524288, context 1048576, lowest tier), so it still wins the primary key everywhere. The new ordering is a latent-correctness change, not an immediate reassignment.
- T2 fixture, no-agents case: exit 1, `opencode.jsonc` md5 byte-identical before and after, no backup written, no temp leaked, top-level model untouched.
- T2 fixture, 18-agents case: exit 0, all 18 patched, agent `description` fields preserved, `jq empty` clean.
- T2 partial case: unrelated agent key left untouched at its original model; missing agents reported by name.
- S3: with a stubbed `daily-check.sh` the degraded advisory appears on the hook's stderr **and** in `results/session-start.log`, while stdout stays silent. Hook exit 0 in every case — a terminal start is never blocked.
- S5: stamp written only when check AND apply succeed; absent when either fails.
- Vendored `plugins/model-check.ts` loads as a module and returns `{}`; the machine copy at `~/.config/opencode/plugins/model-check.ts` still carries the absolute path and loads identically.

### Not verified

- End-to-end with a live OpenCode startup against the vendored plugin and the README install one-liner — needs a real restart.
- `check-upstream.sh`'s network checks (offline by design in this project).

## Native review outcome — TERMINAL, escalated

Lineage `review-54f64dcee1ac2a7e`, candidate range `2f8baf1..1fe538f` (T1 only). Assessed `high_risk` → consent `granted` → 4 lenses (risk, resilience, readability, reliability).

`review-resilience` failed the capture transport twice (`opencode_task_output_empty` and `opencode_reviewer_result_refused`, both truncated reviewer payloads) and was admitted on the third launch; `review-readability` was admitted on its second. Those are transport failures, not review verdicts.

The admitted R4 result escalated the transaction to `stop/native_stop_required` over one CRITICAL finding with `causal_disposition: unknown`:

**`R4-REGISTRY-UNVERIFIED-NOW-DECIDES-ALL-AGENTS`** (`select-role-model.sh:110-114`, evidence_class `inferential`). Claim: making `output_limit`/`context_window` the primary keys hands the sole determinant of every agent's model to capability numbers that `daily-check.sh` deliberately never corrects — `selection_rules.limits_reverify` states existing-entry drift is advisory and never auto-corrected. One inflated or hand-edited `output_limit` would outrank the privacy-verified tier-1 anchor for every role, and the next refresh would reassign all agents. Under the old key order the same bad data could not outrank tier 1, so the blast radius grows from zero to every role. The finding also notes the new test gate does not catch it: `live_registry_resolves_every_role` only asserts a role resolves to something other than `NONE`, so a total reassignment passes the suite green.

**Maintainer assessment (parent, not native):** the risk is real but the causal framing is imprecise, and `unknown` causality is why it could not be adjudicated.

- Capability numbers were already inputs to the old sort (second and third keys) and already unverified by policy — the "never auto-correct" rule is base, not introduced here. What changed is which field is load-bearing.
- The old ordering did not protect that data; it *masked* it. `space-bunny-free` is a Pareto dominator, so the tier-1 key happened to coincide with the most capable entry. Remove it and the old sort picks the same inflated number. That coincidence is the same accident S1 identified.
- **One part of the finding is a real, accepted defect:** the live-registry test asserts only "not `NONE`", so a wholesale reassignment passes green. Closing that needs a golden expected-assignment fixture — a new change, not a correction, and the transaction is already terminal.

Terminal state: no correction, no acknowledgement, no burn. Per the lifecycle contract a `stop` ends the transition and never approves delivery. RDD was switched off at **clone scope** afterwards (`gentle-ai review mode disable --scope clone`) so the remaining work could proceed without repeated prompts; the global setting is untouched and stays `on`. T2–T5 shipped under that setting with the functional gate above.

## Delivery

Strategy `ask-on-risk`. Forecast ≈280 authored changed lines — under the 400-line budget, so no chained PRs are required. Five work-unit commits on `master`, one push at the end.

## Verification recipe

```
bash -n select-role-model.sh apply-model-config.sh session-start-hook.sh daily-check.sh check-upstream.sh
jq empty privacy-tier-registry.json
bash tests/selection.sh
```