# Quick Reference: Free Models for Gentle-AI

## Top Recommendations (TL;DR) — Tier 2 (Anonymous Improvement Only)

These models have the strongest privacy guarantees among free options:

| Role | Model | Why |
|------|-------|-----|
| **Orchestrator** | `opencode/nemotron-3-ultra-free` | Best available at tier 2 |
| **Explore/Research** | `opencode/nemotron-3-ultra-free` | 1M context window, strong privacy |
| **Design** | `opencode/nemotron-3-ultra-free` | Strong reasoning at tier 2 |
| **Implementation** | `opencode/nemotron-3.5-lightning-free` | Fast, reliable, good privacy |
| **Verification** | `opencode/nemotron-3.5-lightning-free` | Fast, reliable checks |

> ⚠ At tier 2, you lose MiMo (best reasoning) and Ling Flash (fast docs). Run `./privacy-setup.sh` to adjust if this is too restrictive.

## Privacy Tiers

| Tier | Label | Models Available |
|------|-------|-----------------|
| 1 | Strict Privacy | ❌ None |
| 2 | Anonymous Improvement | Nemotron Ultra, Nemotron Lightning |
| 3 | Model Improvement | MiMo, Ling Flash, Big Pickle, JEV |
| 4 | Accept All | All 10 free models (Muse Spark → Meta training; DeepSeek Free → no privacy info) |

## Quick Setup

```bash
# 1. Set your privacy preference (first time only)
./privacy-setup.sh

# 2. See your model assignments
./model-selector.sh

# 3. Check for model changes
./check-model-changes.sh

# 4. Run tests (only models in your tier)
./test-models.sh
```

## Model Quick Stats

| Model | Speed | Reasoning | Context | Output | Privacy Tier | Best For |
|-------|-------|-----------|---------|--------|-------------|----------|
| MiMo-V2.5 | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | 262K | 6K | 3 | Planning, Review |
| Nemotron Ultra | ⭐⭐ | ⭐⭐⭐⭐ | 1M | 131K | 2 | Large codebase analysis |
| Nemotron Lightning | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | 262K | 131K | 2 | Quick verification |
| Ling Flash | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | 262K | 131K | 3 | Documentation, Tasks |
| Muse Spark | ⭐⭐⭐⭐ | ⭐⭐⭐ | 262K | 131K | 4 ⚠ | Creative tasks |

## Remember

- All free models support tool calling (required for SDD)
- Free models are available "for a limited time"
- **Privacy tiers filter which models you can use** — run `./privacy-setup.sh` to set yours
- Check for new free model additions regularly with `./check-model-changes.sh`
- Test before relying on them for critical work

## Next Steps

1. Set privacy tier: `./privacy-setup.sh`
2. Run baseline tests: `./test-models.sh`
3. Fill in comparison matrix: `COMPARISON-MATRIX.md`
4. Get model assignments: `./model-selector.sh`
5. Check for changes: `./check-model-changes.sh`
