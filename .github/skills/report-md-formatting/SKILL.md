---
name: report-md-formatting
description: Defines the canonical REPORT.md format for documenting completed work with verification evidence, key decisions, and follow-ups.
---

# REPORT.md Formatting Skill

## Overview

This skill standardizes how to produce a `REPORT.md` that documents what was done, why it was done, and how to verify it.

**Purpose**: Create a clear, consistent record of completed work that enables reviewers to understand outcomes without reading source materials.

**Output**: A single `REPORT.md` file containing summary, deliverables, work completed, verification evidence, key decisions, and follow-ups.

---

## When to Use

**Always use** when:
- Completing a task, feature, or deliverable
- Publishing results of an experiment or investigation
- Documenting a change for review or handoff
- Creating an audit trail for completed work

**Read this skill** when:
- Starting any report writing task
- Unsure what sections are required
- Need to structure findings for stakeholders

---

## Quick Reference

### Pass Criteria

A valid `REPORT.md` must:

- Start with `# Report`
- Contain all required sections: Summary, Deliverables, Work Completed, Verification
- Have Summary that tells a complete story without external context
- Include concrete deliverables that match what actually shipped
- Show verification evidence with commands and results (or explain why missing)
- List known issues with impact and suggested next step
- Mark unknowns explicitly as `(missing)` or `(not measured)`
- Contain no confidential secrets (tokens, credentials, internal-only URLs)

### Required vs Optional Sections

| Section | Required | Purpose |
|---------|----------|---------|
| Summary | Yes | High-level overview of request, outcome, scope, status |
| Deliverables | Yes | Concrete outputs that shipped |
| Work Completed | Yes | Steps taken, grouped logically |
| Verification | Yes | Evidence that deliverables work |
| Key Decisions | No | Rationale for non-trivial choices |
| Known Issues and Follow-ups | No | Bugs, tech debt, deferred items |
| How to Reproduce | No | Steps to validate independently |
| References and Artifacts | No | Links to PRs, commits, logs, etc. |
| Appendix | No | Long outputs, raw logs, charts |

---

## REPORT.md Format (Canonical)

`REPORT.md` MUST follow this structure. Omit optional sections that don't apply, but never omit required sections.

```markdown
# Report

## Summary
- **Request / goal:** <one sentence describing what was asked>
- **Outcome:** <measurable/observable result>
- **Scope:** <what was in / out of scope>
- **Status:** ✅ Done | ⚠️ Partial | ❌ Blocked
- **Notes:** <optional context>

## Deliverables
- <file, module, doc, endpoint, dataset, etc.>
- <use precise identifiers: paths, names, versions>

## Work Completed
- <major steps taken, grouped by theme>
- <map to plan if one existed>
- <call out anything intentionally skipped>

## Verification
- **Automated checks:**
  - Command: `<exact command run>`
  - Result: ✅ | ⚠️ | ❌ <key numbers if relevant>
- **Manual checks (if any):**
  - <what was verified manually>
- **Acceptance criteria mapping:** <optional>
  - <criterion> → <evidence>

## Key Decisions
- **Decision:** <what was decided>
  - **Rationale:** <why this choice>
  - **Alternatives considered:** <other options>
  - **Trade-offs:** <what was gained/lost>

## Known Issues and Follow-ups
- **Issue:** <what's wrong or missing>
  - **Impact:** <why it matters>
  - **Suggested next step:** <what to do>

## How to Reproduce
- **Environment:** <OS, runtime, version constraints>
- **Steps:**
  1. <step>
  2. <step>
- **Expected result:** <what should happen>

## References and Artifacts
- <links/paths to PRs, commits, tickets, logs, screenshots>

## Appendix
- <long outputs, raw logs, charts, measurements>
```

---

## Section Requirements

### Summary (Required)

Must provide enough context for someone to understand the work without reading other documents.

| Field | Must Include | Must Avoid |
|-------|--------------|------------|
| Request / goal | One sentence of original intent | Multi-paragraph descriptions |
| Outcome | Measurable or observable result | Vague "improvements" |
| Scope | Key inclusions and exclusions | Hidden scope changes |
| Status | Accurate reflection of reality | Optimistic misrepresentation |

### Deliverables (Required)

List concrete outputs that actually shipped.

| Must Include | Must Avoid |
|--------------|------------|
| Precise identifiers (paths, names) | Vague "updated files" |
| Only shipped items | Future/planned items (use Follow-ups) |
| Version or commit if relevant | Assumptions about what shipped |

### Work Completed (Required)

Document execution at the right granularity.

| Must Include | Must Avoid |
|--------------|------------|
| Major steps grouped by theme | Exhaustive timeline of every action |
| Constraints that shaped approach | Implementation details better in code |
| Items intentionally skipped | Hidden skipped items |

### Verification (Required)

Provide evidence that deliverables work.

