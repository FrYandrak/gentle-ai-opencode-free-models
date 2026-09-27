# Feature: daily-check-verify (limits + privacy verification in the daily check)

## Objective

Make `daily-check.sh` the trunk verification point for **all three** registry
data sources — model existence, limits, and privacy — so a newly detected model
never lands with fabricated limits or an unexamined privacy tier, and so drift
in existing entries is surfaced on every run.

## Problem / Why

The registry has three sources of truth, but only one is wired up:

| Data | Source of truth | Read by |
| --- | --- | --- |
| Which models exist / are free | `https://opencode.ai/zen/v1/models` | `daily-check.sh` `fetch_zen_models` ✅ |
| `context_window` / `output_limit` | `https://models.dev/api.json` | nobody — prose only (`selection_rules.limits_reverify`) ❌ |
| `privacy_tier` / `evidence` / `privacy_url` | `https://opencode.ai/docs/zen/` §Privacy | nobody — tiers hand-built from provider policies ❌ |

Consequences observed 2026-09-26/27:

- `opencode/longcat-2.5-preview-free` was auto-added with the hardcoded default
  `context_window: 262144`; models.dev records `1000000`. Corrected manually in
  `bc57e3d`. A full comparison of all 12 entries found exactly this one wrong —
  wrong precisely because nothing re-verifies.
- `opencode/space-bunny-free` and `opencode/longcat-2.5-preview-free` sat at
  `4_explicit_training` while the official Zen docs state affirmatively that
  both follow a **zero-retention policy and do not use data for model
  training** (tier 1 by our own definition). Corrected manually after user
  consultation on 2026-09-27.
