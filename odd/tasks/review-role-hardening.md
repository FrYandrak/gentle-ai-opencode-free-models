# Feature: review-role-hardening (dynamic high-output reviewer binding)

## Objective

Make the `review` role select models **dynamically by highest `output_limit`**
among eligible free models (min 128000, registry-driven), remove the
big-pickle fallback from reviewers entirely, make the OUTPUT_LIMIT GUARD read
its thresholds from the registry (no hardcoded numbers), and document the two
thresholds (64000 vs 128000) clearly for developers and users.

## Problem / Why

Native 4R review `review-4d181d4d9e1381be` (commits `c197244`+`97ce0c1`)
closed `escalated` (informational). Triage against evidence:

- **R3-001/R3-002 (CRITICAL, real)**: `pick()` appends `opencode/big-pickle`
  (output_limit **32000** — verified) to any chain not ending with it,
  including the review chain. If both nemotrons leave Zen (free models rotate
  — the premise of this project), review agents silently fall back to the
  exact model class that caused the original `finish=length` failures.
  User decision: **big-pickle stays fallback for everything else, but is
  OUT for reviewers.**
- **R2-001/R2-007/R3-003/R3-007 (threshold confusion, real as docs/design)**:
  guard warns at 64000 while the review requirement is 128000, with no
  explanation of the gap. Fix: registry-driven thresholds + clear docs.
- **R2-002 (real)**: 64000 hardcoded in the guard jq — drift risk vs registry.
- **R2-003 (real)**: the output_limit explanation is duplicated in 4 places
  (registry, README, 2 script comments). Fix: registry = single source,
  everything else points to it.
- **R3-004 (real)**: `selection_rules` was documentation-only; code must now
  read the thresholds it defines.
- **R3-005 (real, minor)**: auto-added models get unverified default limits.
- **R2-006 (real, minor)**: feature doc `review-lens-model.md` duplicates
  registry data. Fix: authoritative-source note.
- **R3-006 (pre-existing, minor)**: jev-1.13-free has output_limit 0 (not a
  text model). Fix: clarify in its notes (no behavior change).
- **R4-1 (FALSE POSITIVE — declined with evidence)**: claimed the guard path
  `.models` does not exist. Verified: `jq '.models[...].output_limit'` →
  128000; `.privacy_tiers[...]` does NOT hold limits. Declined.
- **R2-004 (pre-existing pattern — declined)**: `AGENT_NAMES` hardcoding
  matches the pre-existing sdd-* pattern; not introduced by that candidate.
- **R4-2/R2-005 (chain too small / no fallback)**: superseded by the dynamic
  selection design below.

User decision on reviewer selection: bind reviewers automatically to the
model with the **highest output_limit** among those with sufficient capacity
(`output_limit >= 128000`), tier-eligible and free. No static chain.

## Scope

- IN:
  - `privacy-tier-registry.json`:
    - `selection_rules.thresholds` = `{ "general_large_payload": 64000,
      "role_minimums": { "review": 128000 } }` (machine-readable; code reads
      ONLY this object).
    - Prose: `large_payload_threshold` and `review_role_chain` rewritten to
      reference `thresholds` (no duplicated numbers in prose) +
      `threshold_rationale` explaining 64000 vs 128000 (both derived from
      the observed 32000 `finish=length` failure: 64000 = general warning
      zone at 2× the failure; 128000 = 4× baseline required for lens payloads
      once reasoning overhead is accounted).
    - **Remove** static `role_chains.review` array (dynamic rule supersedes
      it; keeping both = drift, per R3-004). Other chains keep the big-pickle
      fallback exactly as today.
    - jev-1.13-free `notes`: add "structured decision model — not text
      generation (output_limit 0)".
  - `select-role-model.sh` (`select_role_model`): if the canonical role has
    an entry in `selection_rules.thresholds.role_minimums` → dynamic branch:
    candidates = free ids (`*-free` or big-pickle) present in `.models`,
    tier ≤ max, `output_limit >= min`, sorted by `output_limit` desc → first;
    **no big-pickle append**; empty → NONE. Non-dynamic roles: existing
    chain + big-pickle-append logic unchanged.
  - `generate-agent-config.sh`:
    - Inline jq `pick()` mirrors the same dynamic branch (comment already
      says it must mirror select-role-model.sh).
    - GUARD: thresholds from registry (`thresholds.general_large_payload`,
      per-agent `max(general, thresholds.role_minimums[role])` using the
      generated `agents[].role`); no hardcoded 64000; message shows which
      threshold applied.
    - Comment updates: point to registry instead of restating numbers.
  - `daily-check.sh`: auto-add template gets a `notes` marker
    "limits are add-time defaults pending models.dev verification (see
    selection_rules.limits_reverify)".
  - README "Model selection rules": rewrite for both audiences — the two
      thresholds with rationale, the dynamic reviewer selection (highest
      output_limit, min 128000, no fallback → visible NONE skip), pointer to
      the registry as source of truth. Update the troubleshooting row
      ("role chain" → dynamic selection).
  - `QUICK-REFERENCE.md`: source-of-truth line mentions `selection_rules`
    alongside `role_chains`.
  - `odd/tasks/review-lens-model.md`: authoritative-source note (R2-006).