| Must Include | Must Avoid |
|--------------|------------|
| Exact commands run | "Tests passed" without evidence |
| Results with key metrics | Invented or assumed results |
| Explanation if verification missing | Silent omission of verification |

### Key Decisions (Optional)

Capture decisions future maintainers will care about.

| Must Include | Must Avoid |
|--------------|------------|
| Rationale (why, not just what) | Decisions without justification |
| Alternatives considered | Only the chosen option |
| Trade-offs acknowledged | Pretending no downsides exist |

### Known Issues and Follow-ups (Optional)

Make future work obvious and actionable.

Each item must include:
- **Issue:** What's wrong or missing
- **Impact:** Why it matters
- **Suggested next step:** One sentence of what to do

### How to Reproduce (Optional)

Enable independent validation.

| Must Include | Must Avoid |
|--------------|------------|
| Minimal environment info | Assuming reader knows setup |
| Step-by-step instructions | Vague "run the tests" |
| Expected result | Steps without success criteria |

### References and Artifacts (Optional)

Provide traceability to source materials.

| Must Include | Must Avoid |
|--------------|------------|
| Stable identifiers (paths, IDs, URLs) | Vague "see the PR" |
| Only relevant references | Exhaustive link dumps |

---

## Writing Guidelines

### Granularity

Reports should be readable in under 5 minutes by someone who didn't do the work.

**Too detailed**: Every command run, every file touched, every decision micro-documented
**Too sparse**: "Did the thing, it works"
**Right level**: Major steps, key evidence, important decisions

### Evidence Standards

| Claim Type | Required Evidence |
|------------|-------------------|
| Tests pass | Command + exit code or summary |
| Performance improved | Before/after metrics |
| Coverage meets threshold | Coverage percentage |
| Lint passes | Command + result |
| Manual verification | What was checked and observed |

### Handling Missing Information

Use explicit markers rather than omitting or guessing:

- `(missing)` - Information not available
- `(not measured)` - Metric not collected
- `(not applicable)` - Section doesn't apply
- `(to be confirmed)` - Needs verification

---

## Common Pitfalls

| Pitfall | Problem | Fix |
|---------|---------|-----|
| Timeline instead of structure | Hard to find specific info | Group by theme, not chronology |
| Future plans in Deliverables | Misleading about what shipped | Move to Follow-ups |
| "Tests passed" without proof | Unverifiable claim | Include command and output |
| Missing trade-offs | Decisions seem arbitrary | Document alternatives considered |
| Burying outcomes in Appendix | Key info hard to find | Keep outcomes in main sections |
| Vague deliverables | "Updated the code" | Use exact paths and identifiers |
| No verification section | No proof work is correct | Always include, explain if missing |
| Secrets in logs | Security risk | Scrub tokens, credentials, internal URLs |

---

## Validation Checklist

Before treating `REPORT.md` as complete, verify:

- [ ] Starts with `# Report`
- [ ] Summary tells complete story without external context
- [ ] Summary includes Request/goal, Outcome, Scope, Status
- [ ] Deliverables are concrete and match what actually shipped
- [ ] Work Completed describes major steps (not a timeline)
- [ ] Verification includes commands and results
- [ ] Verification explains gaps if any checks are missing
- [ ] Key Decisions capture rationale and alternatives (if section included)
- [ ] Known Issues include impact and next step (if section included)
- [ ] How to Reproduce has concrete steps (if section included)
- [ ] No confidential secrets in any section
- [ ] Missing information marked explicitly, not omitted
- [ ] Readable in under 5 minutes

---

## Examples

### Minimal Example

```markdown
# Report

## Summary
- **Request / goal:** Add unit tests for the parser module
- **Outcome:** 12 new tests covering edge cases, 87% coverage achieved
- **Scope:** Parser module only; refactoring out of scope
- **Status:** ✅ Done

## Deliverables
- `tests/test_parser.py` (new file, 12 test functions)

## Work Completed
- Analyzed parser module for testable functions
- Wrote tests for: valid input, invalid input, empty input, malformed input
- Fixed one bug discovered during testing (missing null check)

## Verification
- **Automated checks:**
  - Command: `python -m pytest tests/test_parser.py -v`
  - Result: ✅ 12 passed in 0.45s
  - Command: `python -m pytest tests/test_parser.py --cov=src/parser --cov-report=term`
  - Result: ✅ 87% coverage (target was 80%)
```

### Detailed Example

