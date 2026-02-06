# Agents Registry

This file is the single source of truth for the project's **agent roster**:

- which agents exist (only `*.agent.md`)
- which model each agent should run with by default
- where the agent definition file lives in the repo

Higher-level workflows/orchestration prompts should **reference this file** so model and roster changes happen in one place.

## Column meanings

- **Agent ID**: stable identifier used when invoking an agent.
- **Default model**: model to use unless overridden.
- **Agent file (repo path)**: must end with `*.agent.md`.

## Registry table

| Agent ID | Default model | Agent file (repo path) |
|---|---|---|
| `planner` | `gpt-5.2` | `.github/agents/planner.agent.md` |
| `plan-critic` | `claude-opus-4.5` | `.github/agents/plan-critic.agent.md` |
| `ilp-schedule-expert` | `gpt-5.2-codex` | `.github/agents/ilp-schedule-expert.agent.md` |
| `ilp-schedule-critic` | `claude-sonnet-4.5` | `.github/agents/ilp-schedule-critic.agent.md` |
| `simd-vect-expert` | `gpt-5.2-codex` | `.github/agents/simd-vect-expert.agent.md` |
| `simd-vect-critic` | `claude-sonnet-4.5` | `.github/agents/simd-vect-critic.agent.md` |
| `memory-opt-expert` | `gpt-5.2-codex` | `.github/agents/memory-opt-expert.agent.md` |
| `memory-opt-critic` | `claude-sonnet-4.5` | `.github/agents/memory-opt-critic.agent.md` |
| `control-flow-expert` | `gpt-5.2-codex` | `.github/agents/control-flow-expert.agent.md` |
| `control-flow-critic` | `claude-sonnet-4.5` | `.github/agents/control-flow-critic.agent.md` |
| `docs-expert` | `gpt-5.2` | `.github/agents/docs-expert.agent.md` |
| `docs-critic` | `claude-sonnet-4.5` | `.github/agents/docs-critic.agent.md` |
| `pipeline-runner` | `default` | `.github/agents/pipeline-runner.agent.md` |
| `project-manager` | `default` | `.github/agents/project-manager.agent.md` |
