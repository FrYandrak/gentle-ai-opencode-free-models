# Feature: Advisory follow-ups (rename, tier docs, naming)

## Objective

Clear the three advisory non-blocking findings from the approved 4R review of the PR #1 cleanup: (1) rename `models-status` to a name that matches what it does, (2) stop hardcoding the privacy tier in docs — one source of truth, (3) remove naming/branch/doc inconsistencies.

## Problem / Why

User approved all three after PR #1 merge explanation:

1. `models-status` sounds read-only but runs `daily-check.sh && apply-model-config.sh` (report + write).
2. Tier `3` is already defined once in `.privacy-config` (`privacy_max_tier`) and loaded by `load_privacy_tier`; docs still spell `3` in several places.
3. Stale branch name `feat/quiet-daily-mimo-v26` (actual: `feat/quiet-daily-hook`), SETUP-COMPLETE still says "deliver/merge PR #1" after the merge, ODD umbrella vs split features.

## Scope

- IN: rename command + all references; docs point at `.privacy-config` / `privacy_max_tier` instead of repeating `3`; fix wrong branch names and post-merge next-step wording; light ODD cross-links.
- OUT: changing the actual tier value; rewriting historical ODD evidence facts (what tier was observed at capture time); registry/selection logic; new features.

## Constraints

- Artifacts/commit messages in English; no AI attribution.
- Cheap checks only (`bash -n`, `jq empty`, greps, source hook) — no model-testing.
- Delivery strategy: ask-on-risk (session default).

## Tasks

- [x] T0 Create this feature document (before first source write).
- [x] T1 Rename `models-status` → `models-apply` in `session-start-hook.sh` + user-facing docs.
- [x] T2 Docs: tier comes from `.privacy-config` only; remove hardcoded user-facing `3` where it states current config.
- [x] T3 Naming: correct `feat/quiet-daily-mimo-v26` → `feat/quiet-daily-hook`; clear stale "merge PR #1" next actions; align ODD cross-links.
- [x] T4 Verify: `bash -n` hook; source hook defines `models-apply`; no leftover `models-status` in active docs/code; grep clean for wrong branch name (historical rename notes only).
- [x] T5 Work-unit commit + RDD assess on the commit.

## Acceptance criteria

- `models-apply` (not `models-status`) is the documented command; sourcing the hook defines it.
- No user-facing doc states a hardcoded current tier without pointing at `.privacy-config` as the definition site.
- No *active* reference to branch `feat/quiet-daily-mimo-v26` or pending PR #1 delivery after merge (ODD may note the rename).

## Progress

- 2026-09-23: created after PR #1 merged (`80bad2d`); user approved rename + single-source tier + inconsistency cleanup.
- 2026-09-23: T1–T3 applied — hook + README + QUICK-REFERENCE + SETUP-COMPLETE + ODD docs updated; branch name fixed; OTHER-TERMINAL-PROMPT tier line no longer hardcodes 3.
- 2026-09-23: T4 checks — `bash -n` all scripts exit 0; `jq empty` registry OK; `source session-start-hook.sh` → `models-apply` is a function; no active `models-status` / wrong-branch / "merge PR #1" leftovers outside intentional ODD history notes.
