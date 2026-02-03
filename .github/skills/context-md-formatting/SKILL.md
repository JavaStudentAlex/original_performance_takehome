---
name: context-md-formatting
description: Defines the canonical CONTEXT.md format and procedure for gathering comprehensive investigation context. Use when analyzing problems, exploring codebases, or preparing context for downstream work.
---

# Context Gathering Skill

## Overview

This skill standardizes how to gather and document investigation context in `CONTEXT.md`. The goal is to produce structured, evidence-based findings that downstream consumers can trust.

**Purpose**: Transform raw investigation into actionable context through systematic exploration and structured documentation.

**Output**: A single `CONTEXT.md` file containing problem analysis, affected code areas, behavioral gaps, hypotheses, and unknowns.

---

## When to Use

**Always use** when:
- Investigating a bug, issue, or unexpected behavior
- Exploring unfamiliar code before making changes
- Preparing context for planning or implementation work
- Documenting findings from codebase analysis

**Read this skill** when:
- Starting any investigation task
- Unsure what information to gather
- Need to structure findings for handoff

---

## Quick Reference

### Pass Criteria

A valid `CONTEXT.md` must:

- Contain all required sections (see format below)
- Distinguish facts from hypotheses clearly
- Have unambiguous "Current vs Expected Behavior"
- Include at least one concrete file/symbol in affected areas (or explicit `(missing)`)
- List ranked, testable hypotheses
- Document unknowns explicitly
- Contain no speculative statements outside the Hypotheses section

---

## CONTEXT.md Format (Canonical)

```markdown
# CONTEXT

## Problem Statement
- **Goal**: (what we are trying to achieve or understand)
- **User-visible symptom**: (what the user or system observes)
- **Severity/impact**: (who/what is affected, how severely)
- **Scope**: (what is in-scope / out-of-scope for this investigation)

## Investigation Summary
- **What was inspected**:
  - (logs / code / tests / configs / docs / external sources)
- **Key observations (facts)**:
  - (fact 1)
  - (fact 2)
- **Confidence**: (low/medium/high) + one sentence explaining why
- **Depth**: (quick scan / partial deep dive / exhaustive)

## Current vs Expected Behavior
- **Current behavior**:
  - (what actually happens, include exact errors/messages if available)
- **Expected behavior**:
  - (what should happen, acceptance criteria if known)

## Affected Code Areas
- **Primary** (most likely relevant):
  - `path/to/file.py` :: `SymbolName` - (why it's implicated)
- **Dependencies** (used by primary areas):
  - `path/to/dep.py` - (why relevant)
- **Dependents** (callers/consumers that might be affected):
  - `path/to/caller.py` - (why relevant)

## Contracts and Invariants
- **Explicit contracts** (types, interfaces, schemas, API expectations):
  - (contract description)
- **Implicit invariants** (assumptions that must remain true):
  - (invariant description)

## Test Coverage
- **Existing relevant tests**:
  - `tests/...` - (what they cover)
- **Failing tests**:
  - `tests/...` - (failure summary)
- **Coverage gaps**:
  - (what should be tested but isn't)

## External Context (if applicable)
- **APIs/services**:
  - (service name, endpoints, auth assumptions)
- **Data formats**:
  - (schemas, example payloads)
- **Environment**:
  - OS: (value or `(missing)`)
  - Runtime: (value or `(missing)`)
  - CI: (value or `(missing)`)

## Root Cause Hypotheses (ranked)
1. **Hypothesis**: (short statement)
   - **Why plausible**: (supporting evidence)
   - **How to confirm**: (specific check or experiment)
   - **How to refute**: (what would disprove it)
2. **Hypothesis**: ...

## Unknowns and Risks
- **Unknowns**:
  - (questions that block certainty)
- **Risks**:
  - (what could go wrong, regressions, rollout concerns)

## Constraints Discovered
- (technical limitations, compatibility requirements, performance bounds)
- (policy constraints, deadlines, external dependencies)
- If none: `(none identified)`
```

---

## Gathering Procedure

### Phase 1: Understand the Problem

1. **Capture the symptom** - What is actually observed? Get exact error messages, logs, or behavioral descriptions.
2. **Define the goal** - What should happen instead? What does success look like?
3. **Scope the investigation** - What's in bounds? What's explicitly out of scope?