```markdown
# Report

## Summary
- **Request / goal:** Implement batch processing for DataLoader to reduce memory usage
- **Outcome:** Memory usage reduced from O(dataset_size) to O(batch_size); 10x improvement for large datasets
- **Scope:** DataLoader streaming implementation; backward compatibility wrapper; tests and docs
- **Status:** ✅ Done
- **Notes:** Performance validated on datasets up to 100k samples

## Deliverables
- `src/data/loader.py` - Modified `BatchLoader.load()` to return generator
- `src/data/loader.py` - New `BatchLoader.load_all()` for backward compatibility
- `tests/test_loader.py` - 8 new tests for streaming behavior
- `docs/data_loading.md` - Updated API documentation

## Work Completed
- **Implementation**
  - Refactored `load()` from eager list to lazy generator
  - Added `load_all()` wrapper with deprecation warning
  - Preserved existing interface contract
- **Testing**
  - Added streaming behavior tests
  - Added memory bounded tests (mocked)
  - Verified backward compatibility with existing tests
- **Documentation**
  - Updated API docs with new streaming interface
  - Added migration guide for `load_all()` users

## Verification
- **Automated checks:**
  - Command: `python -m pytest tests/test_loader.py -v`
  - Result: ✅ 15 passed (8 new + 7 existing)
  - Command: `pyright src/data/loader.py`
  - Result: ✅ 0 errors
  - Command: `python -m pytest tests/ --cov=src/data --cov-report=term`
  - Result: ✅ 92% coverage
- **Manual checks:**
  - Verified memory usage with `memory_profiler` on 100k sample dataset
  - Before: 4.2GB peak | After: 420MB peak

## Key Decisions
- **Decision:** Return generator from `load()` instead of adding new method
  - **Rationale:** Cleaner API; most callers iterate once anyway
  - **Alternatives considered:** New `load_streaming()` method; iterator protocol
  - **Trade-offs:** Breaking change for callers expecting list; mitigated with `load_all()`

## Known Issues and Follow-ups
- **Issue:** `load_all()` deprecation warning not tested
  - **Impact:** Low - warning exists but no test coverage
  - **Suggested next step:** Add test capturing warning output
- **Issue:** Memory benchmark not automated
  - **Impact:** Medium - regression could go unnoticed
  - **Suggested next step:** Add memory benchmark to CI

## How to Reproduce
- **Environment:** Python 3.10+, pytest, memory_profiler (optional)
- **Steps:**
  1. `pip install -e .`
  2. `python -m pytest tests/test_loader.py -v`
  3. (Optional) `python -m memory_profiler examples/batch_demo.py`
- **Expected result:** All tests pass; memory stays bounded during iteration

## References and Artifacts
- PR: #142
- Commit: abc1234 "feat: implement streaming batch loader"
- Memory profile logs: `.github/benchmarks/loader-memory-20250120.log`
```

### Example With Missing Information

```markdown
# Report

## Summary
- **Request / goal:** Diagnose and fix slow API response times
- **Outcome:** Identified bottleneck in model inference; fix proposed but not implemented
- **Scope:** Diagnosis only; fix implementation deferred pending infrastructure decision
- **Status:** ⚠️ Partial

## Deliverables
- `docs/performance-analysis.md` - Analysis findings and recommendations
- `src/api/routes.py` - Added timing instrumentation (to be removed after fix)

## Work Completed
- Added timing instrumentation to `predict_endpoint()`
- Collected timing data over 100 requests
- Identified model inference as 95% of response time
- Documented findings and three fix options

## Verification
- **Automated checks:**
  - Command: `python -m pytest tests/test_api.py -v`
  - Result: ✅ All existing tests pass (instrumentation is non-breaking)
- **Manual checks:**
  - Timing logs reviewed for 100 requests
  - Median response: 5.2s | 95th percentile: 8.1s
  - Model inference: 4.9s median (95% of total)

## Key Decisions
- **Decision:** Defer fix implementation pending infrastructure decision
  - **Rationale:** All three fixes require infrastructure changes
  - **Alternatives considered:** (1) Add GPU, (2) Model quantization, (3) Async processing
  - **Trade-offs:** Diagnosis complete but user-facing issue remains

## Known Issues and Follow-ups
- **Issue:** API response time still exceeds SLA
  - **Impact:** High - users experiencing 5+ second waits
  - **Suggested next step:** Schedule infrastructure review to select fix approach
- **Issue:** Timing instrumentation adds ~50ms overhead
  - **Impact:** Low - acceptable for diagnosis period
  - **Suggested next step:** Remove instrumentation after fix deployed

## References and Artifacts
- Timing logs: `/tmp/api-timing-20250120.json` (not committed)
- Analysis doc: `docs/performance-analysis.md`
```

---

## Summary

**Key Takeaways:**

1. **REPORT.md documents completed work** - what shipped, how it was verified, what's left
2. **Required sections are non-negotiable** - Summary, Deliverables, Work Completed, Verification
3. **Verification needs evidence** - commands, outputs, metrics; not just "it works"
4. **Key decisions need rationale** - capture why, not just what
5. **Known issues need next steps** - make follow-up work actionable
6. **Mark missing information explicitly** - use `(missing)`, never omit silently

**The Golden Rule**: A good report enables any reader to understand what was done, verify it works, and know what's left - without reading any other documents.
