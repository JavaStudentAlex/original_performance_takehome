---
name: plan-md-formatting
description: Defines the canonical PLAN.md format and step schema for converting TASK.md plus planner-led research into an implementation-ready, reviewable plan.
---

# PLAN.md Formatting Skill

## Overview

This skill standardizes how to write `PLAN.md` so downstream agents can implement and critique work step-by-step with minimal ambiguity.

**Purpose**: Convert intent (`TASK.md`) + planner investigation evidence into a sequence of actionable steps with explicit ownership and verifiable completion criteria.

**Output**: A single `PLAN.md` file in the repo root using the canonical structure and step schema defined below.

---

## When to Use

**Always use** when:
- You have a refined `TASK.md` and need to produce the implementation plan
- You are splitting work into steps across specialized agents (implementers/critics)
- You need the plan to be self-contained (no separate context artifact)

**Read this skill** when:
- Starting any planning task
- Unsure what fields a step requires
- Need to structure a plan for parallel execution

---

## Quick Reference

### Pass Criteria

A valid `PLAN.md` must:

- Start with `# PLAN`
- Include a `Research Evidence` section
- Include a `Summary` section
- Contain at least one step (`P01`)
- For **every** step, include *all* required fields:
  - `ID` (P01, P02, ...)
  - `Title` (short verb phrase)
  - `Implementer` (agent or human)
  - `Implementer Model` (exact model name)
  - `Critic` (agent or human)
  - `Critic Model` (exact model name)
  - `Scope` (concrete paths/symbols)
  - `DoD` (observable completion checks)
- Use monotonically increasing step IDs: `P01`, `P02`, `P03`, ...
- Keep scope concrete (paths/symbols); no vague "some module"
- Contain no code blocks
- Mark unknowns explicitly as `(missing)` or `(to be confirmed)`
- Be concise: typically 3-8 steps

---

## PLAN.md Format (Canonical)

`PLAN.md` MUST follow this structure:

```markdown
# PLAN

## Research Evidence
- **Investigation scope**: <what areas were inspected>
- **What was inspected**:
  - <files/symbols/logs/issues reviewed>
- **Key factual observations**:
  - <fact 1>
  - <fact 2>
- **Unknowns / open questions**:
  - <unknown 1> (or `(none)`)
- **Constraints discovered**:
  - <constraint 1> (or `(none identified)`)

## Summary
- **Objective**: <one sentence, aligned with TASK.md>
- **Non-goals**: <explicitly state what is out of scope>
- **Assumptions**: <any assumptions; otherwise (none)>
- **Risks**: <key risks; otherwise (none)>
- **Quality Gates**: <which gates must pass; e.g., lint, tests, docs, coverage>

## Steps

### P01 - <short verb phrase>
- **Implementer**: <agent-name or human>
- **Implementer Model**: <exact model name>
- **Critic**: <agent-name or human>
- **Critic Model**: <exact model name>
- **Scope**:
  - <file paths and/or symbols this step may change>
  - If unknown: (to be confirmed)
- **DoD**:
  - <observable completion check>
  - <how to validate: tests, lint, docs>

### P02 - <short verb phrase>
- **Implementer**: ...
- **Implementer Model**: ...
- **Critic**: ...
- **Critic Model**: ...
- **Scope**: ...
- **DoD**: ...
```

---

## Section Requirements

### Research Evidence Section

| Field | Must Include | Must Avoid |
|-------|--------------|------------|
| Investigation scope | Clear boundary of what was reviewed | Generic "looked at code" |
| What was inspected | Concrete paths/symbols/logs/issues | Vague references |
| Key factual observations | Verifiable facts only | Speculation as fact |
| Unknowns / open questions | Explicit unresolved items | Hidden assumptions |
| Constraints discovered | Limits that affect execution | Unjustified claims |

### Summary Section

| Field | Must Include | Must Avoid |
|-------|--------------|------------|
| Objective | One sentence aligned with TASK.md | Restating the entire task |
| Non-goals | What is explicitly out of scope | Vague exclusions |
| Assumptions | Stated assumptions that affect the plan | Hidden assumptions |
| Risks | Key risks to plan success | Speculation without basis |
| Quality Gates | Specific gates that must pass | Generic "quality checks" |

### Step Fields

