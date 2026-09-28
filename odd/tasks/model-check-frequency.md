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
  - `session` → the `opencode` trigger runs unconditionally (every OpenCode startup). The `shell` trigger is a **degraded-mode backstop, not an inert path**: silent while the shared stamp is fresh, and it falls back to the pre-existing 1-day path (printing one stderr warning naming the plugin) once the stamp is absent or older than 1 day. Without that backstop a plugin that never loads would disable every trigger this repository owns and leave no observable trace — the one CRITICAL raised by native review (`R4-SESSION-MODE-SILENT-TOTAL-LOSS`, corroborated).
  - `daily` / `weekly` / `monthly` → either trigger runs at most once per 1 / 7 / 30 days, decided by the existing stamp file, so the two triggers never double-run.
  - Unknown or missing value → fail closed to `daily` (the pre-existing behavior) with a one-line stderr notice; never crash, never silently widen the window. **The same posture now extends to `session`**: it degrades to the daily path instead of degrading to nothing.
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
- [x] `session-start-hook.sh shell` with `check_frequency=session` is a **backstop**, not an inert path: **(a)** fresh stamp → silent skip (counter 0, stderr empty, nothing created — no network on ordinary terminal starts while the plugin is healthy); **(b)** stamp older than 1 day or absent → runs (counter 1) and prints exactly one stderr warning naming the plugin. **Verified 20/20** in `/tmp/opencode/freqfix/run.sh`, cases (a) and (b) both PASS. *(Revised by native review: the original criterion demanded unconditional silence, which left `session` as the only value with no fallback at all.)*
- [x] `daily`/`weekly`/`monthly` still gate both triggers off one shared stamp (fresh stamp skips, stale stamp runs: daily 8d→run/0d→skip, weekly 8d→run/2d→skip, monthly 31d→run/10d→skip).
- [x] Missing/invalid config → `daily`, exit 0. **Refined during implementation:** a *missing* file/key/value falls back to `daily` **silently**, and the stderr notice fires only for an *unknown* (present but invalid) value. Reason: with `daily` as the fallback the shell trigger stays active, so a notice on a merely-absent file would print on every terminal start forever. The original acceptance line demanded a notice in both cases; this is a deliberate, narrower contract.
- [x] The plugin exists, is syntactically valid, and does not block OpenCode startup (returns `{}` in 1 ms, non-awaited; skip-guard and fire path both proven).
- [x] No file outside the authorized scope changed (`git diff --name-only` ∩ forbidden set → empty).

## Verification (observed results)
All run by the delegated writer; items marked ✓ were spot-checked again by the parent orchestrator.

- `bash -n session-start-hook.sh` → **exit 0** ✓ (parent re-ran).
- `git diff --name-only` ∩ {`daily-check.sh`, `apply-model-config.sh`, `select-role-model.sh`, `generate-agent-config.sh`, `privacy-*`, `.bashrc`, `opencode.jsonc`} → **empty, scope fence clean** ✓.
- `git status --short` → only `session-start-hook.sh`, `README.md`, `QUICK-REFERENCE.md`, `.gitignore` modified; `.model-check-config.example`, `odd/tasks/model-check-frequency.md` untracked. Diff: **4 files, +115/−16**.
- Gate matrix, `/tmp/freqfix/run.sh` harness with stubbed `daily-check.sh` (counter file) + stub `apply-model-config.sh`, stamp aged with `touch -d "<n> days ago"` — **20/20 as expected, all rc=0** (re-run after the review correction; the pre-correction run was 15/15):

