---
name: workflow-cycle-running
description: Orchestrates one full end-to-end development iteration (task framing, planner-led research+planning, implementation, verification) by composing existing skills. Defines phase gates, restart rules, and required artifacts.
---

# Skill: workflow-cycle-running

Orchestrate a complete development cycle from raw request to verified deliverable.

---

## Overview

This skill defines the **global development cycle** as a reusable, high-level coordination unit.

A global cycle is one complete end-to-end iteration through:

1. **Task framing** - Convert raw request into structured intent
2. **Planning (with deep research)** - Gather evidence and produce executable plan
3. **Implementation** - Execute steps with refinement cycles
4. **Verification** - Validate and report outcomes

**Key principle:** This skill is intentionally abstract. It defines phases, gates, artifacts, and restart semantics without prescribing specific agents, models, or orchestration tooling.

---

## When to Use

**Always use** when:
- Starting a new feature, fix, or investigation from a raw request
- Orchestrating end-to-end work that requires planning and implementation
- Coordinating multiple agents through a structured workflow
- Ensuring consistent artifact production and quality gates

**Read this skill** when:
- Starting any orchestration task
- Unsure which phase to run next
- Handling failures and determining restart boundaries
- Validating that a cycle is complete

---

## Quick Reference

### Phase Summary

| Phase | Goal | Input | Output | Gate |
|-------|------|-------|--------|------|
| 0 | Task framing | Raw request | `TASK.md` | TECC sections complete, outcomes observable |
| A | Planning (deep research + plan) | `TASK.md` | `PLAN.md` | Research evidence captured; steps have IDs, scope, DoD |
| B | Implementation | `PLAN.md` | Code + `STEP.md` per step | Each step DoD satisfied with evidence |
| C | Verification | All artifacts | `REPORT.md` | Quality gates pass, evidence recorded |

### Cycle Outcomes

| Outcome | Meaning |
|---------|---------|
| `SUCCESS` | All phases completed, all steps accepted, `REPORT.md` produced |
| `RESTART_REQUIRED` | Cycle aborted; must restart from a configured phase boundary |
| `BLOCKED` | Cannot proceed without external intervention |

### Restart Boundaries

| Failure Type | Restart From |
|--------------|--------------|
| Unclear/unstable requirements | Phase 0 (Task) |
| Insufficient evidence / wrong assumptions | Phase A (Plan research) |
| Plan not implementable | Phase A (Plan research) |
| Implementation blockers with adequate plan | Phase B (Implementation) |

---

## Dependencies

This skill composes these skills as building blocks:

| Dependency | Path | Purpose |
|------------|------|---------|
| TECC task framing | `.github/skills/task-md-tecc-formatting/SKILL.md` | Canonical `TASK.md` format |
| Plan definition | `.github/skills/plan-md-formatting/SKILL.md` | Canonical self-contained `PLAN.md` format |
| Step tracking | `.github/skills/step-md-formatting/SKILL.md` | Canonical `STEP.md` format |
| Implementation refinement | `.github/skills/impl-refine-cycle-running/SKILL.md` | One implementer+critic pass |
| Reporting | `.github/skills/report-md-formatting/SKILL.md` | Canonical `REPORT.md` format |

**Indirect dependencies:** `impl-refine-cycle-running` may rely on additional skills (agent invocation). This skill treats those as internal to that dependency.

---

## Non-Goals

This skill does **not**:
- Choose which agents to run (IDs/roles are caller-provided)
- Define how to invoke agents (delegated to other skills/orchestration)
- Define repo-specific quality thresholds (captured in `TASK.md` Constraints)

---

## Required Artifacts

A global cycle produces and maintains these canonical artifacts:

| Artifact | Owner Phase | Purpose |
|----------|-------------|---------|
| `TASK.md` | Phase 0 | Single source of truth for intent |
| `PLAN.md` | Phase A | Deep-research-backed implementation roadmap |
| `STEP.md` | Phase B | Per-step execution state |
| `REPORT.md` | Phase C | Verification evidence and outcomes |

