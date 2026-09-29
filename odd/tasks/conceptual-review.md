# Conceptual review: free-model-comparison

Date: 2026-09-29
Method: four independent read-only domain audits (acquisition pipeline / selection brain / trigger layer / strategy+docs), then parent verification of the load-bearing claims by direct code reading and empirical execution. Every finding below is marked with how it was established.

This is a **review**, not a feature. It contains no implementation tasks yet — the "Proposed directions" section is the input to whatever work gets authorized next.

---

## Verdict

The engineering is genuinely careful — lock/stamp reasoning, fail-closed privacy, atomic writes, degradation doctrine, and commit hygiene are all better than most comparable bash tooling. The problems are not in the code quality. They are at the **boundaries**: project identity, the install path, and the single place that touches the user's config.

The deepest finding is that the selection algorithm is a **constant function**, for a structural reason that will silently keep it constant even as better models arrive.

---

## What the project actually is

A privacy-gated **model assignment tool**: it reads a JSON registry of free OpenCode Zen models, picks one per OpenCode agent, and patches `~/.config/opencode/opencode.jsonc` so agent models refresh automatically.

It is **not** a model comparison tool. The directory name, the repo name and `AGENTS.md:5` still say "compares free models … determine optimal model assignments"; `README.md:153` and `QUICK-REFERENCE.md:72` explicitly cancel the comparison harness ("Model-testing harness is cancelled — free-token budget"). Three identities coexist:

- directory `free-model-comparison`
- remote `gentle-ai-opencode-free-models`
- README title "OpenCode Free Models Selector for Gentle-AI"

---

## Findings

### S1 — The selector is a constant function, and the tier knob is inert (highest conceptual severity)

**Verified empirically.** `select_role_model` called for 10 roles × tiers 1–4 returns `opencode/space-bunny-free` for **all 40 combinations**, including `review` and a nonsense role name.

Cause: `select-role-model.sh:87` sorts `sort_by([.t, (-.ol), (-.ctx), .id])` — **privacy tier is the primary key**. The tier-1 model therefore wins every role at every tier, regardless of capability. Consequences:

- The user's privacy tier setting (`1`…`4`) changes nothing. Tiers 1 and 4 produce byte-identical output.
- `role_chains` (65 registry lines) can never fire while any tier-1 candidate clears the output floor.
- `role_minimums.review` (128000) is unreachable in practice — no role floor currently excludes the winner.
- **The design can never differentiate roles by capability.** A genuinely better tier-2 model with a huge output window would still lose to any tier-1 model. Role fit is not expressible.

The constant outcome is *acceptable* under the stated philosophy (one model everywhere if it is objectively the best). But it is **accidental**: the code encodes "privacy tier beats capability", not "capability beats privacy tier, ties broken by privacy". Today both readings pick the same model. The moment a second tier-1 model appears, the tie-break becomes output size alone, and role differentiation stays impossible.

*Established by: empirical execution of the real function against the real registry.*

### S2 — `apply-model-config.sh` fabricates agents and overwrites the top-level model (trust defect)

**Verified empirically** with the real jq program. Against a config that has no `.agent` object at all:

```
input:  {"model":"anthropic/claude"}
output: {"model":"a/b","agent":{"sdd-spec-free-models":{"model":"a/b"},
                                "review-free-models":{"model":"c/d"}}}
```

`.agent[$e.key].model = $e.value` (`apply-model-config.sh:79`) auto-vivifies in jq. A user without Gentle-AI agents gets model-only agent stubs invented for them, and the script prints `✓ opencode.jsonc updated successfully` (`:96`). `README.md:50` states the Gentle-AI prerequisite and never checks it.

Separately, `:80` sets the **top-level** `model` whenever `_meta.top_level_model` is present — so a user who opts out of Gentle-AI still has their global default model replaced by a free model. The README calls the Gentle-AI context "optional but the intended context" (`:51`); the code treats it as unconditional.

*Established by: code reading + empirical jq execution.*

### S3 — Degraded runs are invisible (the degradation doctrine has no consumer)