| Case | Expected | Observed |
| --- | --- | --- |
| `session` + shell (no arg, fresh stamp, as `.bashrc` wires) | count=0, silent | 0, stderr empty |
| `session` + shell, stamp 8d → **backstop** | count=1 + plugin notice | **1 + notice** |
| `session` + shell, stamp absent → **backstop** | count=1 + plugin notice | **1 + notice** |
| `session` + shell, stamp 1d-old (still fresh) | count=0, silent | **0, silent** |
| `session` + shell (no arg), no stamp → **backstop** | count=1 + plugin notice | **1 + notice** |
| `session` + opencode, consecutive runs | unconditional | **1 / 1** (fresh stamp, daily would skip) |
| `daily` + opencode, stamp age 0d / 8d | 0 / 1 | **0 / 1** |
| `weekly`, stamp age 8d / 2d | 1 / 0 | **1 / 0** |
| `monthly`, stamp age 31d / 10d | 1 / 0 | **1 / 0** |
| missing `.model-check-config`, fresh / absent stamp (daily) | 0 / 1 | **0 / 1**, silent |
| `bogus`, fresh stamp | 0 + notice | 0, notice printed: `unknown check_frequency "bogus" … falling back to daily` |
| `bogus`, no stamp | 1 | 1 |
| `session` + unrecognized arg → normalized to shell | 0 | 0 |
| `session` + shell, fresh stamp → creates no `results/` | absent | **absent** |
| `session` + shell, no stamp → backstop creates `results/` | present + notice | **present + notice** |

- Plugin load (TypeScript): `node --input-type=module -e "import('file:///…/plugins/model-check.ts')"` → `loaded, named: function default: function`, exit 0 (Node 22.23.2 strips types; harmless `MODULE_TYPELESS_PACKAGE_JSON` warning because `~/.config/opencode/package.json` has no `"type"`).
- Plugin skip-guard: `MODEL_CHECK_REPO=/tmp/opencode/no-such-repo …` → stderr `[model-check] skipping: hook not found: …`, exit 0, nothing run.
- Plugin fire: `MODEL_CHECK_REPO=/tmp/opencode/plugtest …` → returned `{}` in **1 ms** (non-blocking), stub hook recorded `opencode`.
- `bash -n` + `bash -ic` through the real `.bashrc:41` wiring → `models-apply=function`, exit 0, existing stamp mtime unchanged (sourced path stays silent under `session` while the stamp is fresh — live stamp was 5h old at check time, so no network fired).
- `git check-ignore -v .model-check-config` → ignored by `.gitignore:5`; `.model-check-config.example` → **not** ignored (correct).

### Not verified
- **`tsc --noEmit`**: no local/global TypeScript package and network install is forbidden — type-level checking was not performed; the fallback module-load smoke was used instead.
- **Live OpenCode startup loading the plugin**: needs a real OpenCode start. The plugin's load, guard, non-blocking return, and `opencode` invocation were proven with Node; the plugin will actually fire the next time OpenCode restarts.
- **Real-repo `session` + `opencode` run**: would execute `daily-check.sh` → network, so that path was exercised only against `/tmp` stubs. The real silent (`shell` + fresh stamp) path was checked against the live repo.

## Native review correction (RDD, lineage `review-85bbad4509c0d23b`)

Candidate `bf25bcc` was assessed `high_risk` → review_due → consent granted → 4 lenses (risk / resilience / readability / reliability) + one read-only refuter batch.

- **One CRITICAL, corroborated:** `R4-SESSION-MODE-SILENT-TOTAL-LOSS` (lens `resilience`, `causal_disposition: introduced`, location `session-start-hook.sh:88`). Under `check_frequency=session` the `shell` trigger returned 0 *before* `mkdir`, lock, log, and network, so the only trigger owned by this repo was unconditionally disabled; the sole replacement lived outside the repo, and if it never loaded the refresh died with **no** stderr line, **no** log record, and no second trigger — indistinguishable from a quiet normal terminal start, and the exact opposite of the candidate's own stated fail-closed posture. `session` was also the value shipped in the tracked copyable example.
- **Correction (one bounded, ≤126 lines):** `session` + `shell` became a **degraded-mode backstop** instead of an inert path.
  - Healthy (shared stamp fresh, i.e. the plugin checked in within 1 day) → still silent, nothing created, no network: the user's chosen "every OpenCode startup" behavior is unchanged.
  - Degraded (stamp absent or >1 day old) → falls back to the pre-existing 1-day path and prints one stderr warning naming `~/.config/opencode/plugins/model-check.ts`.
  - Implemented via `RUN_UNCONDITIONAL` (only `session` + `opencode` skips the stamp gate) + `DEGRADED_BACKSTOP` (notice emitted *after* the under-lock re-check, so it prints at most once per degraded period).
  - Docs corrected to stop claiming the `shell` trigger is "inert": `README.md`, `QUICK-REFERENCE.md`, `.model-check-config.example`, and this document.