### Optional State Artifacts

Recommended for traceability (paths are conventions):

- `.github/agent-state/runs/<RUN_ID>/cycle.md` - High-level run journal
- `.github/agent-state/runs/<RUN_ID>/steps/<STEP_ID>/...` - Cycle outputs per step

---

## Inputs

The caller must supply or derive a run configuration.

### Required Inputs

| Input | Type | Description |
|-------|------|-------------|
| `RUN_ID` | string | Unique identifier for this global cycle run |
| `TASK_SOURCE` | string | Raw user request or issue description |
| `PHASE_LIMITS` | object | Limits to avoid infinite loops |

**PHASE_LIMITS structure:**
- `MAX_PLAN_REFINEMENTS`: integer (default: 3)
- `MAX_CYCLES_PER_STEP`: integer (default: 5)

### Recommended Inputs

| Input | Type | Description |
|-------|------|-------------|
| `RESTART_POLICY` | object | When and where to restart on failure |
| `STEP_EXECUTION_POLICY` | object | How to sequence steps |
| `QUALITY_GATES` | pointer | Commands/criteria that must pass |

**RESTART_POLICY structure:**
- `restart_from`: one of `TASK`, `PLAN`, `IMPLEMENTATION`
- `restart_on`: list of conditions

**STEP_EXECUTION_POLICY structure:**
- `order`: `sequential` (default) or `dependency-aware`
- `stop_on_first_hard_fail`: boolean (default: true)

---

## Procedure

### Phase -1: Pre-flight (Hard Gate)

**Goal:** Ensure a safe starting point for an end-to-end iteration.

**Checklist:**
- [ ] Inputs are present (`TASK_SOURCE`, `RUN_ID`)
- [ ] Workspace is in a known state (clean working tree or dedicated branch)
- [ ] Constraints understood (offline, determinism, no network, etc.)

**Gate:** All checklist items satisfied.

**If pre-flight fails:** Outcome is `BLOCKED`.

---

### Phase 0: Task Framing (Hard Gate)

**Goal:** Convert raw request into canonical, unambiguous intent.

**Procedure:**
1. Produce or refine `TASK.md` using `.github/skills/task-md-tecc-formatting/SKILL.md`
2. Validate TECC pass criteria

**Gate:** `TASK.md` satisfies:
- All four TECC sections present (Task, Expected Outcome, Constraints, Context)
- Expected Outcome is observable and testable
- Constraints include explicit non-goals
- Unknowns marked as `(missing)` or `(to be confirmed)`

**If Phase 0 fails:** Outcome is `BLOCKED` (task cannot be stated clearly enough to proceed).

---

### Phase A: Planning (Deep Research + Plan) (Hard Gate)

**Goal:** Gather evidence and convert intent into an implementable plan.

**Procedure:**
1. Produce or refine `PLAN.md` using `.github/skills/plan-md-formatting/SKILL.md`
2. If caller uses plan-critique loop, apply up to `MAX_PLAN_REFINEMENTS`
3. Validate plan pass criteria

**Gate:** `PLAN.md` is implementation-ready:
- Includes research evidence with inspected scope, factual observations, unknowns, and constraints
- Steps uniquely identified (P01, P02, ...)
- Each step has Implementer, Critic, Scope, DoD
- Scope contains concrete paths/symbols
- DoD contains observable, testable criteria
- Dependencies and risks described (or marked `(missing)`)

**If Phase A fails:**
- Missing/weak evidence: `RESTART_REQUIRED` from Phase A
- Unclear intent: `RESTART_REQUIRED` from Phase 0

---

### Phase B: Implementation (Step-wise)

**Goal:** Execute each plan step with iterative implementer+critic refinement.

**Procedure for each step in `PLAN.md`:**

1. **Initialize step tracker**
   - Create or update `STEP.md` using `.github/skills/step-md-formatting/SKILL.md`
   - Set Status = `IN_PROGRESS`, Cycles completed = 0

