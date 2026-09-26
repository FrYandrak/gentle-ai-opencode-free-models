# OpenCode Free Models Selector for Gentle-AI

<a href="https://github.com/Gentleman-Programming/gentle-ai">
  <img width="220" src="https://raw.githubusercontent.com/Gentleman-Programming/gentle-ai/main/docs/assets/brand/built-with-gentle-ai.png" alt="Built with Gentle-AI" />
</a>

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
| `check-upstream.sh` | Detect upstream Gentle-AI releases that could affect agents, config, or contracts (`--force` to re-run same day) |
| `select-role-model.sh` | Shared helpers (including `load_privacy_tier`) |

## Model registry

Models are stored in `privacy-tier-registry.json` with privacy tier, provider, context window, and capabilities. `daily-check.sh` keeps this in sync with what Zen actually offers.

When a new model appears on Zen it is added with a **default tier**. Verify its privacy policy and adjust the registry if needed — do not assume the default matches your threat model.

### Model selection rules

**For subagents that emit large payloads, `output_limit` — not `context_window` — is the binding model parameter.**

| Concept | Meaning |
|---------|---------|
| `context_window` | Bounds how much INPUT fits. It says nothing about what the model can emit. |
| `output_limit` | Max output tokens per response — this is what a `finish: "length"` death exhausts. |
| General warning threshold — **64000** (`thresholds.general_large_payload`) | Below this, a model must not be assigned to any subagent that emits large structured payloads (reports, lens JSON). `generate-agent-config.sh` prints a warning when the guard sees such an assignment. |
| Review floor — **128000** (`thresholds.role_minimums.review`) | Review lenses are the heaviest payloads we emit, so the `review` role demands this much output headroom. A model below the floor can never become a reviewer. |

**Why two different numbers?** Both trace back to one observed failure: a model with an output budget of 32000 tokens died with `finish: "length"` after reasoning away its whole budget and emitting nothing (`mimo-v2.6-flash-free`, `reasoning=32000/output=0`, confirmed in `opencode.db`). The general warning sits at **2×** that failure — the zone where any large-payload subagent is at risk. The review floor sits at **4×** it — the headroom review-lens JSON needs once reasoning overhead is counted. The authoritative values live in **`privacy-tier-registry.json` → `selection_rules.thresholds`**: change the number there, re-run `./generate-agent-config.sh`, and behavior changes — no script edits.

**Review role: dynamic selection, no fallback.** The `review` role has **no static chain**. On each generation, code picks the model with the **highest `output_limit`** among free, privacy-tier-eligible models that meet the review floor — automatically, as tiers and the model catalog change. `big-pickle` is **never** a reviewer (it remains the fallback for every other role — that difference is intentional). If no model qualifies at your tier, the review agents get `NONE` and `./apply-model-config.sh` prints a visible skip warning — never a silent low-limit assignment.

**Sync risk:** `review-*` agent blocks are marked `__managed_by: gentle-ai/sdd`, so `gentle-ai sync` may revert assigned models. Re-apply with `./apply-model-config.sh`.

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
| 4R lens fails with `opencode_task_output_empty` (`opencode.db` shows `finish: "length"`) | Assigned model's `output_limit` too small — reasoning consumed the whole budget | Reviewers are bound dynamically to the highest-`output_limit` model meeting `selection_rules.thresholds.role_minimums.review`; re-run `./generate-agent-config.sh && ./apply-model-config.sh` (if no model qualifies you get a visible skip warning, not a bad assignment) |

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

<a href="https://github.com/Gentleman-Programming/gentle-ai">
  <img width="220" src="https://raw.githubusercontent.com/Gentleman-Programming/gentle-ai/main/docs/assets/brand/built-with-gentle-ai.png" alt="Built with Gentle-AI" />
</a>
