---
name: plan-md-formatting
description: Defines the canonical PLAN.md format and step schema for converting TASK.md + CONTEXT.md into an implementation-ready, reviewable plan.
---

# PLAN.md Formatting Skill

## Overview

This skill standardizes how to write `PLAN.md` so that downstream agents can implement and critique work step-by-step with minimal ambiguity.

**Purpose**: Convert intent (`TASK.md`) + evidence (`CONTEXT.md`) into a sequence of actionable steps with explicit ownership and verifiable completion criteria.

**Output**: A single `PLAN.md` file in the repo root using the canonical structure and step schema defined below.

---

## When to Use

**Always use** when:
- You have a refined `TASK.md` and (optionally) `CONTEXT.md` and need to produce the implementation plan
- You are splitting work into steps across specialized agents (implementers/critics)
- You want consistent plan quality and predictable handoff

**Read this skill** when:
- Starting any planning task
- Unsure what fields a step requires
- Need to structure a plan for parallel execution

---

## Quick Reference

### Pass Criteria

A valid `PLAN.md` must:

- Start with `# PLAN`
- Include a plan-level summary section
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
- Contain no code blocks (inline code for commands is acceptable)
- Mark unknowns explicitly as `(missing)` or `(to be confirmed)`
- Be concise: typically 3-8 steps

---

## PLAN.md Format (Canonical)

`PLAN.md` MUST follow this structure:

```markdown
# PLAN

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

<!-- repeat as needed -->
```

---

## Section Requirements

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

**Too coarse**: "Refactor the entire data pipeline"
**Too fine**: "Add import statement to file X"
**Right size**: "Add batch processing to DataLoader with streaming iteration"

### Scope Guidelines

Scope must be concrete. Use exact paths and symbols:

**Good scope**:
```
- `src/data/loader.py` :: `BatchLoader.load()`
- `src/data/transforms.py` :: `apply_transforms()`
- `tests/test_loader.py` (new file)
```

**Bad scope**:
```
- The data loading code
- Related test files
- Some utility functions
```

### DoD Guidelines

Definition of Done must be observable and testable:

**Good DoD**:
```
- `python -m pytest tests/test_loader.py` passes
- `BatchLoader.load()` yields chunks of size <= batch_size
- No type errors from `pyright src/data/`
- Memory usage stays under 1GB for batch_size=10000
```

**Bad DoD**:
```
- Code is clean
- Tests are comprehensive
- Performance is improved
```

---

## Parallel Execution Design

Design plans so steps can run in parallel when feasible:

### Independent Tracks

Group steps that don't share file ownership:

```markdown
### P01 - Add unit tests for parser
- **Scope**: `tests/test_parser.py` (new)
- ...

### P02 - Add integration tests for API
- **Scope**: `tests/test_api.py` (new)
- ...
```

P01 and P02 can run in parallel since they touch different files.

### Explicit Dependencies

When steps must be sequential, note the dependency:

```markdown
### P02 - Implement caching layer
- **Scope**: `src/cache.py` (new)
- **DoD**:
  - Cache module exists and exports `CacheManager`
  - ...

### P03 - Integrate cache into API (depends on P02)
- **Scope**: `src/api/routes.py` :: `predict_endpoint()`
- **DoD**:
  - `predict_endpoint()` uses `CacheManager`
  - ...
```

---

## Style Constraints

- **No code blocks**: Plans describe what to do, not how to implement it. Use inline code for commands (e.g., `pytest tests/`) but not implementation code.
- **Prefer file-path and symbol references**: Be specific about location.
- **Keep steps concise**: Avoid lengthy prose; use bullets.
- **Mark unknowns**: Use `(missing)` or `(to be confirmed)` rather than guessing.

---

## Common Pitfalls

| Pitfall | Problem | Fix |
|---------|---------|-----|
| Vague scope | "The models module" without paths | Include exact paths and symbols |
| Subjective DoD | "Code quality improves" | Add measurable checks |
| Missing model fields | Implementer Model or Critic Model omitted | Always include both model fields |
| Implementation in plan | Code snippets in steps | Remove code; describe intent only |
| Overly long plans | 15+ steps that overwhelm | Consolidate into 3-8 focused steps |
| Hidden dependencies | Steps assume prior work without noting it | Add "(depends on Pxx)" explicitly |
| Same implementer/critic | Implementer reviews own work | Use different agents for critique |
| Invented scope | Guessing file paths that don't exist | Verify paths or mark `(to be confirmed)` |

---

## Validation Checklist

Before treating `PLAN.md` as complete, verify:

- [ ] Starts with `# PLAN`
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
- [ ] Parallel execution is possible where steps don't share scope

---

## Examples

### Minimal Example

```markdown
# PLAN

## Summary
- **Objective**: Add deterministic unit tests for the parsing module
- **Non-goals**: Refactoring parser implementation; adding integration tests
- **Assumptions**: (none)
- **Risks**: Flaky tests if file I/O is involved
- **Quality Gates**: pytest passes, coverage does not decrease

## Steps

### P01 - Add unit tests for core parsing functions
- **Implementer**: test-expert
- **Implementer Model**: gpt-5.2-codex
- **Critic**: test-critic
- **Critic Model**: claude-sonnet-4.5
- **Scope**:
  - `tests/test_parser.py` (new file)
  - `src/parser.py` :: `parse_input()`, `validate_schema()`
- **DoD**:
  - `python -m pytest tests/test_parser.py` passes
  - Tests cover: valid input, invalid input, edge cases (empty, malformed)
  - Tests are deterministic (no network, no randomness)
  - Coverage for `src/parser.py` >= 80%
```