2. **Run refinement cycles (loop)**
   - Use `.github/skills/impl-refine-cycle-running/SKILL.md`
   - Provide: step ID, cycle number, microtask, DoD, implementer/critic identifiers, prior critique

3. **Stop step loop when:**
   - Verdict is `PASS` or `SOFT_FAIL` (step accepted), OR
   - `MAX_CYCLES_PER_STEP` reached, OR
   - `HARD_FAIL` returned and policy says stop

4. **Record step outcome**
   - Update `STEP.md` with verdict, evidence, status
   - If step complete: Status = `DONE`

**Step Gate (per step):**
- DoD satisfied (as stated in `PLAN.md` / `STEP.md`)
- Evidence recorded (commands run, outputs, pass/fail)
- Outcome recorded in `STEP.md`

**Failure Handling:**

| Verdict | Action |
|---------|--------|
| `PASS` | Step accepted; proceed to next step |
| `SOFT_FAIL` | Step accepted unless policy requires nit fixes |
| `HARD_FAIL` | Stop; determine restart boundary |

**HARD_FAIL classification:**

| Cause | Restart From |
|-------|--------------|
| Plan flaw (bad decomposition, missing DoD) | Phase A |
| Missing facts / wrong assumptions | Phase A |
| Unclear intent / shifting requirements | Phase 0 |

Preserve evidence (cycle outputs, step notes) for next run, but treat as non-authoritative until revalidated.

---

### Phase C: Verification and Report (Hard Gate)

**Goal:** Consolidate results and provide auditable evidence of correctness.

**Procedure:**
1. Produce `REPORT.md` using `.github/skills/report-md-formatting/SKILL.md`
2. Ensure report includes:
   - What changed (high-level)
   - What was verified (commands/tests) with results
   - Known limitations / risks
   - Pointers to key artifacts (`TASK.md`, `PLAN.md`, `STEP.md` files)

**Gate:** All quality gates stated in `TASK.md` Constraints are satisfied (or exceptions documented with rationale).

**If Phase C fails:** `RESTART_REQUIRED` from Phase B (unless failure reveals plan issues).

---

## Restart Semantics

A restart is a **new global cycle run** with a new `RUN_ID`, retaining prior artifacts as references.

### Default Restart Mapping

| Failure Condition | Restart Phase | Rationale |
|-------------------|---------------|-----------|
| Requirements unclear or unstable | 0 (Task) | Intent must be re-clarified |
| Evidence insufficient or wrong | A (Plan research) | Need more investigation/planning evidence |
| Plan not implementable | A (Plan research) | Decomposition needs revision |
| Implementation blocked, plan OK | B (Implementation) | Retry with same plan |

### Restart Procedure

1. Record failure reason in current run's state log
2. Create new `RUN_ID`
3. Copy relevant artifacts as starting point (marked as prior-run references)
4. Begin from the designated restart phase
5. Revalidate all downstream artifacts

---

## Guardrails

1. **No duplication of lower-level mechanics**
   Always delegate formatting, refinement-cycle execution, and reporting to referenced skills.

2. **Evidence over claims**
   Every "verified" statement must correspond to recorded evidence (commands, outputs, test results).

3. **Explicit unknowns**
   Unknowns must be written as `(missing)` / `(to be confirmed)` rather than guessed.

4. **Hard gates are real**
   Do not start later phases until earlier phase gates pass.

5. **Step scope discipline**
   Implementation changes must remain aligned to current step and DoD; avoid unplanned refactors.

6. **Artifact ownership**
   Each artifact has one owner phase; do not modify artifacts outside their owner phase without explicit handoff.

---

## Validation Checklist

Before treating a global cycle as complete, verify:

- [ ] Phase 0 gate passed: `TASK.md` has all TECC sections, observable outcomes
- [ ] Phase A gate passed: `PLAN.md` includes research evidence plus executable steps with scope and DoD
- [ ] Phase B gate passed: All steps have Status = `DONE`, evidence recorded
- [ ] Phase C gate passed: `REPORT.md` documents verification with commands and results
- [ ] All quality gates from `TASK.md` Constraints are satisfied
- [ ] No artifacts contain `(missing)` without documented mitigation
- [ ] Run journal/logs capture phase transitions and outcomes

