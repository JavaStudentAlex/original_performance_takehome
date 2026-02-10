---
name: step-md-formatting
description: Defines the canonical STEP.md format for tracking execution of a single work step with status, assignments, cycles, verdicts, and execution artifacts.
---

# STEP.md Formatting Skill

## Overview

This skill standardizes how to create and maintain a `STEP.md` file that tracks the lifecycle of **one concrete step of work** during iterative implementation cycles.

**Purpose**: Provide a single source of truth for the current step's execution state, enabling handoffs, progress tracking, and auditability.

**Output**: A single `STEP.md` file at the repo root containing:
- What step is active and its status
- Who is assigned (implementer and critic)
- Current microtask and definition of done
- Cycle tracking (completed cycles, verdicts)
- Execution artifacts (e.g., patch file path)
- Blockers and notes

---

## When to Use

**Always use** when:
- Starting execution of a planned step (e.g., P01, P02)
- Tracking iterative refinement cycles on a step
- Handing off work mid-step
- Recording verdicts and cycle outcomes

**Read this skill** when:
- Starting any step execution
- Updating step status after a cycle
- Unsure what fields are required
- Recording blockers or completion

---

## Quick Reference

### Pass Criteria

A valid `STEP.md` must:

- Start with `# STEP`
- Use the exact field structure (no missing required fields)
- Have Status as one of `NOT_STARTED`/`IN_PROGRESS`/`DONE`/`BLOCKED`
- Have Latest Verdict as one of `PASS`/`SOFT_FAIL`/`HARD_FAIL`/`N/A`
- Include concrete values or explicit `(none)` / `(missing)` markers
- Track execution artifacts accurately when present (e.g., patch file path)

### Allowed Status Values

| Status | Meaning |
|--------|---------|
| `NOT_STARTED` | Step defined but work has not begun |
| `IN_PROGRESS` | Active work is happening |
| `DONE` | Step completed, all criteria met |
| `BLOCKED` | Cannot proceed without intervention |

### Allowed Verdict Values

| Verdict | Meaning |
|---------|---------|
| `N/A` | No cycles completed yet |
| `PASS` | Last cycle passed all checks |
| `SOFT_FAIL` | Last cycle had minor issues, work can continue |
| `HARD_FAIL` | Last cycle had blocking issues, needs intervention |

---

## STEP.md Format (Canonical)

`STEP.md` MUST follow this exact structure:

```markdown
# STEP

- Status: {NOT_STARTED | IN_PROGRESS | DONE | BLOCKED}
- Active Step ID: <e.g., P01, P02, REPORT>
- Step Title: <short verb phrase describing the step>
- Implementer: <name or identifier>
- Implementer Model: <model name or "(N/A)" for human>
- Critic: <name or identifier>
- Critic Model: <model name or "(N/A)" for human>
- Microtask: <one-paragraph concrete description of current work>
- Definition of Done:
  - <observable completion criterion>
  - <another criterion>
- Cycle Policy:
  - Minimum refinement cycles: <integer, typically 3>
  - Cycles completed: <integer>
- Latest Verdict: {PASS | SOFT_FAIL | HARD_FAIL | N/A}
- Execution Artifacts:
  - Patch file: <path or "(none)">
- Blockers / Notes:
  - <bullet points or "(none)">
```

---

## Field Requirements

### Core Identity Fields

| Field | Required | Description |
|-------|----------|-------------|
| Status | Yes | Current execution state |
| Active Step ID | Yes | Unique identifier (P01, P02, etc.) |
| Step Title | Yes | Short verb phrase from plan |

### Assignment Fields

| Field | Required | Description |
|-------|----------|-------------|
| Implementer | Yes | Who performs the work |
| Implementer Model | Yes | Model used, or `(N/A)` for human |
| Critic | Yes | Who reviews the work |
| Critic Model | Yes | Model used, or `(N/A)` for human |

### Work Definition Fields

| Field | Required | Description |
|-------|----------|-------------|
| Microtask | Yes | Concrete description of current work unit |
| Definition of Done | Yes | Observable, testable completion criteria |

### Cycle Tracking Fields

| Field | Required | Description |
|-------|----------|-------------|
| Minimum refinement cycles | Yes | How many cycles required before completion |
| Cycles completed | Yes | Integer count of finished cycles |
| Latest Verdict | Yes | Outcome of most recent cycle |

### Execution Artifacts Fields

| Field | Required | Description |
|-------|----------|-------------|
| Patch file | Yes | Path to the generated patch file for the latest cycle, or `(none)` |

### Notes Fields

| Field | Required | Description |
|-------|----------|-------------|
| Blockers / Notes | Yes | Current blockers or relevant notes |

---

## Update Procedure

### 1) Initialize for a New Step

When starting a new step:

1. Set `Status: NOT_STARTED`
2. Set `Active Step ID` to the step identifier (e.g., P01)
3. Copy `Step Title` from the plan
4. Set `Implementer` and `Critic` assignments
5. Set corresponding model fields
6. Write the `Microtask` as a concrete description
7. Copy `Definition of Done` criteria from the plan
8. Set `Minimum refinement cycles` (typically 3)
9. Set `Cycles completed: 0`
10. Set `Latest Verdict: N/A`
11. Set `Patch file: (none)`
12. Set `Blockers / Notes: (none)`

### 2) Start Work on a Step

When beginning active work:

1. Set `Status: IN_PROGRESS`

### 3) After Each Cycle

When a cycle completes:

1. Increment `Cycles completed`
2. Update `Latest Verdict` based on outcome
3. Update `Patch file` if a patch was generated for the cycle
4. Add any blockers or notes discovered

### 4) Mark Step as Blocked

When work cannot proceed:

1. Set `Status: BLOCKED`
2. Document specific blockers in `Blockers / Notes`

### 5) Complete the Step

A step may only be marked DONE when ALL of these are true:

- Cycles completed >= Minimum refinement cycles
- Latest Verdict is `PASS`
- All Definition of Done criteria are satisfied
- All quality gates have passed

When marking complete:

1. Set `Status: DONE`
2. Add completion notes if relevant

---

## Section Rules

| Section | Must Include | Must Avoid |
|---------|--------------|------------|
| Status | Exactly one allowed value | Invented status values |
| Active Step ID | Consistent identifier format | Changing ID mid-step |
| Microtask | Concrete, actionable description | Vague "do the thing" |
| Definition of Done | Observable, testable criteria | Subjective criteria |
| Cycle Policy | Numeric values | Non-numeric entries |
| Latest Verdict | Exactly one allowed value | Invented verdict values |
| Execution Artifacts | Patch file path or `(none)` | Invented paths |
| Blockers / Notes | Specific blockers or `(none)` | Empty field |

---

## Common Pitfalls

| Pitfall | Problem | Fix |
|---------|---------|-----|
| Vague microtask | Unclear what work to do | Write concrete, actionable description |
| Subjective DoD | Cannot verify completion | Use observable, testable criteria |
| Forgetting to increment cycles | Inaccurate progress tracking | Update after every cycle |
| Wrong verdict value | Invalid state | Use only allowed enumerated values |
| Missing patch file field | No audit trail for cycle output | Always include `Patch file` (use `(none)` if not produced) |
| Empty blockers when blocked | No path to unblock | Document specific blockers |

---

## Validation Checklist

Before treating `STEP.md` as valid, verify:

- [ ] Starts with `# STEP`
- [ ] Status is one of: NOT_STARTED, IN_PROGRESS, DONE, BLOCKED
- [ ] Active Step ID is present and consistent
- [ ] Step Title is a short verb phrase
- [ ] Implementer and Critic are specified
- [ ] Implementer Model and Critic Model are specified
- [ ] Microtask is concrete and actionable
- [ ] Definition of Done has observable criteria
- [ ] Minimum refinement cycles is a positive integer
- [ ] Cycles completed is a non-negative integer
- [ ] Latest Verdict is one of: PASS, SOFT_FAIL, HARD_FAIL, N/A
- [ ] `Patch file` is present with a real path or `(none)`
- [ ] Blockers / Notes is populated or explicitly `(none)`

---

## Examples

### Minimal Example (Not Started)

```markdown
# STEP

- Status: NOT_STARTED
- Active Step ID: P01
- Step Title: Add unit tests for parser module
- Implementer: test-expert
- Implementer Model: gpt-5.2-codex
- Critic: test-critic
- Critic Model: claude-sonnet-4.5
- Microtask: Create deterministic unit tests covering parse_input() and validate_schema() functions with edge cases for empty, malformed, and valid inputs.
- Definition of Done:
  - `python -m pytest tests/test_parser.py` passes
  - Tests cover: valid input, invalid input, empty input, malformed input
  - Tests are deterministic (no network, no randomness)
  - Coverage for parser module >= 80%
- Cycle Policy:
  - Minimum refinement cycles: 3
  - Cycles completed: 0
- Latest Verdict: N/A
- Execution Artifacts:
  - Patch file: (none)
- Blockers / Notes:
  - (none)
```

### In Progress Example

