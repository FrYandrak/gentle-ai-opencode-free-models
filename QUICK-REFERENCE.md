# Quick Reference: Free Models for Gentle-AI

## Privacy Tiers

| Tier | Label | Models Available |
|------|-------|-----------------|
| 1 | Strict Privacy | ❌ None |
| 2 | Anonymous Improvement | Nemotron Ultra, Nemotron Lightning |
| 3 | Model Improvement | MiMo, Ling Flash, Big Pickle |
| 4 | Accept All | All free models (see registry notes) |

Your configured tier: **3** (`.privacy-config`).

## Quick Setup

```bash
# 1. Set your privacy preference (first time only)
./privacy-setup.sh

# 2. See your model assignments
./model-selector.sh

# 3. Check for model changes
./check-model-changes.sh

# 4. On-demand daily report + apply (hook must be sourced)
models-status
```

## How assignment works (model-agnostic)

- Single source of truth: `privacy-tier-registry.json` → `role_chains` / `role_aliases`
- Shared selector: `select-role-model.sh` (free-only + `tier <= max_tier`, Big Pickle terminal)
- Scripts that used to hardcode chains now source the lib — catalog changes touch the registry only

## Model Quick Stats (qualitative notes only — no scoring harness)

| Model | Privacy Tier | Best For |
|-------|-------------|----------|
| MiMo-V2.6 Flash | 3 | Planning, review (live default) |
| MiMo-V2.5 | 3 | Listed but currently broken on Zen — fallback only |
| Nemotron Ultra | 2 | Large codebase analysis |
| Nemotron Lightning | 2 | Quick verification |
| Ling Flash | 3 | Documentation, tasks |
| Muse Spark | 4 ⚠ | Creative tasks |

## Remember

- All free models support tool calling (required for SDD)
- Free models are available "for a limited time"
- **Privacy tiers filter which models you can use** — `./privacy-setup.sh`
- Check for free model additions with `./check-model-changes.sh`
- Model-testing harness is **cancelled** (free-token budget)

## Next Steps

1. Confirm privacy tier: `./privacy-setup.sh`
2. Get model assignments: `./model-selector.sh`
3. Check for changes: `./check-model-changes.sh`
4. Daily report on demand: `models-status`
