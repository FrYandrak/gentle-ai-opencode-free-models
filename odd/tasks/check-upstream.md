# Feature: check-upstream (upstream drift detection)

## Objective

Add `check-upstream.sh`: detect each Gentle-AI release/update that could affect this project (agent names, config shape, contracts) and report what needs adapting — before silent breakage.

## Problem / Why

This project hard-depends on Gentle-AI's OpenCode integration surface: agent names (gentle-orchestrator, sdd-*, review-*), opencode.jsonc config shape, and contract versions (review-integration/v2, sdd-integration.consent/v1). Upstream changes can break us silently. Confirmed backlog feature (Engram #159, `feature/upstream-drift-check`); also a good first public issue for Discord contributors.

## Scope

- IN:
  - New `check-upstream.sh` with v1 checks:
    1. Latest upstream release tag (`gh api repos/Gentleman-Programming/gentle-ai/releases/latest`, curl fallback)
    2. Local `gentle-ai --version` vs upstream tag → version-drift headline
    3. Diff surface since local version (`/compare/vX...vY` files filtered by opencode|agent|contract)
    4. Release-notes keyword scan (breaking/opencode/agent)
    5. Offline dependency check: AGENT_NAMES in generate-agent-config.sh vs agents in ~/.config/opencode/opencode.jsonc
    6. Contract version pins vs upstream contracts/ dir
  - Once-per-day stamp `results/.last-upstream-run` + flock (mirror session-start-hook pattern)
  - README `## Scripts` table row (L81-91) + QUICK-REFERENCE `## Core Commands` entry (L5-21)
  - DUPLICATION MARKER comment in script header + feature doc (see below)
- OUT:
  - Extracting a shared lib-common.sh (deferred until a 5th consumer appears)
  - Role-impact reporting via select-role-model helpers (not needed v1)
  - Auto-applying adaptations — v1 only detects and reports
  - Model-quality testing (cancelled permanently)

## Constraints

- English output; artifacts/commits English; no AI attribution.
- Conventions: `#!/bin/bash`, `set -e`, SCRIPT_DIR via BASH_SOURCE, ANSI colors + ✓/⚠/✗, `curl -s --max-time 15`, jq dep check, graceful network degradation (exit 0 on fetch failure with warning).
- gh is NEW for this repo (zero gh usage today): gh-primary with curl fallback, both verified working.
- Cheap checks only: bash -n, jq empty, smokes (AGENTS.md).
- RDD on: assess after work-unit commit(s).
- **DUPLICATION RISK MARKER (record in script header)**: daily-check.sh and session-start-hook.sh keep colors/banner/log/stamp helpers private — no shared shell lib exists. check-upstream.sh v1 duplicates these helpers (colors already triplicated across 3 scripts; this makes 4). If a 5th consumer appears, extract lib-common.sh.

## Tasks

- [ ] T0 Create this feature document (before first source write).
- [ ] T1 Implement check-upstream.sh (checks 1-6, stamp+lock, advisory output).
- [ ] T2 Update README Scripts table + QUICK-REFERENCE Core Commands.
- [ ] T3 Verification: bash -n, network checks live (gh/curl both), stamp behavior, offline check works, greps for stale refs.
- [ ] T4 Work-unit commit(s) + RDD assess.

## Acceptance criteria

- `./check-upstream.sh` reports: latest upstream tag, local version, drift verdict, changed-file surface, advisory scan, offline agent-name check.
- Network failure → warning + exit 0 (graceful).
- Stamp prevents re-run same day (with --force override or similar).
- README + QUICK-REFERENCE document the script.
- bash -n clean; no shared-lib extraction.

## Progress

- 2026-09-24: created after user approved separate-script shape; helper-duplication risk marker recorded per user request.