- **Verification after correction:** `bash -n` → exit 0; gate matrix **20/20**; scope fence still only the 5 review paths; `results/.last-daily-run` live stamp was 5h old, so the real sourced path stayed silent (no network fired).
- Remaining non-blocking findings (WARNING/SUGGESTION, informational): `R4-STAMP-GATE-FAILS-OPEN-TO-EVERY-RUN`, `R4-SESSION-MODE-WRITES-CONFIG-DURING-CONSUMER-STARTUP`, `R4-SESSION-MODE-RETRIES-WITHOUT-BACKOFF`, `R2-PLUGIN-ABSENT-FROM-REPO`, `R1-outside-repo-plugin-execution`, plus doc/pin/sed-pattern notes.

## Progress
- [x] Feature document created (ODD step 5) before the first source write.
- [x] T1 gate — route: **delegated (writer `general`)**; trigger evidence: 2+ non-trivial files (`session-start-hook.sh`, `model-check.ts`), so the writer rule fired instead of inline editing.
- [x] T2 plugin `~/.config/opencode/plugins/model-check.ts` (68 lines, outside the repo).
- [x] T3 config + docs (`.model-check-config`, `.example`, `.gitignore`, `README.md` +28/−… , `QUICK-REFERENCE.md` +17).
- [x] T4 verification — see above; gatekeeper spot-checks re-ran `bash -n`, the scope fence, and the diff stat.
- [x] T5 native review correction for `R4-SESSION-MODE-SILENT-TOTAL-LOSS` — 20/20 gate matrix re-run, docs reconciled.
- [x] Work-unit commit + RDD assess — feature commit `bf25bcc` (assessed `high`, review triggered), correction commit `dad8b83`; native review **approved** and acknowledged, authority burned. Post-ack docs commit assessed separately (see Engram mirror `odd/model-check-frequency/tasks`).

## Delivery
- Strategy: `ask-on-risk`; forecast ≈ 100-130 authored changed lines (under 400 → single work unit).
- Note: the plugin lands in `~/.config/opencode/`, outside the repo, so it does not enter the diff or the review boundary. Repo-side commits are the hook, config example, gitignore, docs, and this document.

### Review outcome

- **State: `approved`.** Correction validated by the native targeted validator; no blocking findings remain.
- Correction target: `sha256:f88f76c56192da6b747fa6560b6ba5f041b39077098b41a13bdd08e7fd0cce05`; store revision at approval: `sha256:0c59ac12be784c522f6bb757a6523eadfb6b17ef2a990071d021d09097ae169b`.
- Corrected candidate tree: `754e455d2ab1a47a0844871280aa2e6a3a378070` (commit `dad8b83`).
- The CRITICAL `R4-SESSION-MODE-SILENT-TOTAL-LOSS` no longer appears in the approved finding set.

### Advisory findings at approval (29, all `informational`)

Native statement: *"approved and its receipt stands. None opened a correction, none reopens this review, no correction transition is offered. Treat them as separate later work, never as a reason to re-run review on this candidate."*