| Field | Must Include | Must Avoid |
|-------|--------------|------------|
| ID | Sequential: P01, P02, P03... | Gaps or reordering |
| Title | Short verb phrase describing the action | Long descriptions |
| Implementer | Specific agent name or "human" | Vague "someone" |
| Implementer Model | Exact model name | Generic "best model" |
| Critic | Specific agent name or "human" | Same as implementer (unless justified) |
| Critic Model | Exact model name | Generic "any model" |
| Scope | Concrete paths and symbols | Vague "the models module" |
| DoD | Observable, testable criteria | Subjective "looks good" |

---

## Writing Effective Steps

### Step Granularity

Each step should be:
- **Atomic**: One logical unit of work
- **Independent**: Minimal dependencies on other steps when possible
- **Verifiable**: DoD can be checked objectively

### Scope Guidelines

Scope must be concrete. Use exact paths and symbols:
- Good: `src/data/loader.py` :: `BatchLoader.load()`
- Bad: "The data loading code"

### DoD Guidelines

Definition of Done must be observable and testable:
- Good: `pytest tests/submission_tests.py::CorrectnessTests -v` passes
- Bad: "Performance is improved"

---

## Parallel Execution Design

Design plans so steps can run in parallel when feasible:
- Group steps touching disjoint files/symbols.
- State dependencies explicitly when sequencing is required.
- Keep shared-state changes in dependency-ordered steps.

---

## Style Constraints

- **No code blocks** inside `PLAN.md`
- **Prefer file-path and symbol references**
- **Keep steps concise**
- **Mark unknowns** with `(missing)` or `(to be confirmed)`

---

## Common Pitfalls

| Pitfall | Problem | Fix |
|---------|---------|-----|
| Missing research evidence | Downstream agents lack grounding | Include all required research evidence fields |
| Vague scope | Ambiguous execution ownership | Include exact paths and symbols |
| Subjective DoD | Cannot verify completion | Add measurable checks |
| Hidden dependencies | Rework during implementation | Add explicit depends-on notes |
| Invented scope | Plan targets non-existent files | Verify paths or mark `(to be confirmed)` |

---

## Validation Checklist

Before treating `PLAN.md` as complete, verify:

- [ ] Starts with `# PLAN`
- [ ] Includes `Research Evidence` with inspected areas, facts, unknowns, constraints
- [ ] Summary section includes Objective, Non-goals, Assumptions, Risks, Quality Gates
- [ ] Objective aligns with TASK.md
- [ ] Contains at least one step (P01)
- [ ] Step IDs are sequential (P01, P02, P03...)
- [ ] Every step has all required fields: ID, Title, Implementer, Implementer Model, Critic, Critic Model, Scope, DoD
- [ ] Scope contains concrete paths/symbols (not vague descriptions)
- [ ] DoD contains observable, testable criteria
- [ ] No code blocks in the plan
- [ ] Unknowns marked as `(missing)` or `(to be confirmed)`
- [ ] Plan is concise (typically 3-8 steps)

---

## Minimal Example

```markdown
# PLAN

## Research Evidence
- **Investigation scope**: parser module and existing parser tests
- **What was inspected**:
  - `src/parser.py` :: `parse_input()`, `validate_schema()`
  - `tests/test_parser.py`
- **Key factual observations**:
  - `parse_input()` accepts malformed empty payloads without raising
  - Existing tests cover valid input but not malformed input paths
- **Unknowns / open questions**:
  - Whether strict-schema mode is required in all callers (to be confirmed)
- **Constraints discovered**:
  - Public parser function signatures must remain unchanged

## Summary
- **Objective**: Add deterministic parser coverage for malformed input handling
- **Non-goals**: Parser refactor, integration test expansion
- **Assumptions**: Existing parser API remains stable
- **Risks**: Over-constraining parser behavior for legacy callers
- **Quality Gates**: parser tests pass; no lint/type regressions in touched scope

## Steps
### P01 - Add malformed-input parser tests
- **Implementer**: test-expert
- **Implementer Model**: gpt-5.2-codex
- **Critic**: test-critic
- **Critic Model**: claude-sonnet-4.5
- **Scope**:
  - `tests/test_parser.py`
- **DoD**:
  - `python -m pytest tests/test_parser.py` passes
  - Malformed empty payload and malformed schema cases are asserted
```

---

## Summary

**The Golden Rule**: A good plan is self-contained. Any qualified agent should be able to execute using only `TASK.md`, `PLAN.md`, and the step definitions.
