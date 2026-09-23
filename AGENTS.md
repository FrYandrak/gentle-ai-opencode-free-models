# Agent Configuration for Free Model Comparison Project

## Project Goals

This project compares free models available through OpenCode Zen for use with Gentle-AI workflows. The goal is to determine optimal model assignments for different SDD (Spec-Driven Development) phases.

## Coding Standards

### Documentation
- Use Markdown for all documentation
- Include code examples where applicable
- Follow consistent formatting patterns

### Verification (no model-testing harness)

- Prefer cheap local checks (`bash -n`, `jq empty`, smoke runs) over free-token model evaluation.
- Model-testing / comparison-matrix scoring is cancelled (free-token budget policy).

## Gentle-AI Integration

This project uses:
- **ODD workflow** for organic feature delivery
- **Registry-driven role selection** (model-agnostic)
- **Engram** for persistent memory across sessions

## Communication Style

- Be direct and technical
- Include specific examples
- Reference source documentation
- Provide actionable recommendations