### Phase 2: Explore the Codebase

1. **Map the structure** - Identify relevant directories, modules, and entry points.
2. **Identify affected files** - Find files directly related to the problem area.
3. **Trace dependencies** - Follow imports and calls to understand data flow.
4. **Extract contracts** - Document types, interfaces, expected shapes, and invariants.
5. **Review tests** - Check existing test coverage for the affected area.

### Phase 3: Gather External Context (if applicable)

1. **Check issue trackers** - Look for related open/closed issues with similar symptoms.
2. **Review change history** - Examine recent commits or PRs that touched affected files.
3. **Mine discussions** - Extract context from comments, reviews, or documentation.
4. **Check external docs** - Review API docs, dependency documentation, or specs.

### Phase 4: Synthesize Findings

1. **Separate facts from hypotheses** - Facts are observed; hypotheses are inferred.
2. **Rank hypotheses** - Order by likelihood and ease of testing.
3. **Document unknowns** - What couldn't be determined? What needs more investigation?
4. **Identify constraints** - What limitations affect potential solutions?

---

## Section Requirements

| Section | Must Include | Must Avoid |
|---------|--------------|------------|
| Problem Statement | Concrete symptom, clear goal, defined scope | Vague descriptions, solution proposals |
| Investigation Summary | What was actually inspected, confidence level | Assumptions about uninspected areas |
| Current vs Expected | Exact behaviors with evidence | Mixing the two, ambiguous language |
| Affected Code Areas | Concrete paths and symbols | Generic descriptions without paths |
| Contracts/Invariants | Explicit types, documented interfaces | Guessed contracts without evidence |
| Test Coverage | Existing tests and gaps | Speculation about untested behavior |
| Hypotheses | Ranked, testable, with evidence | Unsupported speculation, certainty |
| Unknowns/Risks | Explicit questions and concerns | Hidden assumptions |

---

## Quality Checklist

Before treating `CONTEXT.md` as complete, verify:

- [ ] All required sections are present
- [ ] Problem Statement has concrete symptom and clear goal
- [ ] Current vs Expected Behavior is unambiguous
- [ ] Affected Code Areas includes at least one concrete file/symbol
- [ ] Hypotheses are ranked and include confirmation/refutation methods
- [ ] Each hypothesis cites supporting evidence
- [ ] Unknowns are explicitly documented (not hidden)
- [ ] No speculative statements outside Hypotheses section
- [ ] Missing information is marked as `(missing)` not invented
- [ ] Confidence level is stated with justification

---

## Common Pitfalls

| Pitfall | Problem | Fix |
|---------|---------|-----|
| Mixing facts and hypotheses | Readers can't distinguish what's known vs. guessed | Use Hypotheses section for all inference |
| Inventing missing info | Downstream work based on false premises | Write `(missing)` and add to Unknowns |
| Vague affected areas | "The models module" without specific files | Include exact paths and symbol names |
| Untestable hypotheses | "Something is wrong with caching" | Add concrete confirmation/refutation steps |
| Mixing current/expected | "It should return X but sometimes doesn't" | Separate into distinct bullet points |
| Proposing solutions | Context doc becomes a plan | Remove solutions; only document findings |
| Skipping test coverage | Unknown what's actually tested | Always check and document test state |

---

## Investigation Depth Levels

| Level | Code Exploration | External Sources | Dependency Tracing |
|-------|------------------|------------------|--------------------|
| **Quick scan** | Primary files only | None | None |
| **Partial deep dive** | Full affected area | Issues + recent changes | 1 level |
| **Exhaustive** | All related code | Full history archaeology | Multi-level |

Document which depth level was used in the Investigation Summary.

---

## Examples

### Minimal Example