- The same gap was already reported twice by native 4R reviews
  (`review-4d181d4d9e1381be`: "No validation against models.dev occurs at add
  time"; `review-15f683aae201bebd`: "`limits_reverify` is prose, not
  machine-readable") and declined as out of scope. It remains open.

User decision 2026-09-27: privacy verification is **core project scope**, not
optional maintenance — wire it into `daily-check.sh` now.

## Scope

### IN

- `daily-check.sh`:
  - **T1 fetch helpers.** `fetch_limits_doc()` → `https://models.dev/api.json`
    (raw JSON); `fetch_privacy_doc()` → the Zen docs MDX source
    `https://raw.githubusercontent.com/anomalyco/opencode/dev/packages/web/src/content/docs/zen.mdx`
    (raw markdown; the rendered HTML page is a fallback, not the primary).
    Both: `curl --max-time` bounded, fail-soft (return empty + yellow notice,
    never non-zero) — the script runs under `set -e` inside the session-start
    hook, so a fetch failure must degrade, not abort.
  - **T2 privacy classifier.**
    - `zen_display_name <id>`: literal `awk` lookup of the `| Model | Model ID |`
      pricing table → display name. Missing name ⇒ no signal (fail-closed).
    - `privacy_statement <name>`: collect every line that *literally starts*
      with `- <name>` (`awk 'index($0,p)==1'` — no regex escaping of `.`/`+`).
      Covers both the §Privacy exception bullets and the free-model bullets.
    - `classify_privacy <text>`: first match wins, in this order —
      1. `zero-retention` **and** `does not use your data for model training`
         ⇒ `1_strict`
      2. `permission to use your prompts` | `train future` |
         `explicitly … train` ⇒ `4_explicit_training`
      3. `not linked to your identity` | `not linked to identity`
         ⇒ `2_anonymous_improvement`
      4. `improve the model` ⇒ `3_model_improvement`
      5. otherwise ⇒ empty (no signal, fail-closed)
      Order is load-bearing: Nemotron carries both "improve NVIDIA products"
      and "not linked to your identity" (must resolve to 2, not 3); Muse Spark
      1.3 carries both "improve the model" and "train future Meta models"
      (must resolve to 4, not 3).
  - **T3 add-time verification.** After `apply_registry_changes`, run
    `verify_new_models "$added"`: for each newly added id, if limits are found
    in models.dev write real `context_window`/`output_limit` + a
    `Limits verified against models.dev <date>` note; if a privacy signal is
    found write that tier with `evidence` = the verbatim matched Zen-doc line
    and `privacy_url` = `https://opencode.ai/docs/zen/#privacy`. Anything
    missing keeps the existing fail-closed defaults (tier 4, add-time limit
    defaults, `UNVERIFIED` evidence). Verify is a **second pass**, so the
    add path stays unchanged and the fallback is already correct.
  - **T4 drift report (advisory only).** Every run, for **existing** entries,
    compare registry limits vs models.dev and registry tier vs classified tier;
    print a yellow advisory on mismatch. **Never mutate existing entries** —
    a tier downgrade would silently unlock a model, which is a human privacy
    decision. Plus one compact line listing models with *no* affirmative
    statement in the official docs (currently `deepseek-v4-flash-free`,
    `jev-1.13-free`, `muse-spark-1.2-contributor-free`) so the manual queue is
    always visible. Placed after the registry update, before the assignments
    table.
- `privacy-tier-registry.json`: `selection_rules.limits_reverify` and
  `selection_rules.privacy_source` rewritten to state they are now executed by
  `daily-check.sh` (add-time + daily drift report), keeping the manual command
  as the offline fallback. Top-level `source` gains the Zen docs URL.
- `README.md` / `QUICK-REFERENCE.md`: one short line each stating that the
  daily check verifies limits against models.dev and privacy against the Zen
  docs §Privacy section.

### OUT

- Changing any existing model's `privacy_tier` — report-only (T4). The three
  manual tiers fixed on 2026-09-27 are already committed.
- Auto-parsing privacy from provider policies (Xiaomi, Meta, NVIDIA, DeepSeek,
  TypeSafe) — the Zen docs are the single official source we trust.
- `check-upstream.sh` (upstream release drift — different concern).
- Any model-quality / benchmark scoring (forbidden by `AGENTS.md`).
- Model-testing evaluation of any kind (free-token budget policy).

## Constraints

- English artifacts; conventional commits; no AI attribution.
- Cheap checks only: `bash -n`, `jq empty`, smoke runs, one live fetch. **No
  model evaluation.**
- RDD is on (global): assess the work-unit commit with
  `gentle-ai review assess --agent opencode --committed-only`.
- Direct commits on `master` (repo's ordinary policy).
- Never touch `~/.config/opencode/opencode.jsonc`.
- `daily-check.sh` is invoked by `session-start-hook.sh` with stdout+stderr
  redirected to `results/session-start.log` and gated by flock + once-per-day
  stamp; output format is free but the script must never exit non-zero on a
  network failure (a failed check makes the hook retry every session).
- Free-only rule: paid models must never enter the pipeline (unchanged).

## Ground truth (verified against live sources 2026-09-27)

Classifier must reproduce this table exactly:

| id | Zen docs say | expected tier |
| --- | --- | --- |
| `big-pickle` | "…collect feedback and improve the model" + exception "may be used to improve the model" | `3_model_improvement` |
| `mimo-v2.5-free` | same pattern | `3_model_improvement` |
| `mimo-v2.6-flash-free` | same pattern | `3_model_improvement` |
| `ling-3.0-flash-fin-free` | same pattern | `3_model_improvement` |
| `nemotron-3-ultra-free` | NVIDIA: "logged… **not linked to your identity**" | `2_anonymous_improvement` |
| `nemotron-3.5-lightning-free` | same | `2_anonymous_improvement` |
| `muse-spark-1.3-contributor-free` | "permission to use your prompts… to **train future Meta models**" | `4_explicit_training` |
| `space-bunny-free` | "**zero-retention** policy and does not use your data for model training" | `1_strict` |
| `longcat-2.5-preview-free` | same | `1_strict` |
| `jev-1.13-free` | "is available on OpenCode for a limited time." — no privacy keywords | no signal ⇒ stay `4` |
| `deepseek-v4-flash-free` | absent from the Zen docs entirely | no signal ⇒ stay `4` |
| `muse-spark-1.2-contributor-free` | absent from the Zen docs entirely | no signal ⇒ stay `4` |

Limits ground truth: 11/12 registry entries already match
`https://models.dev/api.json`; only `jev-1.13-free` is absent from models.dev
(it is a typed-decision model, not a text LLM) ⇒ limits verification must skip
it silently rather than warn.

## Tasks

- [x] T0 Create this feature document + Engram mirror (before first source
      write). Mirror topic: `odd/daily-check-verify/tasks`.
- [x] T1 `daily-check.sh`: fetch helpers for models.dev + Zen docs MDX,
      fail-soft under `set -e`.
- [x] T2 `daily-check.sh`: `zen_display_name` / `privacy_statement` /
      `classify_privacy` with the ordered rules above.
- [x] T3 `daily-check.sh`: `verify_new_models` second pass over `apply_registry_changes`.
- [x] T4 `daily-check.sh`: daily drift report (advisory only, no mutation) +
      unverified-privacy queue line.
- [x] T5 Registry prose: `limits_reverify` + `privacy_source` + `source`.
- [x] T6 Docs: README + QUICK-REFERENCE one-liners.
- [x] T7 Verification: `bash -n daily-check.sh`, `jq empty` registry, live run
      of the classifier producing the exact ground-truth table, one live
      `./daily-check.sh` run with drift output empty, and a synthetic
      add-path test (temporary registry copy, new fake id → tier 4 fallback;
      fake id present in models.dev → real limits).
- [x] T9 **Pre-existing bug found during T7 verification** (not introduced by
      this feature — reproduced identically on `HEAD`): `set -e` aborts the
      script at `live_models=$(fetch_zen_models)` whenever the Zen API is
      unreachable, so the designed fallback ("Could not fetch live model
      list… Continuing with local registry") was dead code and the session
      hook reported `Daily check FAILED` on every shell during an outage.
      Fix: `$(fetch_zen_models || true)`.
- [x] T8 Work-unit commit + RDD assess. Committed as `8cb482e` (assess
      `high_risk` → `review_due:true`); native 4R review
      `review-6bcac0537eb2eb51` closed **`approved`** and its authority was
      burned on 2026-09-27 (`gentle-ai.review-acknowledged/v1`). 4/4 lenses
      admitted; the refuter corroborated one CRITICAL readability finding
      (R2-2: `classify_privacy` rule order load-bearing) which was fixed by
      commit `8d75fff` (rank-based precedence, 52 lines ≤ 200 budget),
      validated by the targeted validator (no regressions), and approved.
      Advisory, non-blocking: R2-1 (WARNING, `verify_new_models` complexity)
      and R4-001 (WARNING, informational).

## Acceptance criteria

- A model auto-added by `daily-check.sh` receives its **real** models.dev
  limits when models.dev knows it, and a **tier from the official Zen docs**
  when those docs make an affirmative statement; otherwise it keeps the
  fail-closed tier 4 + `UNVERIFIED` evidence + add-time limit defaults.
- A network failure in either verification fetch produces a yellow notice and
  the script still exits 0.
- Existing registry entries are never silently rewritten by the daily run;
  mismatches are printed instead.
- The classifier reproduces the ground-truth table above byte-for-byte.
- `bash -n daily-check.sh` and `jq empty privacy-tier-registry.json` are green.

## Delivery forecast

Authored changed lines ≈ 270 (daily-check.sh ~170, registry ~4, docs ~8,
this document ~110) — under the 400-line budget; single work-unit commits on
`master`, no chained PRs required.

## Progress

- 2026-09-27: created (T0). Source: user request to make privacy/limit
  verification part of the trunk daily check; diagnosis traced the gap to
  `selection_rules.limits_reverify` and privacy being prose with no reader.
- 2026-09-27: T1–T6 implemented by writer `general` (`paths-injected`).
- 2026-09-27: T7 verification green — see evidence below. T9 found and fixed
  during the parent spot check (pre-existing, reproduced on `HEAD`).
- 2026-09-27: T8 closed — native 4R review `review-6bcac0537eb2eb51`
  approved + acknowledged after one bounded correction (`8d75fff`).
  Correction evidence: `bash -n` green; ground-truth classifier cases 7/7
  (including both multi-rule overlaps); shuffled-rule-block run also 7/7,
  proving precedence no longer depends on textual order.

## Verification evidence (2026-09-27)

Writer-reported, re-run and confirmed by the orchestrator:

- `bash -n daily-check.sh` → exit 0. `jq empty privacy-tier-registry.json` → exit 0.
- Classifier vs ground truth: **12/12 exact** — `big-pickle`→3,
  `mimo-v2.5-free`→3, `mimo-v2.6-flash-free`→3, `ling-3.0-flash-fin-free`→3,
  `nemotron-3-ultra-free`→2, `nemotron-3.5-lightning-free`→2,
  `muse-spark-1.3-contributor-free`→4, `space-bunny-free`→1,
  `longcat-2.5-preview-free`→1, and **empty** (fail-closed) for
  `jev-1.13-free`, `deepseek-v4-flash-free`, `muse-spark-1.2-contributor-free`.
- Live `./daily-check.sh` → exit 0; drift section reports no limits drift and
  no tier mismatch, and prints exactly one line naming the three models with
  no affirmative statement in the official docs. Registry `last_updated`
  unchanged (report-only confirmed).
- Synthetic add path: unknown id keeps tier 4 + `UNVERIFIED` + add-time limit
  defaults; `space-bunny-free` re-added gets tier `1_strict` with verbatim
  evidence, `privacy_url`, and real limits `1048576`/`524288`.
- **Fail-soft (orchestrator spot check, all network dead via a `curl` shim on
  `PATH`)**: before T9 the script exited **1** with no output past
  "Checking OpenCode Zen…" — identical on `HEAD`, i.e. pre-existing; after T9
  it exits **0** with three yellow notices, the previously-dead
  "Could not fetch live model list… Continuing with local registry" fallback
  now prints, and the full assignments table still renders.
- models.dev payload is 4.9 MB but downloads in ~0.37 s — within the
  `--max-time 15` budget for the once-per-day session hook.
- Parent read-back of the whole `daily-check.sh` diff: no hardcoded thresholds
  added, no model tier/limit mutated outside the add path, no `git` writes
  performed by the writer.