`warn_degraded()` (`daily-check.sh:104-108`) and the fetch-failure advisories (`:734-736`) print to **stdout**. The hook redirects both streams into a logfile: `bash "$DAILY_CHECK" >>"$HOOK_LOG" 2>&1` (`session-start-hook.sh:142`), and only speaks on non-zero exit (`:145`).

`daily-check.sh` is deliberately fail-soft: degraded → exit 0 (documented in its own header, `:100-102`). So a run that verified *nothing* exits 0, prints its warnings into a file nobody reads, and is **indistinguishable from a healthy run**. `README.md:22,89` promise stderr-visible failures.

The same swallow applies to `apply-model-config.sh` (`:151`). This is the exact class of defect the previous feature's CRITICAL finding was about, one layer up: a refresh that silently does nothing.

*Established by: code reading of both scripts.*

### S4 — The flagship `session` mode is unreachable on a fresh clone

`session-start-hook.sh:96-98` grants `RUN_UNCONDITIONAL=1` only to `TRIGGER=opencode`, and that argument comes solely from `~/.config/opencode/plugins/model-check.ts` — not tracked, absent from `git ls-files`, with a hardcoded absolute path. `README.md:74` documents the trigger; the Install section (`:55-65`) never mentions installing it. `.model-check-config.example:9` ships `check_frequency=session`, so **the copy-paste default depends on a file the repo does not own**. A fresh clone in the documented default mode has only the shell trigger — the very "inert" configuration the last review CRITICAL was about, reintroduced through the install path.

*Established by: code reading + `git ls-files`.*

### S5 — Hook stamps before applying, so a failed apply is never retried

`session-start-hook.sh:143` writes the stamp on successful `daily-check.sh`; `apply-model-config.sh` runs afterwards at `:150-151`. If apply fails, the window is already stamped → no retry until the next window, and the user sees one stderr line. The stamp contract elsewhere ("only on success", `:140`) is about the *check*, not the *effect*.

Also: `RUN_UNCONDITIONAL` still takes `flock -n` and returns silently on contention (`:115-120`), so in `session` mode a concurrent run drops the refresh with no message — most likely exactly when the degraded backstop is also firing.

*Established by: code reading of the hook.*

### S6 — `check-upstream.sh` couples to another script by regex

552 lines — 21% of the codebase — and it extracts the agent list out of `generate-agent-config.sh` with a sed range parse (`check-upstream.sh:427`: `sed -n '/^AGENT_NAMES=(/,/^)/p'`). Renaming or reformatting that array silently empties the list and disables the checks, with no error. Its stamp is written unconditionally (`:549`), so a run where every fetch failed still marks the day done — the opposite rule from the hook. Role lists are hardcoded in four places (`model-selector.sh:93,127,235`; `daily-check.sh:928`; `generate-agent-config.sh:45-75`) rather than derived from the registry; the free-id predicate is implemented 5×, and the tier vocabulary 3× inside `daily-check.sh` while canonical values live in the registry.

*Established by: delegated audit, corroborated by grep.*

### S7 — The public README's first command 404s

`README.md:56` says `git clone https://github.com/FrYandrak/free-model-comparison.git`. The actual remote is `…/FrYandrak/gentle-ai-opencode-free-models.git`. The repo is **public**. The first command in the README points at a URL that does not exist.

`QUICK-REFERENCE.md:54-64` additionally hand-maintains a model table (7 entries) that contradicts `README.md:15` ("no hardcoded model names") and is already stale against the registry. Its MiMo-V2.5 row ("currently broken — fallback only") is inert: tier 3 with `output_limit` 32000 cannot clear the 64000 floor, so selection can never reach it.

*Established by: grep + reading the table against the registry.*

### S8 — No verification story for the product

Zero tests, no CI, no `.github`. `AGENTS.md:14-17` sets `bash -n` + `jq empty` as the standard (both pass on all 8 scripts). But the product is *which model gets picked*, and that is precisely what is never asserted. The gate matrix that closed the last feature lives only in `/tmp`. A one-line change to `sort_by` in `select-role-model.sh` would silently reassign every agent in the user's config with no test failing.

*Established by: `git ls-files` (no test paths) + delegated audit.*

---

## What is genuinely good — keep it

