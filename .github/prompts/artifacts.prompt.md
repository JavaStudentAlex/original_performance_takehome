# artifacts.prompt.md
# Purpose: Artifact registry defining ownership, edit access, and governance rules for workflow artifacts.

This file is the single source of truth for the project's **workflow artifacts**: which artifacts exist, which agent **owns** each artifact, and who is allowed to **edit** it.

---

## 1) Artifact Registry

| Artifact | Owner | Edit Access | Purpose |
|----------|-------|-------------|---------|
| `TASK.md` | `project-manager` | `project-manager` only | Canonical task framing (TECC format). Input to all phases. |
| `STEP.md` | `project-manager` | `project-manager` only | Per-step execution tracker: status, cycles, verdicts. |
| `CONTEXT.md` | `researcher` | `researcher` only | Research findings, hypotheses, affected code areas, unknowns. |
| `PLAN.md` | `planner` | `planner` only | Multi-step implementation plan with ownership and DoD per step. |
| `REPORT.md` | `docs-expert` | `docs-expert` only | Final summary with deliverables and verification evidence. |
| `.github/agent-state/**` | `project-manager` | `project-manager` only | Run journals, cycle artifacts, patches, workflow state. |

---

## 2) Enforcement Rules

These rules are **non-negotiable**.

### 2.1) Owners Write; Non-Owners Propose

If an agent needs a change to an artifact it does not own, it MUST:
1. Route the request through `project-manager`
2. `project-manager` delegates to the owning agent

**Example:** If `ml-expert` discovers the plan is incomplete, it proposes changes via `project-manager`, who delegates to `planner`.

### 2.2) No Silent Scope Changes

Changes to `TASK.md` or `STEP.md` are coordination changes:
- Only `project-manager` may apply them
- Changes must be explicit and logged
- No scope expansion without user approval

### 2.3) No Drive-By Edits

Implementation and critic agents must not directly edit workflow artifacts they do not own:
- Service agents (`ml-expert`, `test-expert`, `docs-expert`) produce code/tests/docs only
- Critic agents review and may apply minimal fixes to code, but not to workflow artifacts
- All artifact updates flow through proper ownership channels

---

## 3) Artifact Lifecycle

### 3.1) Creation

| Artifact | Created In | Created By |
|----------|------------|------------|
| `TASK.md` | Phase A (or before) | `project-manager` |
| `CONTEXT.md` | Phase A | `researcher` |
| `PLAN.md` | Phase B | `planner` |
| `STEP.md` | Phase B (after plan accepted) | `project-manager` |
| `REPORT.md` | Phase D | `docs-expert` |

### 3.2) Updates During Workflow

| Artifact | Updated When | Updated By |
|----------|--------------|------------|
| `TASK.md` | Scope clarification needed | `project-manager` (with user approval) |
| `CONTEXT.md` | New research findings | `researcher` (via delegation) |
| `PLAN.md` | Plan refinement cycles | `planner` (via delegation) |
| `STEP.md` | Every cycle completion | `project-manager` |
| `REPORT.md` | Report refinement cycles | `docs-expert` |

---

## 4) Quick Reference

```
project-manager
  |-- TASK.md
  |-- STEP.md
  |-- .github/agent-state/**

researcher
  |-- CONTEXT.md

planner
  |-- PLAN.md

docs-expert
  |-- REPORT.md
```

---

## References

- [`AGENTS.md`](../../AGENTS.md) - Agent definitions, skills, quality gates
