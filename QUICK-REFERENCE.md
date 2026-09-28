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

# 5. Upstream drift check (once per day; --force to re-run)
./check-upstream.sh

# 6. Model check frequency — check or edit (source: .model-check-config)
grep check_frequency .model-check-config
```

## Privacy Tiers

| Tier | Label | Models Available |
|------|-------|-----------------|
| 1 | Strict Privacy | Space Bunny, LongCat Preview |
| 2 | Anonymous Improvement | Nemotron Ultra, Nemotron Lightning |
| 3 | Model Improvement | MiMo, Ling Flash, Big Pickle |
| 4 | Accept All | All free models (see registry notes) |

Defined once in `.privacy-config` (`privacy_max_tier`) via `./privacy-setup.sh` — never hardcode a tier number.

## Model Check Frequency

Defined once in **`.model-check-config`** (`check_frequency=<value>`, gitignored; copy `.model-check-config.example`):

| Value | Behavior |
|-------|----------|
| `session` | Runs on **every OpenCode startup** (plugin trigger); the shell trigger only **backstops** — silent while the stamp is fresh, runs + warns on stderr once the stamp is older than 1 day |
| `daily` | Either trigger runs at most once per **1 day** — the default when the file/key/value is missing |
| `weekly` | Either trigger runs at most once per **7 days** |
| `monthly` | Either trigger runs at most once per **30 days** |

- Two triggers share one stamp (`results/.last-daily-run`): `shell` (sourced from `~/.bashrc`) and `opencode` (`~/.config/opencode/plugins/model-check.ts`) — they never double-run.
- Unknown value → falls back to `daily` with a one-line stderr notice (never crashes, never widens the window silently).

## Model Quick Stats (qualitative notes only — no scoring harness)

| Model | Privacy Tier | Best For |
|-------|-------------|----------|
| Space Bunny | 1 | Live default — privacy-first pick for every role at tier ≥ 1 |
| MiMo-V2.6 Flash | 3 | Planning, fast reasoning |
| MiMo-V2.5 | 3 | Listed but currently broken on Zen — fallback only |
| Nemotron Ultra | 2 | Large codebase analysis |
| Nemotron Lightning | 2 | Quick verification |
| Ling Flash | 3 | Documentation, tasks |
| Muse Spark | 4 ⚠ | Creative tasks |

## Assignment (model-agnostic)

- Source of truth: `privacy-tier-registry.json` → `selection_rules` / `role_chains` / `role_aliases`
- The daily check verifies limits against `https://models.dev/api.json` and privacy against the official OpenCode Zen docs §Privacy section: newly added models get verified data at add time; drift on existing entries is reported, never auto-fixed
- Shared selector: `select-role-model.sh` — criteria-driven for every role: free ids with `tier <= max_tier` and `output_limit >=` the role floor (`selection_rules.thresholds.role_minimums[role]`, else `general_large_payload`), sorted tier ↑ → output ↓ → context ↓ → id ↑; `role_chains` are ordered fallbacks only (big-pickle terminal kept)
- Scripts source the lib — catalog changes touch the registry only
- Model-testing harness is **cancelled** (free-token budget)
