# Feature: Free Model Comparison for Gentle-AI

## Status: CANCELLED (2026-09-23)

Model-testing work is cancelled by user decision: free-tier tokens are limited and must not be spent evaluating models on synthetic tasks. This includes baseline tests, comparison-matrix scoring, and any `test-models` harness.

## Historical objective (for context only)

Compare free models available through OpenCode Zen to determine optimal assignments for Gentle-AI SDD phases.

## What remains in scope (non-testing)

- Registry-driven, model-agnostic role selection (see `odd/tasks/model-agnostic-selection.md` — done).
- Quiet daily hook + on-demand `models-apply` (see `odd/tasks/quiet-daily-and-mimo-v26.md` — done; command later renamed from `models-status`).
- Passive catalog/privacy notes in `privacy-tier-registry.json`.

## What was removed

- Phases 2–4 (baseline testing, analysis scoring, validation) — cancelled.
- `COMPARISON-MATRIX.md` scoring template — removed.
- `test-models.sh` — never executed as a real harness; references removed.

## Decision record

- 2026-09-23: user cancelled model testing to preserve free-token budget. Engram: decision “Cancelled model testing — free token budget”.
