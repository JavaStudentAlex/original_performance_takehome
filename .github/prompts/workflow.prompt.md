# workflow.prompt.md
# Purpose: Canonical workflow entrypoint -- concrete agent/artifact mapping that composes existing skills and registries.

Canonical repo path: `.github/prompts/workflow.prompt.md`

This file defines **which agent does what, when, and how handoffs happen**.
It does not duplicate procedures from skills or registries -- it references them.

---

## -1) Preflight bootstrap (fail-closed)

**This section is BLOCKING.** Before doing anything else (including TECC extraction, planning, delegation,
running tools/commands, or editing any files), you MUST ensure the required files below are loaded,
in this exact order:

### Ground Truth (load first)

1. `AGENTS.md` -- skills catalog, quality gates, conventions
2. `.github/copilot-instructions.md` -- repo coding standards and tooling rules

### Registries

3. `.github/prompts/agents.prompt.md` -- agent roster, default models
4. `.github/prompts/artifacts.prompt.md` -- artifact ownership and edit access

### Global Cycle Skill (MANDATORY)

5. Resolve `workflow-cycle-running` from `AGENTS.md` Skills Catalog, then load the resolved skill file

   This skill defines the phase gates, restart rules, and artifact requirements for end-to-end execution.
   Without it, you cannot run a global cycle.

### What "loaded" means (strict)

A file is considered **loaded** only if, in the current run context, you can **quote at least one
verbatim line** from it (e.g., a heading line), OR you have just retrieved it via a file-read tool
and it is visible in context.

### If anything is missing: STOP

If any required file is not loaded / unreadable / absent:

Output exactly these two lines and then STOP (no other text):
```
ACTIVE AGENT: <agent-name>
WORKFLOW_PREFLIGHT: FAIL -- missing <path-or-skill-name>
```

Do NOT:
- infer or "approximate" missing rules
- invoke any subagent
- update artifacts
- proceed to any phase

### Preflight success handshake

If all required files are loaded, the **first** message of the run MUST begin with exactly:
```
ACTIVE AGENT: <agent-name>
WORKFLOW_PREFLIGHT: OK
```

This is machine-checkable and intended to be enforced by external runners.

---

## 0) Start Global Cycle (MANDATORY)

After `WORKFLOW_PREFLIGHT: OK`:

1. Execute the `workflow-cycle-running` skill
2. Use this file's Phase Execution Map (§4) as the concrete agent/artifact binding
3. Follow the skill's gate and restart rules

Do NOT skip to Phase B before Phase A gate passes.

---

## 1) Ground Truth (must be loaded)

1. `AGENTS.md` -- skills catalog, quality gates, conventions
2. `.github/copilot-instructions.md` -- repo coding standards and tooling rules

These always win if conflicts arise.

---

## 2) Registries

| Registry | Path | What it defines |
|----------|------|-----------------|
| Agents | `.github/prompts/agents.prompt.md` | Agent roster, default models, agent file paths |
| Artifacts | `.github/prompts/artifacts.prompt.md` | Artifact ownership and edit access |

---

## 3) Invariants

1. **Artifact ownership**: Defined in `artifacts.prompt.md`. Owners write; non-owners propose via `project-manager`.
2. **Agent invocation**: Always use `copilot-cli-subagent-running` skill with models from `agents.prompt.md`.
3. **Banner protocol**: Every assistant message starts with `ACTIVE AGENT: <agent-name>`.
4. **No fabrication**: Missing content is labeled `(missing)`, never invented.
5. **Fail-closed preflight**: If Preflight bootstrap is not satisfied, STOP (do not continue).
6. **Repo guardrails**: Follow mandatory guardrails and quality gates from `AGENTS.md` and `.github/copilot-instructions.md`.

---

## 4) Phase Execution Map

### Phase 0 -- Input (workflow entry point)

| Field | Value |
|-------|-------|
| Input | User request (raw) |
| Agent | `project-manager` |
| Output | `TASK.md` (refined prompt in TECC format) |
| Skill | `task-md-tecc-formatting` |

This is the **first step** of every workflow.

### Phase A -- Planning (Deep Research + Plan)

| Field | Value |
|-------|-------|
| Agent | `planner` |
| Critic | `plan-critic` |
| Artifact | `PLAN.md` |
| Skill | `plan-md-formatting` |

### Phase B -- Implementation

| Field | Value |
|-------|-------|
| Coordinator | `project-manager` |
| Artifact | `STEP.md` + code/tests/docs |
| Skills | `step-md-formatting`, `impl-refine-cycle-running` |

Implementer/critic pairs per step type:

| Step Type | Implementer | Critic |
|-----------|-------------|--------|
| ILP scheduling / bundling | `ilp-schedule-expert` | `ilp-schedule-critic` |
| SIMD vectorization / VALU utilization | `simd-vect-expert` | `simd-vect-critic` |
| Memory traffic / scratchpad / pipelining | `memory-opt-expert` | `memory-opt-critic` |
| Control flow / predication / FLOW minimization | `control-flow-expert` | `control-flow-critic` |
| Documentation / report | `docs-expert` | `docs-critic` |

### Phase C -- Report

| Field | Value |
|-------|-------|
| Agent | `docs-expert` |
| Critic | `docs-critic` |
| Artifact | `REPORT.md` |
| Skill | `report-md-formatting` |

---

## 5) Context Pack

Pass to every subagent. Schema fields:

```
RUN_ID, PHASE, STEP_ID, CYCLE_NUM, AGENT_ROLE
TASK_MD, PLAN_MD, STEP_MD
MICRO_TASK, DEFINITION_OF_DONE, PREV_CRITIQUE
RELEVANT_CODE_CONTEXT, PROGRESS_SINCE_LAST_CYCLE
```

If a field is unavailable, write `(missing)`.

---

## 6) State Location

State lives under `.github/agent-state/**` (see `artifacts.prompt.md` for ownership).

- **Run journal** (global cycle): `.github/agent-state/runs/<RUN_ID>/` (per `workflow-cycle-running` skill)
- **Per-step cycle artifacts** (impl cycles): `.github/agent-state/cycles/<STEP_ID>/` (per `impl-refine-cycle-running` skill)

---

## 7) Failure Restarts

| Failure Type | Restart At |
|--------------|------------|
| Intent unclear | Phase 0 |
| Evidence weak | Phase A |
| Plan wrong | Phase A |
| Implementation blocked | Phase B (same step) |

See `workflow-cycle-running` skill for restart procedures.

---

## References

- `AGENTS.md`
- `.github/copilot-instructions.md`
- `.github/prompts/agents.prompt.md`
- `.github/prompts/artifacts.prompt.md`
- `workflow-cycle-running` skill (resolved from `AGENTS.md` Skills Catalog)
