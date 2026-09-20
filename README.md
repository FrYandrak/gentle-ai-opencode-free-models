# Free Model Selection for Gentle-AI

Privacy-aware, dynamic model assignment for OpenCode Zen free models in Gentle-AI workflows.

## What This Does

OpenCode Zen offers free models that rotate over time. This system:

1. **Classifies models by privacy tier** — so you choose what data you're willing to share
2. **Assigns the best model to each task** — orchestrator, explore, apply, verify, etc.
3. **Adapts automatically** — when models appear or disappear, assignments recalculate

No hardcoded model names. The system reads what's available and decides.

## Quick Start

```bash
# 1. Set your privacy preference (one time)
./privacy-setup.sh

# 2. First session of the day — runs automatically via session-start-hook
#    Or run manually:
./daily-check.sh
./apply-model-config.sh
```

## How It Works

### Privacy Tiers

| Tier | Meaning | Tradeoff |
|------|---------|----------|
| **1 — Strict** | No data used for anything. Zero retention. | Fewest models available |
| **2 — Anonymous** | Logged for improvement, not linked to you. No training. | Limited selection |
| **3 — Model Improvement** | Data may improve the model during free period. | Most models available |
| **4 — Accept All** | Including models that train on your data explicitly. | All models, full exposure |

### Dynamic Assignment

```
Session starts
  → daily-check.sh fetches live models from Zen API
  → generate-agent-config.sh reads your tier + available models
  → apply-model-config.sh patches opencode.jsonc
  → each sdd-*-free-models agent gets its optimal model
```

### Session Hook

The `session-start-hook.sh` runs once per day when you open a terminal. It:
- Checks Zen for model changes
- Updates the local registry
- Regenerates agent assignments in `opencode.jsonc`

Add to your `~/.bashrc`:
```bash
source /path/to/free-model-comparison/session-start-hook.sh
```

## Scripts

| Script | Purpose |
|--------|---------|
| `privacy-setup.sh` | Set or change your privacy tier |
| `model-selector.sh` | Show current assignments for your tier |
| `daily-check.sh` | Fetch live models, detect changes, update registry |
| `check-model-changes.sh` | Interactive change detector with re-evaluation |
| `generate-agent-config.sh` | Generate role→model mapping from tier + registry |
| `apply-model-config.sh` | Patch `opencode.jsonc` with generated assignments |
| `session-start-hook.sh` | Orchestrate daily check + config application |

## Model Registry

Models are stored in `privacy-tier-registry.json` with their privacy tier, provider, context window, and capabilities. The `daily-check.sh` script keeps this in sync with what Zen actually offers.

When a new model appears on Zen, it's added with a default tier. You should verify its privacy policy and adjust if needed.

## Requirements

- `jq` — JSON processing
- `curl` — API calls to Zen
- OpenCode with free model agents configured (`sdd-*-free-models`)

## Files

```
privacy-setup.sh              # Interactive tier selection
model-selector.sh             # Role-based model assignment
daily-check.sh                # Live model sync
check-model-changes.sh        # Change detection
generate-agent-config.sh      # Config generator
apply-model-config.sh         # OpenCode config patcher
session-start-hook.sh         # Daily automation
privacy-tier-registry.json    # Model database
.privacy-config               # Your tier (gitignored)
```
