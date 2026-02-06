# AGENTS.md
# Purpose: Skills, Quality Gates, and Conventions

This document defines the **available skills**, **quality gate patterns**, and **execution conventions** for agent-based work in this repository.

---

## 0) Mandatory Guardrails (Non-Negotiable)

These guardrails apply to **all agents, all tools, and all workflows**. If anything conflicts, follow this section first.

1. **Always load `.github/copilot-instructions.md`**
   - Before doing any work, ensure `.github/copilot-instructions.md` has been read and is in the active context.
   - If you are not certain it is loaded, re-open/read it (treat it as the top-level contract).
   - When invoking Copilot CLI subagents, include `.github/copilot-instructions.md` in the context pack (e.g., via `--context-file` or explicit "READ: .github/copilot-instructions.md" in the prompt).

2. **Never edit anything under `tests/`**
   - Do not modify, create, delete, rename, move, or reformat any file or folder inside `tests/`.
   - `tests/` is **read-only ground truth** for correctness.

3. **Do not change the testing interface**
   - Do not change public APIs, module names, entrypoints, function signatures, output formats, or file locations that tests depend on.
   - If a change could affect how tests call into the code, it is **out of scope** unless explicitly requested.

4. **Do not change constants defined in the code**
   - Do not modify existing constant values (e.g., module-level "constants", fixed parameters, lookup tables, or other stable configuration baked into the code).
   - If tunability is needed, add *new* configuration that defaults to the existing behavior, while leaving existing constants unchanged.

---

## 1) Contract Hierarchy

When in doubt about what to follow, use this precedence order:

1. `.github/copilot-instructions.md` (repo top-level contract)
2. This `AGENTS.md` (mandatory guardrails + execution conventions)
3. Individual skills under `.github/skills/` (procedures and formats)

Skills must never override the guardrails above.

---

## 2) Skills Catalog

Skills are reusable instruction sets that agents follow for specific tasks.

### Coordination Skills

#### copilot-cli-subagent-running
- **Path**: `.github/skills/copilot-cli-subagent-running/SKILL.md`
- **Purpose**: Invoke agents via Copilot CLI with proper model selection and context packing
- **Priority**: MANDATORY for all agent invocations
- **Scope note**: Invocation only — runs Copilot CLI subagents in the current workspace via the wrapper script and produces a patch from a directory-state diff.
- **Guardrail notes**: Always ensure `.github/copilot-instructions.md` is loaded before invoking.

#### task-md-tecc-formatting
- **Path**: `.github/skills/task-md-tecc-formatting/SKILL.md`
- **Purpose**: Convert raw requests into structured TASK.md using TECC format
- **Sections**: Task, Expected Outcome, Constraints, Context
- **Pass criteria**: All four TECC sections present, outcomes observable, non-goals explicit

#### plan-md-formatting
- **Path**: `.github/skills/plan-md-formatting/SKILL.md`
- **Purpose**: Convert `TASK.md` + planner-led research findings into a canonical, implementation-ready `PLAN.md` with explicit step ownership and verifiable DoD
- **Use when**: Planning execution after task refinement; splitting work into steps across implementer/critic agents
- **Output**: `PLAN.md` with Summary + sequential steps (`P01`, `P02`, ...) using the required step fields
- **Pass criteria**: `PLAN.md` follows canonical structure; every step includes Implementer/Critic + model fields, concrete Scope (paths/symbols), and observable DoD; unknowns marked `(missing)` / `(to be confirmed)`

#### step-md-formatting
- **Path**: `.github/skills/step-md-formatting/SKILL.md`
- **Purpose**: Track execution of a single work step with status, assignments, cycles, verdicts, and execution context
- **Use when**: Starting execution of a planned step (P01, P02, etc.); tracking iterative refinement cycles; handing off work mid-step; recording verdicts and cycle outcomes;
- **Output**: `STEP.md` at repo root with step identity, implementer/critic assignments, microtask, DoD, cycle policy, verdict, and execution-context tracking
- **Pass criteria**: Status is one of `NOT_STARTED`/`IN_PROGRESS`/`DONE`/`BLOCKED`; Latest Verdict is one of `PASS`/`SOFT_FAIL`/`HARD_FAIL`/`N/A`; all required fields present; execution-context fields populated; completion requires cycles >= minimum AND passing verdict AND DoD satisfied

#### report-md-formatting
- **Path**: `.github/skills/report-md-formatting/SKILL.md`
- **Purpose**: Document completed work in canonical `REPORT.md` format with verification evidence, key decisions, and follow-ups
- **Use when**: Completing a task/feature/deliverable; publishing experiment results; documenting changes for review or handoff; creating audit trails
- **Output**: `REPORT.md` with Summary, Deliverables, Work Completed, Verification (required); Key Decisions, Known Issues, How to Reproduce, References, Appendix (optional)
- **Pass criteria**: Starts with `# Report`; all required sections present; Summary tells complete story without external context; Verification includes commands and results; missing info marked explicitly `(missing)` / `(not measured)`

#### impl-refine-cycle-running
- **Path**: `.github/skills/impl-refine-cycle-running/SKILL.md`
- **Purpose**: Run exactly one implementer+critic refinement cycle, persist cycle artifacts, and select/apply patch based on verdict
- **Use when**: Executing Phase B refinement cycles for a step; you need deterministic per-cycle outputs and patch handling
- **Output**: `cycle-<NN>-service.md`, `cycle-<NN>-critic.md` written under `STATE_BASE_DIR` (default: `.github/agent-state/cycles/<STEP_ID>/`)
- **Pass criteria**: Artifacts are written; verdict recorded; patch is applied only on `PASS`/`SOFT_FAIL` and never on `HARD_FAIL`; skill stops after one cycle (looping is caller responsibility)
- **Guardrail notes**: Must not apply patches that touch `tests/`, change test interfaces, or modify constants.

