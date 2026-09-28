# Feature: model-check-frequency

## Objective
Let the user choose how often the model check + assignment refresh runs, with the check able to fire on **every OpenCode startup** (the user's chosen mode), instead of only on shell start at most once per day.

## Problem
The refresh is triggered exclusively by `~/.bashrc:41` sourcing `session-start-hook.sh`, whose gate `already_ran_today()` (lines 28-51) hardcodes a **once-per-day** window against `results/.last-daily-run`.

Two consequences:
1. The frequency is not configurable — `daily` is the only possible value.
2. The trigger is the wrong event. OpenCode does not start a fresh interactive shell, so "OpenCode startup" is not what the hook observes. The project's own goal is that the assignment follows the models actually available when a session starts.

Roadmap memory `roadmap/next-features` (#266) queued this as the next feature on 2026-09-27 with the options **every session / once a day / once a week / once a month** and the user's chosen value **EVERY SESSION**. Confirmed again by the user, narrowed to *every OpenCode startup* (not every shell).

## Why
`daily-check.sh` fetches live catalog data (`opencode.ai/zen/v1/models`, `models.dev`, `zen.mdx`) and `apply-model-config.sh` writes `~/.config/opencode/opencode.jsonc`. Between two daily gate windows the assignment cannot react to a model appearing, disappearing, or changing limits — which is precisely the flexibility the project exists to provide.

## Scope (authorized)
- `session-start-hook.sh` — replace the hardcoded daily gate with a frequency gate plus an explicit trigger.
- **NEW** `~/.config/opencode/plugins/model-check.ts` — OpenCode startup trigger (outside the repo; explicitly authorized by the user as part of "ponte a ello" for the per-OpenCode-startup behavior).
- **NEW** `.model-check-config` (user, gitignored) + **NEW** tracked `.model-check-config.example`.
- `README.md`, `QUICK-REFERENCE.md` — document the option.
- NOT in scope: `daily-check.sh`, `apply-model-config.sh`, `select-role-model.sh`, `privacy-tier-registry.json`, `privacy-setup.sh`, `.privacy-config`.

### Why a new config file and not `.privacy-config`
`privacy-setup.sh:147` regenerates `.privacy-config` with `cat >` — any key added there is silently clobbered on the next privacy-setup run. A separate `.model-check-config` keeps the frequency out of the privacy domain and survives `privacy-setup.sh`. Both files are gitignored user state, so `.model-check-config.example` carries the tracked default.

## Design decisions
- **Trigger argument.** `session-start-hook.sh [opencode|shell]` (default `shell`, so the existing `.bashrc` wiring keeps working unchanged).
- **Gate by mode:**
  - `session` → the `shell` trigger returns immediately (no network on every new terminal); the `opencode` trigger runs unconditionally, i.e. every OpenCode startup.
  - `daily` / `weekly` / `monthly` → either trigger runs at most once per 1 / 7 / 30 days, decided by the existing stamp file, so the two triggers never double-run.
  - Unknown or missing value → fail closed to `daily` (the pre-existing behavior) with a one-line stderr notice; never crash, never silently widen the window.
- **Plugin follows `plugins/skill-registry.ts`**: non-awaited `execFile` so OpenCode startup stays responsive, `console.error` for diagnostics (stdout is reserved for CLI parsing), `process.env.MODEL_CHECK_REPO ?? <default>` for the repo path (mirrors `engram.ts:25`), and a path-existence guard so the plugin is inert outside a machine that has the repo.
- **Failure policy**: any non-zero exit from the hook is logged to stderr and swallowed — a failed refresh must never block OpenCode startup.

## Constraints
- Cheap local checks only: `bash -n`, `tsc --noEmit` if available, plugin load smoke, gate unit test with a temp stamp. No network calls in tests, no model evaluation.
- English for code/comments/docs; conventional commits; no AI attribution.
- `results/` stays gitignored; the stamp file keeps its existing name so an upgrade does not re-run a check that already ran.

## Tasks

### T1 — Configurable gate in `session-start-hook.sh`
Read `check_frequency` from `.model-check-config`, add the `opencode|shell` trigger argument, and implement the mode table above. Keep `models-apply()` and the existing lock/stamp/flock behavior intact.

- Route: delegated (writer). Trigger: 2+ non-trivial files.

### T2 — OpenCode startup plugin
Create `~/.config/opencode/plugins/model-check.ts` executing `session-start-hook.sh opencode`, non-awaited, guarded by repo-path existence.

### T3 — Config files + docs
Create `.model-check-config` with `check_frequency=session`, add `.model-check-config.example`, add `.model-check-config` to `.gitignore`, and document the option in `README.md` and `QUICK-REFERENCE.md`.

### T4 — Verify
- `bash -n session-start-hook.sh` → exit 0.
- Gate unit test in a `/tmp` copy: with `check_frequency=session` the `shell` trigger skips and the `opencode` trigger runs; with `daily` a fresh stamp makes both skip and a stale stamp makes them run; with an unknown value it falls back to `daily` with a notice. Report each as `<command>: <observed result>`.
- Plugin: `node --check` (or `tsc --noEmit`) on the `.ts` file; confirm OpenCode loads it on next startup.

## Acceptance criteria
- [x] The frequency is readable and editable without touching any script.
- [x] `session-start-hook.sh opencode` runs the check on every invocation when `check_frequency=session` (counter 1 → 2 on consecutive runs).
- [x] `session-start-hook.sh shell` does nothing when `check_frequency=session` (counter 0, stderr empty, `results/` not even created — no network on plain terminal starts).
- [x] `daily`/`weekly`/`monthly` still gate both triggers off one shared stamp (fresh stamp skips, stale stamp runs: daily 8d→run/0d→skip, weekly 8d→run/2d→skip, monthly 31d→run/10d→skip).
- [x] Missing/invalid config → `daily`, exit 0. **Refined during implementation:** a *missing* file/key/value falls back to `daily` **silently**, and the stderr notice fires only for an *unknown* (present but invalid) value. Reason: with `daily` as the fallback the shell trigger stays active, so a notice on a merely-absent file would print on every terminal start forever. The original acceptance line demanded a notice in both cases; this is a deliberate, narrower contract.
- [x] The plugin exists, is syntactically valid, and does not block OpenCode startup (returns `{}` in 1 ms, non-awaited; skip-guard and fire path both proven).
- [x] No file outside the authorized scope changed (`git diff --name-only` ∩ forbidden set → empty).

## Verification (observed results)
All run by the delegated writer; items marked ✓ were spot-checked again by the parent orchestrator.

- `bash -n session-start-hook.sh` → **exit 0** ✓ (parent re-ran).
- `git diff --name-only` ∩ {`daily-check.sh`, `apply-model-config.sh`, `select-role-model.sh`, `generate-agent-config.sh`, `privacy-*`, `.bashrc`, `opencode.jsonc`} → **empty, scope fence clean** ✓.
- `git status --short` → only `session-start-hook.sh`, `README.md`, `QUICK-REFERENCE.md`, `.gitignore` modified; `.model-check-config.example`, `odd/tasks/model-check-frequency.md` untracked. Diff: **4 files, +115/−16**.
- Gate matrix, `/tmp` harness with stubbed `daily-check.sh` (counter file) + stub `apply-model-config.sh`, stamp aged with `touch -d` — **15/15 as expected, all rc=0**:

| Case | Expected | Observed |
| --- | --- | --- |
| `session` + shell (no arg, as `.bashrc` wires) | count=0 | 0, stderr empty |
| `session` + opencode, run 1 → run 2 | 1 → 2 | **1 → 2** |
| `daily` + opencode, stamp age 0d / 8d | 0 / 1 | **0 / 1** |
| `weekly`, stamp age 8d / 2d | 1 / 0 | **1 / 0** |
| `monthly`, stamp age 31d / 10d | 1 / 0 | **1 / 0** |
| missing `.model-check-config`, fresh / absent stamp (daily) | 0 / 1 | **0 / 1**, silent |
| `bogus`, fresh stamp | 0 + notice | 0, notice printed: `unknown check_frequency "bogus" … falling back to daily` |
| `bogus`, no stamp | 1 | 1 |
| `session` + unrecognized arg → normalized to shell | 0 | 0 |
| `session` + shell creates no `results/` | absent | **absent** |

- Plugin load (TypeScript): `node --input-type=module -e "import('file:///…/plugins/model-check.ts')"` → `loaded, named: function default: function`, exit 0 (Node 22.23.2 strips types; harmless `MODULE_TYPELESS_PACKAGE_JSON` warning because `~/.config/opencode/package.json` has no `"type"`).
- Plugin skip-guard: `MODEL_CHECK_REPO=/tmp/opencode/no-such-repo …` → stderr `[model-check] skipping: hook not found: …`, exit 0, nothing run.
- Plugin fire: `MODEL_CHECK_REPO=/tmp/opencode/plugtest …` → returned `{}` in **1 ms** (non-blocking), stub hook recorded `opencode`.
- `bash -n` + `bash -ic` through the real `.bashrc:41` wiring → `models-apply=function`, exit 0, existing stamp mtime unchanged (sourced path stays inert under `session`).
- `git check-ignore -v .model-check-config` → ignored by `.gitignore:5`; `.model-check-config.example` → **not** ignored (correct).

### Not verified
- **`tsc --noEmit`**: no local/global TypeScript package and network install is forbidden — type-level checking was not performed; the fallback module-load smoke was used instead.
- **Live OpenCode startup loading the plugin**: needs a real OpenCode start. The plugin's load, guard, non-blocking return, and `opencode` invocation were proven with Node; the plugin will actually fire the next time OpenCode restarts.
- **Real-repo `session` + `opencode` run**: would execute `daily-check.sh` → network, so that path was exercised only against `/tmp` stubs. The real inert (`shell`) path was checked against the live repo.

## Progress
- [x] Feature document created (ODD step 5) before the first source write.
- [x] T1 gate — route: **delegated (writer `general`)**; trigger evidence: 2+ non-trivial files (`session-start-hook.sh`, `model-check.ts`), so the writer rule fired instead of inline editing.
- [x] T2 plugin `~/.config/opencode/plugins/model-check.ts` (68 lines, outside the repo).
- [x] T3 config + docs (`.model-check-config`, `.example`, `.gitignore`, `README.md` +28/−… , `QUICK-REFERENCE.md` +17).
- [x] T4 verification — see above; gatekeeper spot-checks re-ran `bash -n`, the scope fence, and the diff stat.
- [ ] Work-unit commit + RDD assess

## Delivery
- Strategy: `ask-on-risk`; forecast ≈ 100-130 authored changed lines (under 400 → single work unit).
- Note: the plugin lands in `~/.config/opencode/`, outside the repo, so it does not enter the diff or the review boundary. Repo-side commits are the hook, config example, gitignore, docs, and this document.
