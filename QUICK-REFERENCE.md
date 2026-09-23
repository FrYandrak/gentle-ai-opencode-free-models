# Quick Reference: Free Models for Gentle-AI

One-screen command card. Rationale and full details live in `README.md`.

## Core Commands

```bash
# 1. Privacy tier — check or change (source of truth: .privacy-config)
./privacy-setup.sh
grep privacy_max_tier .privacy-config

# 2. Current role → model assignments for your tier
./model-selector.sh

# 3. On-demand daily report + apply (source session-start-hook.sh first)
models-apply

# 4. Shared selector lib (sourced by scripts; also usable directly)
source ./select-role-model.sh && load_privacy_tier \
  && select_role_model apply "$PRIVACY_TIER"
```

## Privacy Tiers

| Tier | Label | Models Available |
|------|-------|-----------------|
| 1 | Strict Privacy | ❌ None |
| 2 | Anonymous Improvement | Nemotron Ultra, Nemotron Lightning |
| 3 | Model Improvement | MiMo, Ling Flash, Big Pickle |
| 4 | Accept All | All free models (see registry notes) |

Defined once in `.privacy-config` (`privacy_max_tier`) via `./privacy-setup.sh` — never hardcode a tier number.

## Model Quick Stats (qualitative notes only — no scoring harness)

| Model | Privacy Tier | Best For |
|-------|-------------|----------|
| MiMo-V2.6 Flash | 3 | Planning, review (live default) |
| MiMo-V2.5 | 3 | Listed but currently broken on Zen — fallback only |
| Nemotron Ultra | 2 | Large codebase analysis |
| Nemotron Lightning | 2 | Quick verification |
| Ling Flash | 3 | Documentation, tasks |
| Muse Spark | 4 ⚠ | Creative tasks |

## Assignment (model-agnostic)

- Source of truth: `privacy-tier-registry.json` → `role_chains` / `role_aliases`
- Shared selector: `select-role-model.sh` (free-only, `tier <= max_tier`, Big Pickle terminal)
- Scripts source the lib — catalog changes touch the registry only
- Model-testing harness is **cancelled** (free-token budget)