- OUT:
  - Space-bunny privacy/tier work — **user consultation required first**
    (official OpenCode X account claims "0 retention"; pending user decision).
  - Orchestrator model change (mimo-v2.6 stays for now; separate decision).
  - R2-004 (pre-existing AGENT_NAMES pattern), R4-1 (false positive),
    any model-quality scoring (forbidden by AGENTS.md).
  - Push — after implementation: double privacy scan first (user request).

## Constraints

- English artifacts; conventional commits; no AI attribution.
- Cheap checks only (`bash -n`, `jq empty`, regen smoke); no model evaluation.
- RDD on: assess after each work-unit commit.
- Never assign paid models; free = `-free` suffix or big-pickle whitelist.
- big-pickle fallback MUST keep working for every non-review role.

## Tasks

- [x] T0 Create this feature document + Engram mirror.
- [x] T1 Registry: `thresholds` object + rationale prose + remove
      `role_chains.review` + jev notes marker.
- [x] T2 Dynamic review selection in `select-role-model.sh` AND mirrored in
      `generate-agent-config.sh` pick(); big-pickle excluded from review.
- [x] T3 GUARD reads thresholds from registry (role-aware, no hardcoded
      64000).
- [x] T4 Docs: README section rewrite + troubleshooting row +
      QUICK-REFERENCE + review-lens-model note + script comment pointers.
- [x] T5 daily-check auto-add limits-unverified marker.
- [x] T6 Verification: `bash -n` on all touched scripts; `jq empty` on
      registry; regen smoke (stdout pure JSON; review agents → highest
      output_limit eligible model; orchestrator chain unchanged);
      `select_role_model review 1` → NONE (no eligible model);
      `select_role_model review 3` → top-output eligible; non-review roles
      unchanged vs pre-change output. Record exact outputs here.
- [ ] T7 Work-unit commit(s) + RDD assess (orchestrator; user confirms).
- [x] T8 Native review `review-a3918022efdf8ec7` closed `escalated`
      (informational; unknown causality on R2-001 + R3-1). Maintainer triage:
      both real → fixed pre-commit: R2-001 single-sourced model selection
      (generate-agent-config.sh now calls `select_role_model`; inline `pick()`
      deleted), R3-1 shared fail-closed predicate `registry_thresholds_present`
      used by both the generator (exit 1) and the lib (stderr warning + NONE).
      Verified: byte-equivalent regen vs pre-refactor (modulo timestamp),
      identical guard stderr, fail-closed test green both sides.

## Acceptance criteria

- Review agents resolve to the tier-eligible free model with the highest
  `output_limit` ≥ 128000, automatically; no path can assign big-pickle (or
  any model < 128000) to a review agent; when none qualifies the agent gets
  NONE and apply-model-config prints its visible skip warning.
- Every non-review role behaves exactly as before (big-pickle fallback kept).
- Guard thresholds come from `selection_rules.thresholds` only; changing the
  registry number changes behavior with no script edits.
- README explains both thresholds and the fallback difference so a new user
  never has to ask why 64000 ≠ 128000.

## Progress

- 2026-09-26: created (T0). Source: review `review-4d181d4d9e1381be`
  findings triage + user decisions this session (big-pickle out for
  reviewers; dynamic max-output binding; docs for both audiences; attack
  minor warnings; space-bunny pending consultation).

## Verification evidence (2026-09-26)

- `bash -n` on all 4 touched scripts: OK (exit 0). `jq empty` registry: OK.
- Regen smoke: exit 0, stdout pure JSON; 10 guard warnings = same 10 as
  pre-change baseline (wording only: threshold now printed + registry pointer).
- Review agents (all 5): `opencode/nemotron-3.5-lightning-free`
  (output_limit 262144 = computed max among free, tier ≤3, ≥128000 eligible;
  next: nemotron-3-ultra-free 128000). Big-pickle (32000) unreachable by rule.
- `select_role_model review 3` → lightning; `review 1` → NONE;
  `orchestrator 3` → mimo-v2.6-flash-free (unchanged). Role loop diff vs
  baseline: only the `review` row changed.
- agents before/after diff: only the 5 review rows changed; everything else
  IDENTICAL.
- `grep 64000/128000` in generate/select scripts: zero matches (numbers live
  only in the registry). Missing-thresholds validation: exit 1 + clear stderr,
  0 bytes stdout.
- Parent spot check: independent jq max computation reproduced 262144;
  dynamic branch + guard diffs read line by line: PASS.

T0–T6 done by writer `general` + parent spot check. T8 (findings fixes) done
by writer `general` + parent spot check (byte-equivalence verified).
T7: work-unit commit done; RDD assess follows, then push after the double
privacy scan the user requested.