#### workflow-cycle-running
- **Path**: `.github/skills/workflow-cycle-running/SKILL.md`
- **Purpose**: Orchestrate a complete development cycle (task framing, planning with deep research, implementation, verification) with phase gates, restart semantics, and evidence-backed completion
- **Use when**: Starting a new feature/fix/investigation from raw request; coordinating end-to-end work through structured phases; ensuring consistent artifact production and quality gates
- **Output**: `TASK.md`, `PLAN.md`, `STEP.md` per step, `REPORT.md`; optional run journal at `.github/agent-state/runs/<RUN_ID>/`
- **Pass criteria**: All hard-gate phases pass; all steps have Status = `DONE` with evidence; `REPORT.md` includes verification commands and results; quality gates from `TASK.md` Constraints satisfied

### Quality Gate Skills

#### python-linting
- **Path**: `.github/skills/python-linting/SKILL.md`
- **Purpose**: Code quality and type safety verification
- **Gates**:
  - `isort --check`: Import sorting verification
  - `black --check`: Format verification
  - `flake8`: Linting
  - `mypy`: Type checking
- **Pass criteria**: All checks pass with zero errors

#### python-docs-covering
- **Path**: `.github/skills/python-docs-covering/SKILL.md`
- **Purpose**: Documentation coverage verification
- **Gates**:
  - `pydocstyle --convention=numpy`: Docstring style check
  - Cross-reference accuracy check
- **Pass criteria**: 100% public API coverage, no stale docs

---

## 3) Quality Gate Patterns

Use the repo's contract in `.github/copilot-instructions.md` as the source of truth for what is required. This section captures common patterns without overriding that contract.

### Core correctness gate (required)

- Run the repository's authoritative correctness check(s) as specified by the repo.
- In this repo, correctness is validated against the existing tests (read-only). A common entrypoint is `python tests/submission_tests.py` (if present), but always defer to `.github/copilot-instructions.md` for the exact command.

### Testing requirements for this repository

**Running tests is mandatory** after any code change.

| Test Suite | Must Pass? | Purpose |
|------------|------------|---------|
| `CorrectnessTests` | **Yes** | Validates functional correctness against the reference kernel |
| `SpeedTests` | No | Compares cycle counts to existing benchmarks |

**Commands:**
- Correctness: `pytest tests/submission_tests.py::CorrectnessTests -v`
- Performance: `pytest tests/submission_tests.py::SpeedTests -v`

**SpeedTests interpretation:**
- SpeedTests compare your implementation's cycle counts against established benchmark targets.
- A "failing" SpeedTest does **not** indicate a regression if cycles improved from the prior implementation—it simply means the benchmark target has not yet been reached.
- Even if cycle counts are lower than before your changes, the solution is still an improvement over the previous state.

### For Code Implementation Agents
| Gate | Tool | Pass Criteria |
|------|------|---------------|
| Import sorting | `isort --check` | No changes needed |
| Formatting | `black --check` | No changes needed |
| Linting | `flake8` | Zero errors |
| Type checking | `mypy` | Zero errors |

### For Test Implementation Agents
| Gate | Tool | Pass Criteria |
|------|------|---------------|
| Import sorting | `isort --check` on test files | No changes needed |
| Formatting | `black --check` on test files | No changes needed |
| Linting | `flake8` on test files | Zero errors |
| Coverage | Coverage measurement | Meet project thresholds |

### For Documentation Agents
| Gate | Tool | Pass Criteria |
|------|------|---------------|
| Docstring style | `pydocstyle --convention=numpy` | All checks pass |
| Docstring coverage | API coverage check | 100% public API coverage |
| Accuracy | Cross-reference with code | No stale docs |

### For Critic Agents
| Gate | Tool | Pass Criteria |
|------|------|---------------|
| Review complete | Structured review output | All areas assessed |
| Evidence checked | Gate verification | Implementer gates verified |

### Lint / type-check gate (when configured)

- Use `.github/skills/python-linting/SKILL.md` for the canonical commands.
- Prefer `pre-commit run --all-files` when available; otherwise run the tools directly.
- Keep outputs small: redirect verbose logs to a file and summarize.

### Documentation checks (only if configured)

- Use `.github/skills/python-docs-covering/SKILL.md` for guidance.
- Do not introduce a new docs-coverage threshold unless it is explicitly configured in the repo.

---

## 4) Branch & Patch Conventions

### Branch Naming Convention

Format: `agent/<agent-name>/<phase-or-step-id>-cycle-<N>`

**Examples:**
- Planning + research: `agent/planner/PLAN-cycle-1`
- Plan review: `agent/plan-critic/PLAN-cycle-1`
- Implementation: `agent/ml-expert/P01-cycle-1`
- Code review: `agent/ml-critic/P01-cycle-1`

### Patch Storage

By default, patches and logs are stored under `.github/agent-state/`:

- Patches: `.github/agent-state/patches/<timestamp>-<agent>.patch`
- Logs / workspace state snapshots: `.github/agent-state/subagents/`

### Patch Handling

- Patches are derived from a **directory-state diff** (workspace snapshot **before** → **after**) produced by the Copilot CLI wrapper.
- Treat patches as the review unit: apply only when the cycle verdict permits (`PASS` / `SOFT_FAIL`), and never apply on `HARD_FAIL`.

---

## 5) Global Notes

- Never invent missing content; label unknowns as `(missing)` / `(to be confirmed)`.
- The guardrails in this document are intended to keep work deterministic and reviewable while preserving the repository's testing contract.

---

## References

- Repo top-level contract: `.github/copilot-instructions.md`