---

## Common Pitfalls

| Pitfall | Problem | Fix |
|---------|---------|-----|
| Skipping deep research in planning | Plan based on assumptions, not evidence | Require research evidence in `PLAN.md` before steps |
| Vague DoD in plan | Cannot verify step completion | Ensure DoD is observable and testable |
| Ignoring SOFT_FAIL nits | Tech debt accumulates | Track nits for follow-up or fix before proceeding |
| Restarting without new RUN_ID | Confusion about which run's artifacts are current | Always create new RUN_ID on restart |
| No evidence in report | Claims without proof | Include commands run and their outputs |
| Mixing phase responsibilities | Artifacts modified by wrong phase | Respect artifact ownership strictly |

---

## Examples

### Minimal Cycle Configuration

```yaml
RUN_ID: "run-2025-01-21-001"
TASK_SOURCE: "Add unit tests for the parser module"
PHASE_LIMITS:
  MAX_PLAN_REFINEMENTS: 3
  MAX_CYCLES_PER_STEP: 5
```

### Full Configuration

```yaml
RUN_ID: "run-2025-01-21-002"
TASK_SOURCE: "Implement batch processing for DataLoader to reduce memory usage"
PHASE_LIMITS:
  MAX_PLAN_REFINEMENTS: 3
  MAX_CYCLES_PER_STEP: 5
RESTART_POLICY:
  restart_from: PLAN
  restart_on:
    - insufficient_evidence
    - wrong_assumptions
STEP_EXECUTION_POLICY:
  order: sequential
  stop_on_first_hard_fail: true
QUALITY_GATES:
  - "python -m pytest tests/"
  - "pre-commit run --all-files"
```

### Phase Transition Log Entry

```markdown
## 2025-01-21T14:30:00Z - Phase Transition

- From: Phase 0 (Task)
- To: Phase A (Planning)
- Gate Status: PASSED
- Artifacts:
  - TASK.md: validated
- Next Action: Produce PLAN.md with research evidence
```

### Restart Decision Log Entry

```markdown
## 2025-01-21T16:45:00Z - Restart Decision

- Current Phase: B (Implementation)
- Step: P02
- Verdict: HARD_FAIL
- Cause: Plan step P02 depends on API that doesn't exist (wrong assumption)
- Classification: Missing facts / wrong assumptions
- Decision: RESTART_REQUIRED from Phase A
- New RUN_ID: run-2025-01-21-003
- Preserving: TASK.md (valid), PLAN.md (to be updated), cycle-01-*.md logs
```

---

## Summary

**Key Takeaways:**

1. **Global cycle has four hard-gate phases** - Phase 0 Task, Phase A Plan (with research), Phase B Implement, Phase C Verify
2. **Phases are sequential** - Do not skip phases; each gate must pass before proceeding
3. **Compose, don't duplicate** - Reference other skills for artifact formatting and refinement mechanics
4. **Restart boundaries are defined** - Failures map to specific restart phases based on cause
5. **Evidence is mandatory** - Every verification claim needs recorded commands and outputs
6. **Unknowns are explicit** - Mark `(missing)` rather than guess; document in plan/report

**The Golden Rule:** A global cycle succeeds when all phase gates pass and `REPORT.md` contains verifiable evidence that `TASK.md` intent was satisfied.

---

## References

- `.github/skills/task-md-tecc-formatting/SKILL.md` - Task framing
- `.github/skills/plan-md-formatting/SKILL.md` - Planning with embedded research evidence
- `.github/skills/step-md-formatting/SKILL.md` - Step tracking
- `.github/skills/impl-refine-cycle-running/SKILL.md` - Implementation refinement
- `.github/skills/report-md-formatting/SKILL.md` - Reporting