### Multi-Step Example

```markdown
# PLAN

## Summary
- **Objective**: Implement batch processing for DataLoader to reduce memory usage
- **Non-goals**: Changing data format; modifying model architecture
- **Assumptions**: Current memory issue is caused by eager loading (per CONTEXT.md)
- **Risks**: Breaking backward compatibility; performance regression on small batches
- **Quality Gates**: pytest passes, type checks pass, memory benchmark shows improvement

## Steps

### P01 - Implement streaming batch iterator
- **Implementer**: ml-expert
- **Implementer Model**: gpt-5.2-codex
- **Critic**: ml-critic
- **Critic Model**: claude-sonnet-4.5
- **Scope**:
  - `src/data/loader.py` :: `BatchLoader.load()`, `BatchLoader.__iter__()`
- **DoD**:
  - `load()` returns a generator instead of a list
  - Memory usage is O(batch_size), not O(dataset_size)
  - `pyright src/data/loader.py` has no errors

### P02 - Add backward-compatible wrapper
- **Implementer**: ml-expert
- **Implementer Model**: gpt-5.2-codex
- **Critic**: ml-critic
- **Critic Model**: claude-sonnet-4.5
- **Scope**:
  - `src/data/loader.py` :: `BatchLoader.load_all()` (new method)
- **DoD**:
  - `load_all()` returns `List[Tensor]` for backward compatibility
  - Existing callers using list interface continue to work
  - Deprecation warning logged when `load_all()` is called

### P03 - Add tests for batch processing (parallel with P01/P02)
- **Implementer**: test-expert
- **Implementer Model**: gpt-5.2-codex
- **Critic**: test-critic
- **Critic Model**: claude-sonnet-4.5
- **Scope**:
  - `tests/test_loader.py` :: `test_streaming_load()`, `test_memory_bounded()` (new)
- **DoD**:
  - `python -m pytest tests/test_loader.py` passes
  - Tests verify streaming behavior with batch_size=1, 100, 10000
  - Tests verify memory stays bounded (mock or measure)

### P04 - Update documentation (depends on P01, P02)
- **Implementer**: docs-expert
- **Implementer Model**: gpt-5.2
- **Critic**: docs-critic
- **Critic Model**: claude-sonnet-4.5
- **Scope**:
  - `docs/data_loading.md`
  - `src/data/loader.py` (docstrings only)
- **DoD**:
  - `docs/data_loading.md` documents new streaming API
  - Migration guide from `load_all()` to `load()` included
  - All public methods have updated docstrings
```

### Example With Unknowns

```markdown
# PLAN

## Summary
- **Objective**: Diagnose and fix slow API response times
- **Non-goals**: Full performance optimization; infrastructure changes
- **Assumptions**: Issue is in application code, not network/infra (to be confirmed)
- **Risks**: Root cause may require infrastructure changes (out of scope)
- **Quality Gates**: Response time < 500ms for standard queries

## Steps

### P01 - Add profiling instrumentation
- **Implementer**: ml-expert
- **Implementer Model**: gpt-5.2-codex
- **Critic**: ml-critic
- **Critic Model**: claude-sonnet-4.5
- **Scope**:
  - `src/api/routes.py` :: `predict_endpoint()`
  - `src/api/middleware.py` (to be confirmed - may not exist)
- **DoD**:
  - Timing logs added for: request parsing, model inference, response serialization
  - Logs include timestamps with millisecond precision
  - No functional changes to endpoint behavior

### P02 - Identify bottleneck from profiling data (depends on P01)
- **Implementer**: human
- **Implementer Model**: (N/A)
- **Critic**: ml-critic
- **Critic Model**: claude-sonnet-4.5
- **Scope**:
  - Analysis of profiling logs (to be confirmed)
- **DoD**:
  - Bottleneck identified with evidence (log data)
  - Root cause hypothesis documented
  - Fix approach proposed for P03

### P03 - Implement fix for identified bottleneck (depends on P02)
- **Implementer**: (to be confirmed after P02)
- **Implementer Model**: (to be confirmed)
- **Critic**: (to be confirmed)
- **Critic Model**: (to be confirmed)
- **Scope**:
  - (to be confirmed after P02)
- **DoD**:
  - Response time < 500ms for standard queries
  - No regression in functionality
  - `python -m pytest tests/` passes
```

---

## Summary

**Key Takeaways:**

1. **PLAN.md converts intent into actionable steps** - each step has explicit ownership and verifiable completion criteria
2. **Every step requires all fields** - ID, Title, Implementer, Implementer Model, Critic, Critic Model, Scope, DoD
3. **Scope must be concrete** - exact paths and symbols, not vague descriptions
4. **DoD must be observable** - tests, commands, measurements that prove completion
5. **Design for parallel execution** - independent steps can run concurrently
6. **Mark unknowns explicitly** - use `(to be confirmed)` or `(missing)`, never guess

**The Golden Rule**: A good plan enables any qualified agent to execute a step without needing additional context beyond what's in TASK.md, CONTEXT.md, and the step definition itself.