```markdown
# STEP

- Status: IN_PROGRESS
- Active Step ID: P02
- Step Title: Implement streaming batch iterator
- Implementer: ml-expert
- Implementer Model: gpt-5.2-codex
- Critic: ml-critic
- Critic Model: claude-sonnet-4.5
- Microtask: Refactor BatchLoader.load() to return a generator that yields chunks instead of loading the entire batch into memory at once.
- Definition of Done:
  - load() returns a generator instead of a list
  - Memory usage is O(batch_size), not O(dataset_size)
  - `pyright src/data/loader.py` has no errors
  - Existing tests continue to pass
- Cycle Policy:
  - Minimum refinement cycles: 3
  - Cycles completed: 1
- Latest Verdict: SOFT_FAIL
- Execution Artifacts:
  - Patch file: .github/agent-state/patches/2025-01-01T10-00-00Z-ml-expert.patch
- Blockers / Notes:
  - Cycle 1: Type hints incomplete, critic flagged missing return type annotation
  - Addressing in cycle 2
```

### Blocked Example

```markdown
# STEP

- Status: BLOCKED
- Active Step ID: P03
- Step Title: Integrate cache layer into API endpoint
- Implementer: ml-expert
- Implementer Model: gpt-5.2-codex
- Critic: ml-critic
- Critic Model: claude-sonnet-4.5
- Microtask: Add CacheManager integration to predict_endpoint() for response caching.
- Definition of Done:
  - predict_endpoint() uses CacheManager for repeated queries
  - Cache hit rate logged for monitoring
  - Response time < 100ms for cached queries
  - All existing API tests pass
- Cycle Policy:
  - Minimum refinement cycles: 3
  - Cycles completed: 2
- Latest Verdict: HARD_FAIL
- Execution Artifacts:
  - Patch file: .github/agent-state/patches/2025-01-01T10-00-00Z-ml-expert.patch
- Blockers / Notes:
  - CacheManager dependency not installed in test environment
  - Redis connection configuration missing from CI
  - Need infrastructure update before proceeding
```

### Completed Example

```markdown
# STEP

- Status: DONE
- Active Step ID: P01
- Step Title: Add unit tests for parser module
- Implementer: test-expert
- Implementer Model: gpt-5.2-codex
- Critic: test-critic
- Critic Model: claude-sonnet-4.5
- Microtask: Create deterministic unit tests covering parse_input() and validate_schema() functions with edge cases for empty, malformed, and valid inputs.
- Definition of Done:
  - `python -m pytest tests/test_parser.py` passes
  - Tests cover: valid input, invalid input, empty input, malformed input
  - Tests are deterministic (no network, no randomness)
  - Coverage for parser module >= 80%
- Cycle Policy:
  - Minimum refinement cycles: 3
  - Cycles completed: 3
- Latest Verdict: PASS
- Execution Artifacts:
  - Patch file: (none)
- Blockers / Notes:
  - Completed in 3 cycles
  - Coverage achieved: 87%
  - All 12 test cases passing
```

### Example With Human Assignment

```markdown
# STEP

- Status: IN_PROGRESS
- Active Step ID: P05
- Step Title: Review and approve API design
- Implementer: human
- Implementer Model: (N/A)
- Critic: docs-critic
- Critic Model: claude-sonnet-4.5
- Microtask: Human reviews proposed API design document and provides approval or feedback.
- Definition of Done:
  - Human has reviewed API design document
  - Approval recorded or feedback documented
  - Any required changes identified
- Cycle Policy:
  - Minimum refinement cycles: 1
  - Cycles completed: 0
- Latest Verdict: N/A
- Execution Artifacts:
  - Patch file: (none)
- Blockers / Notes:
  - Awaiting human review
  - Design document at: docs/api-design-v2.md
```

---

## Lifecycle State Diagram

```
                    +---------------+
                    | NOT_STARTED   |
                    +-------+-------+
                            |
                            | Start work
                            v
                    +-------+-------+
            +------>| IN_PROGRESS   |<------+
            |       +-------+-------+       |
            |               |               |
            | Resume        | Cycle         | Cycle
            | (unblock)     | completes     | completes
            |               |               | (continue)
            |               v               |
            |       +-------+-------+       |
            |       | Check verdict |-------+
            |       +-------+-------+
            |               |
            |               | HARD_FAIL
            |               v
            |       +-------+-------+
            +-------+   BLOCKED     |
                    +---------------+

                    +---------------+
                    | IN_PROGRESS   |
                    +-------+-------+
                            |
                            | All criteria met:
                            | - cycles >= minimum
                            | - verdict = PASS
                            | - DoD satisfied
                            v
                    +-------+-------+
                    |     DONE      |
                    +---------------+
```

---

## Summary

**Key Takeaways:**

1. **STEP.md tracks one step at a time** - it is the single source of truth for current execution state
2. **All fields are required** - use `(none)` or `N/A` for empty values, never omit fields
3. **Status and Verdict have fixed values** - only use the allowed enumerated values
4. **Update after every cycle** - increment cycles, update verdict, and capture artifacts
5. **Completion has strict criteria** - minimum cycles, passing verdict, and DoD all required

**The Golden Rule**: STEP.md should always reflect the actual current state. When in doubt, update it. Anyone reading STEP.md should know exactly where the step stands and what happens next.
