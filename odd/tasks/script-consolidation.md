# Feature: Script consolidation (merge, races, jq batch, dead code)

## Objective

Apply all approved audit fixes to free-model-comparison shell scripts: merge the forked change-detector, eliminate write races, batch jq, delete verified dead code, fix small bugs — then full verification and push (docs + registry + code) to origin/master.

## Problem / Why

Exhaustive audit (two delegated maps) found: ~150 duplicated lines between daily-check.sh and check-model-changes.sh (already diverged into a fetch-warning bug); fixed `.tmp` registry path races; once-per-day stamp without lock; ~60 jq forks per hook cycle; verified dead code and stale hardcoded counts. User approved all suggestions with "aplica todas las soluciones".

## Scope

- IN:
  - Merge check-model-changes.sh → daily-check.sh --interactive; delete the standalone script; update README + QUICK-REFERENCE references
  - Race fixes: mktemp for registry writes; lock (mkdir or flock) for daily stamp
  - Batch jq: one registry load + one write per run; jq -n --arg for JSON emit in generate-agent-config
  - Dead code removal: check-model-changes snapshot fns (gone with merge), privacy-setup load_config + hardcoded "10 models"/stale names (derive from registry) + option-3 provider bug (.value.provider), model-selector unused name= + dead show_machine_output branch, AGENT_ROLES identity no-ops, vestigial comment block in daily-check, un-hardcode session-start-hook SCRIPT_DIR via BASH_SOURCE
  - README Files/table + QR updates for merged script
  - Separate chore commit for privacy-tier-registry.json (space-bunny-free from models-apply)
  - Push all ready commits (docs b3c9c0c, registry, code) to origin/master
