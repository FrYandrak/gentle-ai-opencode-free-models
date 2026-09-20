# Feature: Free Model Comparison for Gentle-AI

## Objective
Compare free models available through OpenCode Zen to determine optimal assignments for Gentle-AI SDD phases.

## Problem
Gentle-AI supports model assignments per SDD phase, but choosing the right model for each phase requires understanding model capabilities and limitations.

## Why
- Free models have different strengths (reasoning vs speed vs context)
- Optimal assignment can improve workflow efficiency
- Cost-free solution for personal projects

## Scope
- Compare all 8+ free models available
- Test on representative tasks for each SDD phase
- Create recommended assignment profiles
- Document findings for future reference

## Constraints
- All models must support tool calling
- Tests should be reproducible
- Results should be quantifiable where possible

## Tasks

### Phase 1: Research & Setup
- [x] Task 1.1: Document available free models and their specs
- [x] Task 1.2: Create comparison matrix template
- [ ] Task 1.3: Set up test environment with Gentle-AI

### Phase 2: Baseline Testing
- [ ] Task 2.1: Test code generation capabilities
- [ ] Task 2.2: Test code review capabilities
- [ ] Task 2.3: Test documentation generation
- [ ] Task 2.4: Test complex reasoning tasks

### Phase 3: Analysis & Recommendations
- [ ] Task 3.1: Analyze results and score models
- [ ] Task 3.2: Create recommended role assignments
- [ ] Task 3.3: Create Gentle-AI profile configuration
- [ ] Task 3.4: Document findings and best practices

### Phase 4: Validation
- [ ] Task 4.1: Test recommended configuration
- [ ] Task 4.2: Compare against baseline
- [ ] Task 4.3: Refine recommendations based on results

## Acceptance Criteria
- All free models tested on representative tasks
- Comparison matrix completed with scores
- Recommended profile created and tested
- Documentation complete with clear recommendations

## Verification Evidence
- Test results in results/ directory
- Comparison matrix with scores
- Profile configuration in opencode.json
- Documentation in README.md and COMPARISON-MATRIX.md

## Progress
- [x] Initial research completed
- [x] Comparison matrix created
- [ ] Baseline testing pending
- [ ] Analysis pending

## Next Steps
1. Run baseline tests on each model
2. Fill in comparison matrix
3. Analyze results
4. Create recommended profile
