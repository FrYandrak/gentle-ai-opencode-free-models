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
- **Silent session-start hook** — configurable frequency (`session` / `daily` / `weekly` / `monthly`) on shell start or OpenCode startup; failures still go to stderr
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

### Session-start automation (optional)

`session-start-hook.sh` refreshes models automatically. It has one frequency gate and two triggers:

| Trigger | Fired by | Argument |
|---------|----------|----------|
| `shell` (default) | `~/.bashrc` sourcing the hook on each terminal start | none (or `shell`) |
| `opencode` | `plugins/model-check.ts` (`~/.config/opencode/plugins/`) on each OpenCode startup | `opencode` |

The frequency lives in **`.model-check-config`** (gitignored user state; copy `.model-check-config.example` to create it) as `check_frequency=<value>`:

| `check_frequency` | Behavior |
|-------------------|----------|
| `session` | Runs on **every OpenCode startup**; the `shell` trigger stays silent while the stamp is fresh and acts as a **backstop** (runs + one stderr warning) once it is older than 1 day — i.e. when the plugin is absent or failing |
| `daily` | Either trigger runs at most once per **1 day** |
| `weekly` | Either trigger runs at most once per **7 days** |
| `monthly` | Either trigger runs at most once per **30 days** |

Both triggers share one stamp (`results/.last-daily-run`), so they never double-run. A missing file/key/value is treated as `daily`; an unknown value falls back to `daily` and prints one stderr notice — the hook never crashes and never widens the window silently. The stamp is written only on a successful check, so a failure retries on the next trigger.

`session` has no silent dead end: if the out-of-repo plugin stops running (not installed, not loaded, or failing), the shared stamp goes stale and the `shell` trigger falls back to the 1-day path and warns once on stderr instead of letting the refresh die unnoticed.

The hook is **silent on success** (detail appended to `results/session-start.log`). Failures still print to stderr.

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
| `session-start-hook.sh` | Orchestrate model check + config application at the configured frequency (`session` / `daily` / `weekly` / `monthly`) |
| `check-upstream.sh` | Detect upstream Gentle-AI releases that could affect agents, config, or contracts (`--force` to re-run same day) |
| `select-role-model.sh` | Shared helpers (including `load_privacy_tier`) |

## Model registry

Models are stored in `privacy-tier-registry.json` with privacy tier, provider, context window, and capabilities. `daily-check.sh` keeps this in sync with what Zen actually offers.

When a new model appears on Zen it is added with a **default tier**. Verify its privacy policy and adjust the registry if needed — do not assume the default matches your threat model.

### Model selection rules

**Every role is selected by the same criteria: best privacy allowed first, then most headroom. `role_chains` are ordered fallback lists only — never the primary ranking.**

1. **Tier gate** — a candidate must pass your active tier (`.privacy-config` → `privacy_max_tier`, loaded by `load_privacy_tier`); a model with no `privacy_tier` in the registry counts as tier 4.
2. **Candidate filter** — free registry ids (`.models`: `opencode/big-pickle` or ids ending in `-free`) whose `output_limit` meets the role floor: `thresholds.role_minimums[role]` when the registry defines one, else `thresholds.general_large_payload`.
3. **Sort** — privacy tier ascending → `output_limit` descending → `context_window` descending → id ascending. First candidate wins.
4. **Chain fallback** — no candidate → first entry of `role_chains[role]` (else `role_chains.default`) that is free, present in `.models`, and tier-eligible; the `big-pickle` terminal append stays.
5. **`NONE`** — still nothing → the agent gets `NONE` and `./apply-model-config.sh` prints a visible skip warning — never a silent low-limit assignment.

Selection lives in **`select-role-model.sh` → `select_role_model`** (single source of truth); role names are resolved through `role_aliases` first. `./generate-agent-config.sh` re-runs the whole calculation from the registry, so assignments self-correct when models, limits, or tiers change.

> **Intended consequence:** with `privacy_max_tier=3`, privacy-first ordering resolves most or all roles to `opencode/space-bunny-free` (tier 1, largest output headroom). That is the design working — privacy is the primary valued parameter. Chains only decide anything when the criteria path finds no candidate.

**For subagents that emit large payloads, `output_limit` — not `context_window` — is the binding model parameter.**

| Concept | Meaning |
|---------|---------|
| `context_window` | Bounds how much INPUT fits. It says nothing about what the model can emit. |
| `output_limit` | Max output tokens per response — this is what a `finish: "length"` death exhausts. |
| General warning threshold — **64000** (`thresholds.general_large_payload`) | Below this, a model must not be assigned to any subagent that emits large structured payloads (reports, lens JSON). It is also the **default selection floor** for every role without an entry in `thresholds.role_minimums`. `generate-agent-config.sh` prints a warning when the guard sees an assignment below it (defense-in-depth: selection applies the same floor on the primary path, and the guard still catches under-allocated chain-fallback assignments). |
| Review floor — **128000** (`thresholds.role_minimums.review`) | Review lenses are the heaviest payloads we emit, so the `review` role demands this much output headroom on the primary selection path; anything below the floor trips the generator's warning guard instead of passing silently. |

**Why two different numbers?** Both trace back to one observed failure: a model with an output budget of 32000 tokens died with `finish: "length"` after reasoning away its whole budget and emitting nothing (`mimo-v2.6-flash-free`, `reasoning=32000/output=0`, confirmed in `opencode.db`). The general warning sits at **2×** that failure — the zone where any large-payload subagent is at risk. The review floor sits at **4×** it — the headroom review-lens JSON needs once reasoning overhead is counted. The authoritative values live in **`privacy-tier-registry.json` → `selection_rules.thresholds`**: change the number there, re-run `./generate-agent-config.sh`, and behavior changes — no script edits.

**Sync risk:** `review-*` agent blocks are marked `__managed_by: gentle-ai/sdd`, so `gentle-ai sync` may revert assigned models. Re-apply with `./apply-model-config.sh`.

**Automated verification:** every `daily-check.sh` run verifies `context_window`/`output_limit` against `https://models.dev/api.json` and each `privacy_tier` against the official OpenCode Zen docs §Privacy section. Verified data is applied automatically to **newly added** models at add time; on **existing** entries, drift is reported as a yellow advisory only — the daily run never auto-corrects committed limits or rewrites tiers (a tier change stays a manual privacy decision).

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
| 4R lens fails with `opencode_task_output_empty` (`opencode.db` shows `finish: "length"`) | Assigned model's `output_limit` too small — reasoning consumed the whole budget | Assignments are criteria-driven (privacy tier first, then output headroom — see "Model selection rules"); re-run `./generate-agent-config.sh && ./apply-model-config.sh` (if no model qualifies you get a visible skip warning, not a bad assignment) |

## Repository notes

- `.privacy-config`, `.model-check-config`, `results/`, `.engram/`, `.atl/`, and `.gga` are gitignored — your tier, check frequency, and logs stay local (`.model-check-config.example` is the tracked copyable default).
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
