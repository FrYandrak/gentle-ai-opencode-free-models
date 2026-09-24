# OpenCode Free Models Selector for Gentle-AI

[![Built with Gentle-AI](https://raw.githubusercontent.com/Gentleman-Programming/gentle-ai/main/docs/assets/brand/built-with-gentle-ai.png)](https://github.com/Gentleman-Programming/gentle-ai)

Privacy-aware, dynamic model assignment for **OpenCode Zen free models** in [Gentle-AI](https://github.com/Gentleman-Programming/gentle-ai) workflows.

Free models rotate, disappear, and change their data policies. Hardcoding a model name in `opencode.jsonc` means your config breaks silently — or worse, keeps sending your code to a model you would not have chosen today. This tool picks the model per role from what Zen actually offers **and** from the privacy level you set once.

## Why this exists

1. **OpenCode Zen free models rotate.** Assignments recalculated from the live catalog do not go stale.
2. **Privacy is not one-size-fits-all.** You declare how much data you accept sharing; every role assignment respects that ceiling.
3. **No hardcoded model names.** The system reads the registry and decides; new models land at a default tier you can adjust.

## Features

- **Privacy tiers (1–4)** — one setting (`.privacy-config`) controls every assignment
- **Live registry** — `daily-check.sh` syncs `privacy-tier-registry.json` from the Zen API
- **Role-based mapping** — orchestrator, explore, apply, verify, and the rest of your agents each get the best allowed model
- **Silent daily hook** — runs once per day on shell start; failures still go to stderr
- **Model-agnostic** — works when Zen adds or drops models; no script edits required

## Privacy tiers

| Tier | Meaning | Tradeoff |
|------|---------|----------|
| **1 — Strict** | No data used for anything. Zero retention. | Fewest models available |
| **2 — Anonymous** | Logged for improvement, not linked to you. No training. | Limited selection |
| **3 — Model Improvement** | Data may improve the model during free period. | Most models available |
| **4 — Accept All** | Including models that train on your data explicitly. | All models, full exposure |

Your active tier lives in `.privacy-config` as `privacy_max_tier` (set via `./privacy-setup.sh`). Every script loads it through `load_privacy_tier` from `select-role-model.sh` — never hardcode a tier number in scripts or docs.

## How it works

```text
Session starts
  → daily-check.sh fetches live models from the Zen API
  → generate-agent-config.sh reads your tier + available models
  → apply-model-config.sh patches opencode.jsonc
  → each free-models agent gets its optimal allowed model
```

## Requirements

- `jq` — JSON processing
- `curl` — API calls to Zen
- OpenCode with free-model agents configured (roles that resolve to `*-free` / `*-free-models` entries)
- [Gentle-AI](https://github.com/Gentleman-Programming/gentle-ai) workflows (optional but the intended context)

## Install

```bash
git clone https://github.com/FrYandrak/free-model-comparison.git
cd free-model-comparison

# 1. One-time: set your privacy preference
./privacy-setup.sh

# 2. Generate and apply assignments once
./daily-check.sh
./apply-model-config.sh
```

### Daily automation (optional)

`session-start-hook.sh` runs once per day when you open a terminal. It is **silent on success** (detail appended to `results/session-start.log`). Failures still print to stderr.

Add to your `~/.bashrc`:

```bash
source /path/to/free-model-comparison/session-start-hook.sh
```

After the hook is sourced, the full on-demand report is:

```bash
models-apply
```

## Scripts

| Script | Purpose |
|--------|---------|
| `privacy-setup.sh` | Set or change your privacy tier |
| `model-selector.sh` | Show current assignments for your tier |
| `daily-check.sh` | Fetch live models, detect changes, update registry (`--interactive` to confirm changes) |
| `generate-agent-config.sh` | Generate role→model mapping from tier + registry |
| `apply-model-config.sh` | Patch `opencode.jsonc` with generated assignments |
| `session-start-hook.sh` | Orchestrate daily check + config application |
| `select-role-model.sh` | Shared helpers (including `load_privacy_tier`) |

## Model registry

Models are stored in `privacy-tier-registry.json` with privacy tier, provider, context window, and capabilities. `daily-check.sh` keeps this in sync with what Zen actually offers.

When a new model appears on Zen it is added with a **default tier**. Verify its privacy policy and adjust the registry if needed — do not assume the default matches your threat model.

### Known non-goals

- **Not a benchmark suite.** This project does not score model quality; it assigns models. (Comparative testing was deliberately dropped to keep the free-token budget for real work.)
- **Not a paid-model router.** Only free-tier / whitelisted free models are in scope.

## Known limitation: free-tier subagent failures

OpenCode's free tier sometimes rejects **sub-agent** LLM streams with:

```text
AI_APICallError: Error from provider (Console):
OpenCode's free tier can only be used from within OpenCode
```

This is a **server-side free-tier limit**, not a config bug here. The same model, session, and prompt can succeed on one launch and fail on the next.

**What to do:** retry the same sub-agent after a short pause. Under Gentle-AI review, re-query the exact lineage STATUS first — the capture slot stays reoffered while the transaction is open. Primary (non-subagent) chats are usually unaffected. See `~/.local/share/opencode/log/opencode.log` for `free tier can only` if you need timestamps.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Assignments not applied | Hook never ran / `opencode.jsonc` path mismatch | Run `./daily-check.sh && ./apply-model-config.sh` manually |
| Wrong privacy ceiling | Stale or hand-edited `.privacy-config` | Re-run `./privacy-setup.sh` |
| New model missing or mis-tiered | Registry default not reviewed | Edit `privacy-tier-registry.json`, re-run `generate-agent-config.sh` |
| Sub-agent stream rejected | Free-tier server limit (see above) | Retry after a pause |

## Repository notes

- `.privacy-config`, `results/`, `.engram/`, `.atl/`, and `.gga` are gitignored — your tier and logs stay local.
- `AGENTS.md` and `odd/tasks/` document how *this* repository is developed (agent-driven workflow). They are not required to use the tool.

## Contributing

Issues and PRs are welcome — especially registry tier corrections when Zen changes a model's data policy. Keep changes small and include a short “why” in the PR description.

## Resources

- Gentle-AI: https://github.com/Gentleman-Programming/gentle-ai
- OpenCode Zen docs: https://opencode.ai/docs/zen/
- Ecosystem health check: `gentle-ai doctor`

## License

MIT — see [LICENSE](LICENSE).

---

[![Built with Gentle-AI](https://raw.githubusercontent.com/Gentleman-Programming/gentle-ai/main/docs/assets/brand/built-with-gentle-ai.png)](https://github.com/Gentleman-Programming/gentle-ai)