- **Lock/stamp correctness** (`session-start-hook.sh:112-126`): double-check before and under the lock, no stale-lock recovery needed, stamp-only-on-success. Correct by construction.
- **Fail-closed privacy** (`daily-check.sh:313-318`): tier-4 default, upgrades only on affirmative doc evidence with verbatim quote stored.
- **Structural validation over JSON syntax** — failures carry the reason, not just an error.
- **Atomic writes** everywhere: `mktemp` in the target filesystem + `jq empty` + `mv`, with an `EXIT` trap.
- **`NONE`-not-exit contract** (`select-role-model.sh:6-7`) keeps `set -e` safe across three callers.
- **Total sort order** with `id asc` last — ties are deterministic.
- **Honest, bounded duplication** (`check-upstream.sh:11-15`) — better than premature `lib-common.sh`.
- **Commit hygiene**: coherent work units, `feat`/`fix`/`refactor` interleaved with their evidence. No drive-by edits.
- Docs describing the *selection rules* are accurate clause-for-clause (`README.md:124-132` vs `select-role-model.sh:41-56`). The failures are at the boundaries, not in the rules.

---

## Proposed directions (not authorized; input to the next planning step)

| # | Direction | Cost | Risk | Addresses |
|---|---|---|---|---|
| P1 | Guard the patch: refuse to write agent keys absent from `opencode.jsonc`, report instead of auto-vivifying; make the top-level overwrite opt-in | ~10 lines | low | S2 |
| P2 | Make the tier knob real: add a role-fit key to the sort so `role_minimums` and tier both express intent, or document explicitly that tier is intentionally dominant and *why* | 1 line + docs, or ~15 lines | medium — changes assignments for every consumer | S1 |
| P3 | Forward `daily-check` degradation to the user's stderr (or a one-line summary), instead of swallowing it | ~5 lines | low | S3 |
| P4 | Vendor `plugins/model-check.ts` in-repo + an install step; default `.model-check-config.example` to `daily` | ~40 lines | low | S4 |
| P5 | Stamp after apply succeeds; skip the lock (or block) under `RUN_UNCONDITIONAL` instead of returning silently | ~5 lines | medium — verify apply idempotency | S5 |
| P6 | Fix `README.md:56`; regenerate the `QUICK-REFERENCE` model table from the registry, or delete it | ~5 lines | none | S7 |
| P7 | Add `tests/selection.sh` — table-driven expected model per role per tier, ~40 lines | ~40 lines | low | S8, and it locks in whichever P2 outcome is chosen |
| P8 | Decide the project's identity: pick one name, one README title, and either decouple from Gentle-AI or declare the coupling in the README | docs | none | S7, S6 |

### Open decisions for the owner

1. **S1/P2 is a policy question, not a bug fix.** Is "privacy tier dominates capability" the intent? If yes, it should be stated in the registry prose and the README so the next reader does not read it as an accident. If no, the sort key order changes and every user's assignments change.
2. **S2/P1**: should a non-Gentle-AI user get a warning + refusal, or should the tool be explicitly Gentle-AI-only (and fail loudly when the agents are absent)?
3. **S8/P4 vs the repo's identity**: is the intent to keep this personal-machine tooling, or to support a fresh clone? That decides whether P4 and P8 are worth doing at all.

---

## Evidence appendix

- Delegated read-only audits: acquisition pipeline (`daily-check.sh`, 983 lines), selection brain (`select-role-model.sh`, `model-selector.sh`, `generate-agent-config.sh`, `apply-model-config.sh`, `privacy-tier-registry.json`), trigger layer (`session-start-hook.sh`, `check-upstream.sh`, `privacy-setup.sh`, plugin, `.bashrc`), strategy+docs (`README.md`, `QUICK-REFERENCE.md`, `AGENTS.md`, `odd/tasks/`, dotfiles).
- Parent verification: S1 by executing `select_role_model` over 10 roles × 4 tiers; S2 by executing the exact jq patch program; S3/S5 by reading both hook call sites; S4 by `git ls-files`; S6/S7 by grep against the registry; S8 by file inventory.
- No file outside this document was modified during the review.