```markdown
# CONTEXT

## Problem Statement
- **Goal**: Understand why batch processing fails for large inputs
- **User-visible symptom**: OOM error when batch size exceeds 1000
- **Severity/impact**: Blocks production deployment for large datasets
- **Scope**: Data loader module only; model architecture out of scope

## Investigation Summary
- **What was inspected**: `data/loader.py`, `tests/test_loader.py`, error logs
- **Key observations**:
  - Loader allocates full batch in memory before yielding
  - No streaming or chunked loading implemented
- **Confidence**: High - root cause is evident from code
- **Depth**: Partial deep dive

## Current vs Expected Behavior
- **Current**: Entire batch loaded into memory at once; OOM at batch_size > 1000
- **Expected**: Streaming/chunked loading; should handle batch_size up to 10000

## Affected Code Areas
- **Primary**: `data/loader.py` :: `BatchLoader.load()` - allocates full batch
- **Dependencies**: `data/transforms.py` - applies transforms per-item
- **Dependents**: `training/trainer.py` :: `Trainer.train_epoch()` - consumes batches

## Contracts and Invariants
- **Explicit**: `BatchLoader.load()` returns `List[Tensor]` of length `batch_size`
- **Implicit**: Memory usage assumed to be O(batch_size)

## Test Coverage
- **Existing**: `test_loader.py::test_small_batch` - only tests batch_size=10
- **Failing**: None (large batches not tested)
- **Gaps**: No tests for batch_size > 100

## Root Cause Hypotheses (ranked)
1. **Hypothesis**: Eager loading pattern causes full batch memory allocation
   - **Why plausible**: Code shows `data = [load(i) for i in range(batch_size)]`
   - **How to confirm**: Add memory profiling; observe linear growth with batch_size
   - **How to refute**: If memory stays constant, cause is elsewhere

## Unknowns and Risks
- **Unknowns**: Maximum safe batch_size for target hardware (missing)
- **Risks**: Changing to streaming may break downstream code expecting full lists

## Constraints Discovered
- Must maintain backward compatibility with existing `List[Tensor]` return type
```

### Example With Missing Information

```markdown
# CONTEXT

## Problem Statement
- **Goal**: Determine why API responses are slow
- **User-visible symptom**: 5+ second response times for `/api/predict`
- **Severity/impact**: User-reported; affecting production UX
- **Scope**: API endpoint and immediate dependencies

## Investigation Summary
- **What was inspected**: `api/routes.py`, server logs (partial)
- **Key observations**:
  - Endpoint calls model.predict() synchronously
  - No caching layer observed
- **Confidence**: Low - limited log access, no profiling data
- **Depth**: Quick scan

## Current vs Expected Behavior
- **Current**: Response time 5-8 seconds (from user reports)
- **Expected**: Response time < 500ms (per SLA)

## Affected Code Areas
- **Primary**: `api/routes.py` :: `predict_endpoint()` - handles request
- **Dependencies**: `models/predictor.py` :: `Predictor.predict()` - (missing - not inspected)
- **Dependents**: (missing - client code not available)

## Contracts and Invariants
- **Explicit**: (missing - no API spec found)
- **Implicit**: Response should be JSON with `prediction` field

## Test Coverage
- **Existing**: (missing - test files not located)
- **Failing**: (missing)
- **Gaps**: (missing)

## External Context
- **Environment**:
  - OS: (missing)
  - Runtime: Python 3.x (version unknown)
  - CI: (missing)

## Root Cause Hypotheses (ranked)
1. **Hypothesis**: Model inference is slow without GPU
   - **Why plausible**: No GPU config observed in deployment
   - **How to confirm**: Check deployment config; profile inference time
   - **How to refute**: If GPU is present and utilized, cause is elsewhere
2. **Hypothesis**: No response caching for repeated queries
   - **Why plausible**: No cache layer observed in route handler
   - **How to confirm**: Send identical requests; check if second is faster
   - **How to refute**: If caching exists, cause is elsewhere

## Unknowns and Risks
- **Unknowns**:
  - Actual deployment configuration
  - Model inference time in isolation
  - Whether issue is consistent or intermittent
- **Risks**:
  - Investigation incomplete; may need deeper access

## Constraints Discovered
- Limited log access constrains investigation depth
```

---

## Summary

**Key Takeaways:**

1. **CONTEXT.md documents findings, not solutions** - provide context for downstream decision-making
2. **Facts and hypotheses must be separate** - readers need to know what's certain vs. inferred
3. **Current vs Expected must be unambiguous** - this is the core gap analysis
4. **Always include concrete paths/symbols** - vague references are not actionable
5. **Hypotheses must be testable** - include how to confirm and refute each one
6. **Mark unknowns explicitly** - never invent missing information

**The Golden Rule**: If it wasn't observed, don't state it as fact. Use `(missing)` and document the gap in Unknowns.
