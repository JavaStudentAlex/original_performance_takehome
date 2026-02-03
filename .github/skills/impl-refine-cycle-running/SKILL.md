---
name: impl-refine-cycle-running
description: Single-pass implementation loop runner: invoke implementer and critic, record deterministic per-cycle artifacts under `.github/agent-state/cycles/<STEP_ID>/`, select the correct patch source, and enforce "no patch on HARD_FAIL" before stopping after one cycle.
---

# Skill: impl-refine-cycle-running

Run a single implementation refinement cycle (implementer pass, critic pass, patch decision).

---

## Purpose

This skill orchestrates **one forward pass** of an implementation refinement cycle:

1. **Implementer pass** - A service agent applies changes in an isolated workspace and commits them
2. **Critic pass** - A reviewer evaluates the result and renders a verdict
3. **Patch decision** - Apply changes to main workspace or keep artifacts for debugging

This skill is a reusable unit. It does not define agent rosters, model assignments, or multi-cycle loops. Those are the caller's responsibility.

---

## Dependencies

This skill delegates mechanics to existing skills:

| Dependency | Path | Purpose |
|------------|------|---------|
| Agent invocation | `.github/skills/copilot-cli-subagent-running/SKILL.md` | Invoke agents with correct models |

Read and follow that skill for implementation details. Do not duplicate its commands here.

---

## Inputs

The caller must provide these values:

| Input | Required | Description |
|-------|----------|-------------|
| `STEP_ID` | Yes | Current step identifier (e.g., `P01`) |
| `CYCLE_NUM` | Yes | Cycle number (integer, e.g., `1`) |
| `IMPLEMENTER_ID` | Yes | Identifier for the implementer agent |
| `CRITIC_ID` | Yes | Identifier for the critic agent |
| `MICRO_TASK` | Yes | Concrete task for this cycle |
| `DEFINITION_OF_DONE` | Yes | Checklist the implementer must satisfy |
| `PREV_CRITIQUE` | No | Critique from previous cycle, or `(none)` |
| `STATE_BASE_DIR` | No | Output directory (default: `.github/agent-state/cycles/<STEP_ID>/`) |
| `CRITIC_CAN_EDIT` | No | If `true`, critic may apply minimal fixes (default: `false`) |
| `PATCH_SOURCE_POLICY` | No | Policy for selecting patch source (default: `prefer_critic_if_commits_else_implementer`) |

---

## Outputs

Written to `STATE_BASE_DIR`:

| File | Content |
|------|---------|
| `cycle-<NN>-service.md` | SERVICE_RESULT from implementer |
| `cycle-<NN>-critic.md` | CRITIC_RESULT with verdict |

---

## Procedure

### Step 1: Implementer pass

Invoke the implementer using `.github/skills/copilot-cli-subagent-running/SKILL.md`.

**Work packet must include:**
- `MICRO_TASK`
- `DEFINITION_OF_DONE`
- `PREV_CRITIQUE` (if any)
- Relevant code pointers or snippets

**Implementer requirements:**
- Apply the required changes
- Commit all intended changes
- Run applicable quality gates
- Report evidence (commands and outcomes), not guesses

Persist output as `cycle-<NN>-service.md` using the SERVICE_RESULT template.

### Step 2: Critic pass

Invoke the critic using `.github/skills/copilot-cli-subagent-running/SKILL.md`.

**Default behavior:** Critic reviews and produces findings plus verdict, without edits.

**If `CRITIC_CAN_EDIT=true`:** Caller permits minimal fixes. Edits must be:
- Minimal and scoped to blockers
- Committed by the critic
- Documented in CRITIC_RESULT

Persist output as `cycle-<NN>-critic.md` using the CRITIC_RESULT template.

### Step 3: Determine verdict and patch source

**Verdicts:**

| Verdict | Meaning | Action |
|---------|---------|--------|
| `PASS` | Acceptable | Apply patch |
| `SOFT_FAIL` | Acceptable with nits | Apply patch |
| `HARD_FAIL` | Blockers present | Do not apply patch |

**Patch source selection (default policy):**
- If critic produced commits: patch from critic
- Else: patch from implementer

Then:
1. Generate a patch from the chosen source (per the invocation skill's directory-state diff mechanism)
2. Apply the patch to the main workspace (uncommitted)

Record (at minimum) in `cycle-<NN>-critic.md` under `Patch Recommendation`:
- Patch source (implementer or critic)
- Patch file path
- Apply status

### Step 4: Stop

This skill ends after one implementer+critic forward pass.

Looping (running cycle 2, 3, ...) is the caller's responsibility.

---

## Templates

### SERVICE_RESULT

File: `cycle-<NN>-service.md`

```markdown
# SERVICE_RESULT

- Step: <STEP_ID>
- Cycle: <CYCLE_NUM>
- Agent: <IMPLEMENTER_ID>

## Summary

<1-5 bullets describing what changed and why>

## Changes

- Files changed:
  - <path>
- Key symbols/contracts touched:
  - <module:function/class>

## Validation Evidence

- Gates/commands run:
  - `<command>` -> <PASS/FAIL + notes>
- Notes:
  - <performance, determinism, edge cases>

## Open Questions / Risks

- <bullets>

## Handoff to Critic

- Review focus:
  - <bullets>
```

### CRITIC_RESULT

File: `cycle-<NN>-critic.md`

```markdown
# CRITIC_RESULT

- Step: <STEP_ID>
- Cycle: <CYCLE_NUM>
- Agent: <CRITIC_ID>

## Verdict

<PASS | SOFT_FAIL | HARD_FAIL>

## Context Alignment

<Does the result match MICRO_TASK and DoD?>

## Blockers

<location> - <issue> - <minimal fix guidance>

## Non-blocking Suggestions

- <bullets>

## Edits Made (if permitted and applied)

- Commits:
  - <hash> <message>
- Changes:
  - <what was changed and why>

## Patch Recommendation

- Source: <critic | implementer>
- Rationale: <bullets>
```

---

## Guardrails

1. **Evidence required** - Do not claim validation occurred without command output
2. **No patch on HARD_FAIL** - Never apply patches when blockers exist
3. **Scope discipline** - Keep diffs small and step-scoped; avoid refactor drift
4. **Conflict handling** - If patch application conflicts, keep the patch and any underlying logs/diffs and surface details to the caller
5. **Single pass** - This skill runs exactly one cycle; looping is out of scope

---

## References

- `.github/skills/copilot-cli-subagent-running/SKILL.md` - Agent invocation
