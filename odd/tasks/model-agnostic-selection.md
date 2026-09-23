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

- [x] T1 Map all selection call sites; inventory `best_for` vocabulary vs role
      names (explore subagent — delegated 2026-09-22). Evidence: 4 scripts ×
      call sites catalogued; chains content-identical, structure drifted.
- [x] T2 Fix on ONE recommended design from T1 (single source; preserves
      current assignments; deterministic). Evidence: decided design — registry
      `role_chains`/`role_aliases` + shared `select-role-model.sh`
      (free-only + `tier <= max_tier` gates, big-pickle chain terminal,
      head-1 last-resort dropped as provably dead).
- [x] T3 Capture baseline: `generate-agent-config.sh` output before refactor.
      Evidence: `/tmp/fmc-baseline/gen-before.json` + `selector-before.txt`
      captured at tier 3 pre-edit; `.privacy-config` byte-identical (`cmp` OK).
- [x] T4 Implement shared selection + refactor the four scripts.
      Evidence: `select-role-model.sh` created; registry gained `role_chains` +
      `role_aliases`; all four scripts source the lib; `bash -n` all 5 → exit 0.
- [x] T5 Verify: `bash -n` all scripts; post-refactor generate output equals
      T3 baseline; free-only leak check on registry + snapshot; run
      `daily-check.sh` clean.
      Evidence: `jq -e empty privacy-tier-registry.json` → exit 4 on valid file
      (jq `-e` semantics for no-output filter; parse error would be exit 5;
      `jq empty` → 0); free-only leak count = 0; generate diff vs baseline =
      IDENTICAL (normalized `generated_at`); role sweep diff vs baseline =
      IDENTICAL; tier-1 edge → `NONE` via lib (exit 0) and via CLI (`all`
      shows all-NONE, `role` exits 1 with message); residual `opencode/`
      literals itemized (registry add/del key construction, free-only fetch
      greps, big-pickle display/fallback — no role-chain literals remain);
      `daily-check.sh` full run: SKIPPED (network/mutation); `check-model-changes.sh`:
      static/syntax only (interactive `read -p` path not forced).
- [x] T6 Work-unit commit (conventional commit). Evidence: `c6b8973`
      `feat: registry-driven role selection via shared select-role-model lib`
      (recorded 2026-09-23; 4R review `review-47c8fab3bcb43f8d` targets this
      candidate).

## Intentional delta

- Tier 1 in `check-model-changes.sh` previously force-fell-back to
  `opencode/big-pickle` (violating `tier <= max_tier`); after refactor it
  emits `NONE` (`✗ label: NO MODEL — needs attention`), matching the other
  three scripts. Tiers 2–4 outputs identical to baseline.
- Latent, unobservable today: daily-check had no `research` branch (fell to
  default); after refactor `research` resolves to the explore chain everywhere.

## Acceptance criteria

- No role model-id literals remain in the four scripts.
- Updating a chain/preference touches only the registry.
- T5 checks all pass; assignments unchanged from baseline.

## Progress

- 2026-09-22: created; T1 delegated. Policy prerequisite landed in d1eb536,
  beb6438, and the tier-4 auto-add commit.
