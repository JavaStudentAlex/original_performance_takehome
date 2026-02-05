---
name: task-md-tecc-formatting
description: Defines the canonical TASK.md format (TECC) and the refinement procedure for converting raw requests into structured tasks.
---

# TASK.md (TECC) Skill

## Overview

This skill standardizes how to define a **refined task** in `TASK.md` using the TECC structure:

| Section | Purpose |
|---------|---------|
| **Task** | What must be done (intent, not plan) |
| **Expected Outcome** | Observable completion criteria |
| **Constraints** | Hard requirements, non-goals, boundaries |
| **Context** | Background, rationale, repo pointers |

`TASK.md` is the single source of truth for intent.

---

## Alignment with `.github/copilot-instructions.md.md`

This skill treats `.github/copilot-instructions.md.md` as the **top-level contract**. If anything in this skill conflicts with it, follow `.github/copilot-instructions.md.md`.

When writing `TASK.md`:

- Prefer **pointers** over restating theory: reference canonical docs rather than duplicating content.
- Treat `tests/` as **immutable ground truth**; include "do not modify tests/" as a constraint when relevant.
- In **Expected Outcome**, name the repo's verification commands (e.g., test runners, linters, benchmarks), or mark them as `(to be confirmed)` if unknown.
- Keep `TASK.md` compact and high-signal; avoid pasting verbose logs or traces (store them in a file and reference the path instead).

---

## Quick Reference

### Pass Criteria

A valid `TASK.md` must:

- Contain exactly four TECC sections in canonical order
- Have an observable/verifiable Expected Outcome
- Include explicit non-goals in Constraints
- Mark unknowns as `(missing)` or `(to be confirmed)`

---

## Canonical TASK.md Format

`TASK.md` MUST contain these sections **in this order**, using the exact headings shown:

```markdown
# TASK

## Task
<One short paragraph describing what must be done. Use concrete verbs.>

## Expected Outcome
<What "done" means. Prefer observable outputs: files, behaviors, acceptance criteria.>

## Constraints
<Hard requirements and boundaries: scope, non-goals, quality gates, tooling limits, performance, determinism, etc.>

## Context
<Background, rationale, pointers to relevant modules/paths, known symptoms, related decisions, links to internal docs.>
```

### Section Requirements

| Section | Must Include | Must Avoid |
|---------|--------------|------------|
| Task | Concrete verbs, north-star intent | Implementation steps, acceptance criteria |
| Expected Outcome | Observable outputs, validation methods | Vague terms like "improve" or "optimize" |
| Constraints | Non-goals, quality thresholds, boundaries | Hidden assumptions |
| Context | Repo paths, rationale, known issues | Duplicate info from other sections |

---

## Refinement Procedure

When converting a raw request into TECC:

### Step 1: Task

- Write the north-star statement: what must be done, not how
- Keep it concrete; if the work is multi-part, list the parts in one sentence
- Avoid acceptance checks here; put them in **Expected Outcome**

**Good**: "Implement retry logic for API calls in the authentication module."

**Bad**: "Improve testing." (too vague, no concrete target)

### Step 2: Expected Outcome

Include clear completion signals:

- Artifacts that must exist (files, modules, docs)
- Behaviors that must change (APIs, outputs, UX, performance)
- How success is validated (tests, lint gates, benchmarks, deterministic runs)
- If something is unknown, mark it as `(to be confirmed)` rather than guessing

**Good**: "All tests pass; retry logic triggers on 5xx errors with exponential backoff."

**Bad**: "Code quality improves." (not measurable)

### Step 3: Constraints

Capture hard requirements and boundaries:

- Non-goals (explicitly out of scope)
- Quality requirements (lint/test/docs/coverage thresholds, if applicable)
- Tooling/runtime limits (offline, no network, deterministic, etc.)
- Compatibility requirements (platforms, versions, APIs)