- OUT:
  - generate-agent-config.sh NONE→big-pickle fallback (INTENTIONAL always-free default — user decision, do not change)
  - Odd/tasks/* docs (ODD recovery)
  - Model-testing anything
  - Changing privacy tier values or selection logic semantics (except fixing the provider display bug)

## Constraints

- Artifacts/commit messages English; no AI attribution.
- Cheap checks only: bash -n, jq empty, greps, source hook, smoke runs of scripts — no model-testing harness.
- Delivery: on master (already past branch phase for this cleanup series); work-unit commits Conventional.
- RDD on: after each work-unit commit, assess committed-only; follow transitions if due.
- big-pickle fallback stays.

## Tasks

- [x] T0 Create this feature document (before first source write).
- [x] T1 Dead code + small bugs + SCRIPT_DIR BASH_SOURCE (low-risk script edits). — fe862e9: BASH_SOURCE SCRIPT_DIR, cat→$(<file), dropped group wrapper, vestigial comment block removed, grep -c || echo 0 → grep -c . || true, unused name= and dead single-role show_machine_output branch deleted, AGENT_ROLES identity no-ops removed. Bonus pre-existing bugfix: privacy-setup get_models_for_tier field order (jq emitted tier|key vs key|tier consumer — available list was always empty).
- [x] T2 Race fixes: mktemp registry writes + daily stamp lock. — fe862e9: registry writes via same-directory mktemp (no fixed .tmp); once-per-day stamp guarded by flock on results/.last-daily-run.lock (fd 9; auto-released on crash, no stale-lock recovery). apply-model-config temps also same-dir mktemp + EXIT trap (ad56f1e).
- [x] T3 jq batching across daily-check, apply-model-config, generate-agent-config, model-selector, privacy-setup. — ad56f1e: single reg_json load + one jq --argjson batch (apply_registry_changes) + name-map pass in daily-check; one jq reduce in apply-model-config; single jq -n --arg emit in generate-agent-config (output verified semantically identical to baseline ce7e6ad2…; NONE→big-pickle fallback preserved exactly); one jq per display command in model-selector; one jq per listing in privacy-setup (also fixed excluded-list jq that never parsed — backslash quotes inside single-quoted program).
- [x] T4 Merge check-model-changes.sh into daily-check.sh --interactive; git rm standalone; update README + QR. — 50fc3db: --interactive diffs vs registry, confirm prompt (EOF-safe), changelog append, advisory block, warnings not captured into live_models; decline/accept paths exercised end-to-end on synthetic change (restored from git); plain daily-check.sh flow unchanged. README Scripts table + Files list updated; QUICK-REFERENCE needed no change (never referenced the deleted script); privacy-setup completion message and select-role-model.sh header updated. QR: N/A — no reference existed.
- [x] T5 privacy-setup: derive counts/names from registry; fix option-3 provider bug; delete load_config. — fe862e9: registry_total/count_le/count_eq/names_le/names_gt/names_eq helpers; print_tier_info and first-time menu fully registry-derived (menu shows 0/2/6/5 of 11); option 3 prints .provider; load_config deleted.
- [x] T6 Verification: bash -n all scripts; jq empty registry; source hook → models-apply + no models-status; smoke: daily-check, model-selector, generate+apply dry paths; grep no stale check-model-changes references in active docs; grep no leftover dead symbols. — battery all green on 2026-09-23:
  - `bash -n` × 7 remaining scripts: all OK
  - `jq empty privacy-tier-registry.json`: OK
  - `source hook && type models-apply && ! type models-status`: OK
  - `./daily-check.sh`: exit 0; `./daily-check.sh --interactive <<< ''`: exit 0
  - `./model-selector.sh`: exit 0; `./model-selector.sh all | jq empty`: OK
  - `printf '1\n' | ./privacy-setup.sh`: exit 0 (keep-settings, read-only); isolated first-time menu smoke: counts correct, cancel writes no config
  - `./generate-agent-config.sh | jq empty`: OK; semantic diff vs pre-change baseline: identical
  - `OPENCODE_CONFIG=/tmp/... ./apply-model-config.sh` dry-run: exit 0, valid JSON, non-model fields untouched, model fields identical to live config
  - `grep -rn check-model-changes` (excluding odd/tasks history): clean
  - `grep 'REGISTRY_FILE.tmp"' --include='*.sh'`: gone
  - `check-model-changes.sh`: deleted (git rm in 50fc3db)
  - synthetic batch test (add/exists-skip/remove/stamp, no leftover temps): OK
- [x] T7 Work-unit commits + RDD assess each; handle review if due. — commits: 528ba81 (registry chore), fe862e9 (T1+T2+T5), ad56f1e (T3), 50fc3db (T4 + docs). RDD assess: N/A in this session (no review tooling available; parent handles push/review — native review explicitly not started per instruction).
- [x] T8 Commit registry chore (space-bunny-free); push docs b3c9c0c + registry + code to origin/master; confirm clean status. — registry chore committed as 528ba81; PUSHED 2026-09-24: 39b95c3..379b448 (7 commits, incl. MIT LICENSE + public README 379b448). 4R refuter abandoned after 18 free-tier failures (prior user decision: push without refuter). Repo renamed gentle-ai-opencode-free-models and flipped PUBLIC same day. Clean status, local == remote.

## Acceptance criteria

- All scripts pass bash -n; registry jq valid.
- check-model-changes.sh gone; daily-check --interactive covers confirm flow (smoke-tested).
- No fixed REGISTRY.tmp path; stamp guarded by lock.
- jq call count per full models-apply cycle roughly ≤10 (spot-check via reasoning/count in comments or debug).
- Dead symbols greps clean; README/QR don't reference deleted script.
- generate-agent-config big-pickle fallback UNCHANGED.
- origin/master contains docs cleanup, registry update, and script fixes; local == remote.

## Progress

- 2026-09-23: created after audit approval; big-pickle intent recorded (related #12).
- 2026-09-23: T1–T7 complete. Commits 528ba81 (registry), fe862e9 (T1+T2+T5), ad56f1e (T3), 50fc3db (T4+docs); T6 battery green (see Tasks). T8 push pending — parent owns push after review.