| ID | Lens | Location | Severity |
| --- | --- | --- | --- |
| `R1-freq-unvalidated-echo` | risk | session-start-hook.sh:46-47 | WARNING |
| `R1-gate-preexec-parse-race` | risk | session-start-hook.sh:39-44 | SUGGESTION |
| `R1-hook-baseline-privilege-boundary` | risk | session-start-hook.sh:92-99 | SUGGESTION |
| `R1-outside-repo-plugin-execution` | risk | odd/tasks/model-check-frequency.md:30 | WARNING |
| `R1-session-mode-bypasses-gate` | risk | session-start-hook.sh:74-80 | WARNING |
| `R1-stamp-mtime-replaces-date-gate` | risk | session-start-hook.sh:63-67 | WARNING |
| `R2-DUAL-GATE-LOGIC` | readability | session-start-hook.sh:86-91 | WARNING |
| `R2-EXAMPLE-DEFAULT-MISMATCH` | readability | .model-check-config.example:9 | WARNING |
| `R2-EXAMPLE-FREQUENCY-NOT-INVOKED` | readability | QUICK-REFERENCE.md:25 | WARNING |
| `R2-MODE-TABLE-DRIFT` | readability | session-start-hook.sh:41-55 | WARNING |
| `R2-NAMED-DAILY-SURFACES` | readability | session-start-hook.sh:26 | WARNING |
| `R2-PLUGIN-ABSENT-FROM-REPO` | readability | odd/tasks/model-check-frequency.md:19 | SUGGESTION |
| `R2-SILENT-VS-NOTICE-CONTRACT` | readability | odd/tasks/model-check-frequency.md:76 | WARNING |
| `R2-STALE-LOG-HEADER` | readability | session-start-hook.sh:112 | WARNING |
| `R2-STAMP-DAY-BOUNDARY-INTENT-UNDOCUMENTED` | readability | session-start-hook.sh:80-83 | SUGGESTION |
| `R2-STAMP-READS-BECOME-DEAD` | readability | session-start-hook.sh:75-77 | WARNING |
| `R2-UNPINNED-EXTERNAL-PLUGIN` | readability | odd/tasks/model-check-frequency.md:105 | WARNING |
| `R2-UNPINNED-SCOPE-CLAIM` | readability | odd/tasks/model-check-frequency.md:86 | SUGGESTION |
| `R3-doc-plugin-mismatch` | reliability | README.md:74-79 | WARNING |
| `R3-inert-shell-every-parse` | reliability | session-start-hook.sh:36-40 | SUGGESTION |
| `R3-last-run-content-dropped` | reliability | session-start-hook.sh:85-88 | SUGGESTION |
| `R3-lost-under-lock-recheck` | reliability | session-start-hook.sh:103-111 | SUGGESTION |
| `R3-no-persistent-test` | reliability | odd/tasks/model-check-frequency.md:66-74 | WARNING |
| `R3-sed-silently-ignores-freq` | reliability | session-start-hook.sh:42-47 | WARNING |
| `R3-stamp-undeclared-ds` | reliability | session-start-hook.sh:85-88 | WARNING |
| `R4-SESSION-MODE-RETRIES-WITHOUT-BACKOFF` | resilience | session-start-hook.sh:90 | WARNING |
| `R4-SESSION-MODE-WRITES-CONFIG-DURING-CONSUMER-STARTUP` | resilience | session-start-hook.sh:85 | WARNING |
| `R4-STAMP-GATE-FAILS-OPEN-TO-EVERY-RUN` | resilience | session-start-hook.sh:82 | WARNING |
| `R4-UNKNOWN-VALUE-NOTICE-ON-EVERY-STARTUP` | resilience | session-start-hook.sh:52 | SUGGESTION |

#### Follow-up candidates worth picking up later (not blocking, not now)

1. **`R3-doc-plugin-mismatch` + `R2-UNPINNED-EXTERNAL-PLUGIN`** — README/QUICK-REFERENCE promise an `opencode` trigger that no tracked path installs; a fresh clone gets `session` mode with only a shell trigger. Highest practical value: one install-guidance line next to the `.bashrc` snippet.
2. **`R4-STAMP-GATE-FAILS-OPEN-TO-EVERY-RUN` + `R3-stamp-undeclared-ds`** — `find -mtime` failure degrades to "always run", and `-mtime` rounds *down* so the "once per 1 day" claim can slip ~a day. Replacing the probe with a bash-builtin epoch comparison fixes both and drops an external dependency on the terminal startup path.
3. **`R3-sed-silently-ignores-freq`** — a `check_frequency` line sed cannot match (commented out, `export` prefix, CRLF) silently becomes `daily`; same class of silent fallback we just fixed for `session`.
4. **`R2-STALE-LOG-HEADER`** — the log banner still says `daily sync` for weekly/monthly runs; one mechanical string change.
5. **`R3-no-persistent-test`** — the 20/20 matrix lives only in `/tmp`; committing it would give the gate a real regression assertion.