**Good**: "Do not modify `tests/`. Keep diffs small and avoid refactoring unrelated code."

**Bad**: (omitting non-goals, leaving scope ambiguous)

### Step 4: Context

Capture background that helps planning and execution:

- Why this task matters
- Where it likely touches the repo (paths, modules)
- Known issues, errors, or symptoms
- Prior decisions, conventions, or related artifacts that must be respected

**Good**: "Auth module lives in `src/auth/`. Current implementation fails silently on network errors; see issue #42."

**Bad**: "This needs to be done." (no useful background)

---

## Common Pitfalls

| Pitfall | Problem | Fix |
|---------|---------|-----|
| Mixing plan steps into TASK.md | TASK.md is intent, not implementation | Move steps out; keep only the goal |
| Missing non-goals | Scope becomes ambiguous | Add explicit "do not" items to Constraints |
| Hiding assumptions | Downstream work may misinterpret | State assumptions explicitly |
| Overly broad outcomes | "Improve" without measurable checks | Add specific, testable criteria |
| Duplicate information | Same content in multiple sections | Keep each section focused on its purpose |

---

## Examples

### Minimal Example

```markdown
# TASK

## Task
Add input validation to the user registration endpoint to reject malformed email addresses.

## Expected Outcome
- All existing tests pass.
- New test cases cover valid and invalid email formats.
- Invalid emails return HTTP 400 with a descriptive error message.

## Constraints
- Do not modify anything in `tests/` (add new test files instead).
- Keep diffs small and reviewable; avoid unrelated refactors.
- Follow existing error response format in the codebase.

## Context
Registration endpoint is in `src/api/users.py`. Current implementation accepts any string as email, causing downstream issues in email delivery. Reference `docs/api-standards.md` for error response conventions.
```

### Example With Explicit Assumptions

```markdown
# TASK

## Task
Create a centralized definition of the TECC-based TASK.md schema as a reusable skill.

## Expected Outcome
- A single canonical TECC skill document exists (location: (to be confirmed by repo layout)) defining the TASK.md format and refinement rules.
- Newly produced TASK.md files conform to the canonical template.

## Constraints
- Do not change existing workflow phase definitions.
- If repository guidance conflicts, follow `.github/copilot-instructions.md.md`.

## Context
The goal is to avoid schema drift by keeping one canonical TECC reference and updating copies (if any) to point to it.
```

### Example With Missing Information

```markdown
# TASK

## Task
Implement caching for database queries in the product listing endpoint.

## Expected Outcome
- All existing tests pass.
- Response time improves by (to be confirmed) over baseline.
- Cache invalidation triggers on product updates.

## Constraints
- Do not modify anything in `tests/`.
- Cache TTL should be configurable (default value: (missing)).
- Do not change the public API contract.

## Context
Product listing endpoint is in `src/api/products.py`. Current implementation queries the database on every request; see performance issue #123. Reference `docs/caching.md` for caching patterns used in this codebase.
```

---

## Validation Checklist

Before treating `TASK.md` as complete, verify:

- [ ] Contains exactly four TECC sections in canonical order
- [ ] **Task** is one clear statement of intent (not a plan)
- [ ] **Expected Outcome** is observable and testable
- [ ] **Constraints** include non-goals and quality/tooling boundaries
- [ ] **Context** points to relevant repo areas and the reason the task exists
- [ ] Any unknowns are marked as `(missing)` or `(to be confirmed)`
- [ ] No implementation steps mixed into Task section
- [ ] No hidden assumptions

---

## Summary

**Key Takeaways:**

1. `TASK.md` uses exactly four sections: Task, Expected Outcome, Constraints, Context
2. Task describes **what**, not **how**
3. Expected Outcome must be **observable and verifiable**
4. Constraints must include **explicit non-goals**
5. Mark unknowns explicitly rather than guessing

**The Golden Rule**: `TASK.md` is the single source of truth for intent. When in doubt, make it explicit.
