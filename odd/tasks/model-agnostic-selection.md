# Feature: Model-agnostic role selection (registry-driven)

## Objective

Replace the four duplicated hardcoded role candidate chains with a single
registry-driven selection mechanism, so model catalog changes are absorbed in
exactly one place: `privacy-tier-registry.json`.

## Problem / Why

Role candidate chains are copy-pasted in:

- `model-selector.sh`
- `generate-agent-config.sh`
- `daily-check.sh`
- `check-model-changes.sh`

Each Zen catalog change requires editing four files in lockstep. This violates
the project's essence (model-agnostic free-model management) and is a
desync hazard. The registry already carries `best_for` per model — the
selection should derive from it (or from registry-hosted chain data), never
from script literals.

## Scope

- IN: shared selection logic; registry as single source of truth; preserve
  current observable assignments; free-only + tier filter + Big Pickle
  designated fallout; refactor all four scripts; verification baseline.
- OUT: changing today's role→model preferences (unless forced); perseBEU;
  re-applying `opencode.jsonc` (only if assignments actually change).

## Constraints

- Deterministic ordering (same inputs → same selection).
- Free-only policy: `policy/free-model-tiering` in Engram (tier <= user tier;
  unknown → tier 4; Big Pickle ends every chain).
- Bash only, no new runtime deps beyond jq.

## Tasks

- [ ] T1 Map all selection call sites; inventory `best_for` vocabulary vs role
      names (explore subagent — delegated 2026-09-22).
- [ ] T2 Fix on ONE recommended design from T1 (single source; preserves
      current assignments; deterministic).
- [ ] T3 Capture baseline: `generate-agent-config.sh` output before refactor.
- [ ] T4 Implement shared selection + refactor the four scripts.
- [ ] T5 Verify: `bash -n` all scripts; post-refactor generate output equals
      T3 baseline; free-only leak check on registry + snapshot; run
      `daily-check.sh` clean.
- [ ] T6 Work-unit commit (conventional commit).

## Acceptance criteria

- No role model-id literals remain in the four scripts.
- Updating a chain/preference touches only the registry.
- T5 checks all pass; assignments unchanged from baseline.

## Progress

- 2026-09-22: created; T1 delegated. Policy prerequisite landed in d1eb536,
  beb6438, and the tier-4 auto-add commit.
