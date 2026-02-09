# Copilot CLI Subagent Runner Skill

This skill defines how to run the repository's Copilot CLI subagents safely and reproducibly via `.github/skills/copilot-cli-subagent-running/scripts/run-subagent.sh`.

**Important update:** `run-subagent.sh` now runs the agent directly in the **current workspace** (repo root by default, or `--workdir <path>`) and produces a patch from a **directory-state diff**:

1. Snapshot workspace directory state (**before**) the agent run
2. Run the Copilot CLI agent in the workspace
3. Snapshot workspace directory state (**after**) the agent run
4. Write a patch from **before -> after** (binary-safe)

The wrapper also writes a small state file at `.github/agent-state/subagents/<timestamp>-<agent>.workspace-state.txt` that records `base_commit`, `before_tree`, and `after_tree` used for patch generation. The state file is written **after** the patch is generated, so it never contaminates the before/after diff.

**Repo contract:** `.github/copilot-instructions.md` is the top-level contract for how work is done in this repo. This skill must stay consistent with it and should **not** duplicate repository rules or architecture theory--reference `VLIW.md` instead.

---

## When to use this skill

Use this skill whenever workflow/orchestration needs to run any registered subagent (for example: `planner`, `memory-opt-expert`, `simd-vect-critic`, `project-manager`).

Agent IDs and default models are defined in `.github/prompts/agents.prompt.md`.

---

## Hard rules

1. **Always invoke via the wrapper script**: `.github/skills/copilot-cli-subagent-running/scripts/run-subagent.sh`
   Never call the raw `copilot ...` command directly.
2. **Workspace or sandbox execution**:
   Runs happen in the current workspace by default. Use `--sandbox` for isolation in a git worktree.
3. **Keep outputs small in terminal/chat**:  
   Redirect full stdout/stderr to `.github/agent-state/` and summarize from the log.
4. **Ground truth remains ground truth**:  
   Tests and reference behavior are authoritative; don't change them unless explicitly requested.
5. **Reference, don't duplicate**:  
   Point the agent to `.github/copilot-instructions.md` and `VLIW.md` instead of restating theory.
6. **Include repo contract in context pack**:
   Ensure `.github/copilot-instructions.md` is included via `--context-file` or explicit prompt directive.
   The wrapper also prepends `READ FIRST: .github/copilot-instructions.md` to every run.

**Workspace snapshot invariants (non-negotiable):**

- **Patch contains a directory-state diff.** The wrapper snapshots the workspace before and after the agent run, then diffs those snapshots to produce the patch (commits optional).

---

## Prerequisites

1. **GitHub Copilot Subscription**: Pro, Pro+, Business, or Enterprise
2. **Copilot CLI Installed**: 
   ```bash
   npm install -g @github/copilot
   ```
3. **Authentication**: Must be authenticated via `gh auth login`

---

## Standard invocation (quiet-by-default logging)

Create a log folder once:

```bash
mkdir -p .github/agent-state/subagents
```

Run the agent and capture all output to a log file (recommended default).

By default, the wrapper will also:

- write a patch to `.github/agent-state/patches/<timestamp>-<agent>.patch`

The wrapper prints the patch path at the end of the run.

```bash
ts="$(date -u +"%Y%m%dT%H%M%SZ")"
agent="memory-opt-expert"
log=".github/agent-state/subagents/${ts}-${agent}.log"

.github/skills/copilot-cli-subagent-running/scripts/run-subagent.sh \
  --agent="$agent" \
  --prompt "..." \
  >"$log" 2>&1

echo "log: $log"
```

If you want streaming output while logging, use `tee`:

```bash
.github/skills/copilot-cli-subagent-running/scripts/run-subagent.sh --agent=memory-opt-expert --prompt "..." 2>&1 \
  | tee ".github/agent-state/subagents/${ts}-memory-opt-expert.log"
```

---

## Recommended prompt shape (Context Pack)

Keep the prompt tight and grounded. Point the agent to repo contracts and files instead of restating theory.

```text
TASK:
- What you want the agent to do (one paragraph)

CONTEXT:
- What this repo is / where to look (mention: .github/copilot-instructions.md, VLIW.md, tests/)

CONSTRAINTS:
- "Small diffs", "no verbose logs to terminal", "don't edit tests/", etc.

FILES / LOCATIONS:
- Exact paths the agent should read/modify

OUTPUT FORMAT:
- What you want back (e.g., "propose a minimal patch + rationale", "list of candidate transforms ranked by expected perf impact")
```

For larger context, prefer `--context-file` instead of pasting huge blocks into `--prompt`:

```bash
.github/skills/copilot-cli-subagent-running/scripts/run-subagent.sh \
  --agent=planner \
  --context-file STEP.md \
  --prompt "Propose the minimal kernel changes described in STEP.md"
```

**Context-file path semantics:**
- Relative paths are resolved from the **repo root** (not the caller's CWD).
- Absolute paths must be inside the repo root.
- Path traversal (`..`) is rejected.
- Files larger than `--max-inline-context-bytes` (default 65536) are **not** inlined into the prompt. Instead, the wrapper injects a file-read directive telling the agent to read the file using its tools. This avoids `ARG_MAX` failures with very large context files.

---

## Wrapper script options

| Flag | Purpose | Example |
|------|---------|---------|
| `--prompt <text>` | Task for the agent (required) | `--prompt "Optimize the hash loop"` |
| `--agent <name>` | Custom agent name (must match `^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$`) | `--agent=memory-opt-expert` |
| `--model <model>` | AI model override | `--model claude-sonnet-4` |
| `--workdir <path>` | Working directory inside the repo (and sandbox when enabled) | `--workdir ./src` |
| `--context-file <file>` | Prepend file contents to prompt (resolved from repo root) | `--context-file STEP.md` |
| `--max-inline-context-bytes <N>` | Max context file size to inline in prompt (default: 65536). Larger files use file-reference mode. | `--max-inline-context-bytes 131072` |
| `--tool-policy <policy>` | Tool permission policy: `allowlist` (default) or `legacy-denylist` | `--tool-policy=legacy-denylist` |
| `--allow-all-tools-unsafe` | Shortcut for `--tool-policy=legacy-denylist` (restores old behavior) | |
| `--allow-tool <tool>` | Additional tool to allow (repeatable, merged with policy) | `--allow-tool 'shell(npm run test:*)'` |
| `--deny-tool <tool>` | Deny additional tool (repeatable, applied in all policies) | `--deny-tool 'shell(docker)'` |
| `--allow-urls` | Allow network access | |
| `--allow-paths` | Allow all path access | |
| `--dry-run` | Print command without executing | |
| `--verbose` | Print debug information | |
| `--patch-out <path>` | Patch output path | `--patch-out .github/agent-state/patches/run1.patch` |
| `--sandbox` | Run agent in isolated git worktree | `--sandbox` |
| `--no-cleanup-on-success` | Keep sandbox after success (default: remove) | `--sandbox --no-cleanup-on-success` |
| `--cleanup-on-failure` | Remove sandbox even on failure (default: preserve) | `--sandbox --cleanup-on-failure` |

---

## Sandbox mode

Use `--sandbox` to run the agent in an isolated git worktree instead of the main workspace:

```bash
.github/skills/copilot-cli-subagent-running/scripts/run-subagent.sh \
  --agent=memory-opt-expert \
  --prompt "Reduce LOAD operations" \
  --sandbox
```

**How it works:**

1. `scripts/sandbox-create.sh` creates a git worktree at `.agent-sandboxes/<agent>-<timestamp>/`
2. Agent runs inside the worktree (main workspace is untouched)
   - If `--workdir` is provided, it is resolved relative to the sandbox root.
3. Patch is generated from worktree state diff (same mechanism as non-sandbox mode)
4. `scripts/sandbox-cleanup.sh` removes the worktree on success (configurable)

The agent is trusted to run its own quality gates inside the sandbox.

**Cleanup policy (default):**
- Success → sandbox removed
- Failure → sandbox preserved for debugging at `.agent-sandboxes/<agent>-<timestamp>/`

**Agent tracking:** every run (sandboxed or not) is recorded in `agents.db` at the repo root with columns: `id`, `agent_name`, `agent_path`, `agent_sandbox`, `agent_status`.

**Agent status values:** `pending`, `running`, `completed`, `failed`, `interrupted`.

**Signal handling:** If the wrapper receives SIGINT (Ctrl+C), SIGTERM, or SIGHUP during a run, it performs graceful cleanup:
- Updates the DB row to `interrupted` (instead of leaving it stuck as `running`).
- In sandbox mode, cleans up the worktree.
- Exits with the conventional signal code (130/143/129).

---

## Model selection

`run-subagent.sh` has a default model configured internally (`claude-sonnet-4.5`). Override per run if needed:

```bash
.github/skills/copilot-cli-subagent-running/scripts/run-subagent.sh --agent=planner --model gpt-5 --prompt "..."
```

Availability depends on your Copilot plan / org policy.

---

## Tool permissions and safety

The wrapper uses an **allowlist-based tool policy** by default. Only a conservative set of tools is allowed unless the agent definition specifies its own tool list.

**Default policy: `allowlist`**

The wrapper builds the allowed tool set from:
1. The agent's definition file (`~/.copilot/agents/<agent>.agent.md` or `.github/agents/<agent>.agent.md`), if it contains a tools block.
2. If no agent-specific tools are found, a conservative fallback set: `read`, `search`, `execute`, `edit`, `agent`, `todo`, `web`, `vscode`.

Destructive commands are always denied as defense-in-depth:
- `shell(rm)`, `shell(rm -rf)`, `shell(rmdir)`
- `shell(git push)`, `shell(git push --force)`, `shell(git push -f)`

**Effective tool set:** `(policy_allowlist + --allow-tool flags) - (default_denies + --deny-tool flags)`

**Legacy mode:** Use `--tool-policy=legacy-denylist` or `--allow-all-tools-unsafe` to restore the previous behavior (allow all tools, deny destructive ones only). This is an explicit opt-in for backward compatibility.

Add more restrictions as needed:

```bash
.github/skills/copilot-cli-subagent-running/scripts/run-subagent.sh \
  --agent=memory-opt-expert \
  --deny-tool 'shell(curl)' \
  --deny-tool 'shell(wget)' \
  --prompt "..."
```

Allow URLs only when you explicitly need network access:

```bash
.github/skills/copilot-cli-subagent-running/scripts/run-subagent.sh --agent=memory-opt-expert --allow-urls --prompt "..."
```

---

## Where the agent profile lives

Copilot CLI resolves custom agents from these locations (highest priority first):

1. `~/.copilot/agents/<agent-id>.agent.md`
2. `.github/agents/<agent-id>.agent.md`

Keep the agent description and tool list in the agent profile; keep this file focused on **how to run** the agent safely.

---

## Script architecture

The skill uses a modular script architecture with shared utilities:

### Library files (sourced, not executed directly)

- `scripts/common-utils.sh` - Shared utilities for all scripts:
  - Logging: `log_verbose`, `log_info`, `log_warn`, `log_error`
  - Git utilities: `ensure_in_git_repo`
  - Time utilities: `make_timestamp`, `seconds_to_human`
  - Validation: `check_copilot_installed`, `check_sqlite_installed`
  - SQL helpers: `_param_esc` (escapes values for sqlite3 `.param set`; rejects newlines/CR to prevent injection), `db_exec`, `db_query`

- `scripts/snapshot-utils.sh` - Git directory state management:
  - `snapshot_directory_state` - Creates git tree snapshots for patch generation

### Executable scripts

- `scripts/run-subagent.sh` - Main entry point for running agents
  - Sources both library files
  - Orchestrates agent execution, timeout handling, patch generation
  - Manages database tracking and sandbox lifecycle

- `scripts/sandbox-create.sh` - Creates isolated git worktree
  - Sources `common-utils.sh` for logging
  - Creates worktree at `.agent-sandboxes/<agent>-<timestamp>/`

- `scripts/sandbox-cleanup.sh` - Cleans up sandbox worktree
  - Sources `common-utils.sh` for logging
  - Removes worktree and associated branch

All executable scripts source the library files for consistent behavior.

---

## Output handling and `.github/agent-state/`

Use `.github/agent-state/` as the audit trail:

- Raw subagent logs: `.github/agent-state/subagents/<timestamp>-<agent>.log`
- Workspace state files: `.github/agent-state/subagents/<timestamp>-<agent>.workspace-state.txt`
- Patches: `.github/agent-state/patches/<timestamp>-<agent>.patch`
- Optional short summaries: `.github/agent-state/NOTES.md`

Guideline: store the full output in the log, and only a short, high-signal summary elsewhere.

---

## Timeout behavior

`run-subagent.sh` enforces a **hard max runtime of 1 hour** per invocation.

- If the command produces no output for a while, **do not assume it failed**--just wait for completion.
- If the run exceeds 1 hour, the wrapper terminates it and exits with code **124**.

---

## Troubleshooting

| Error | Cause | Solution |
|-------|-------|----------|
| `GitHub Copilot CLI is not installed` | CLI missing | Install and ensure `copilot` is on PATH |
| `sqlite3 is required for agent run tracking` | `sqlite3` missing | Install sqlite3 and rerun |
| `Authentication failed` | Token/auth issue | Re-authenticate with `gh auth login` |
| `Tool denied` | Missing permission | Add `--allow-tool ...`, adjust deny patterns, or use `--allow-all-tools-unsafe` |
| `Invalid --agent value` | Agent name has invalid characters | Use alphanumeric, dot, hyphen, underscore only (max 64 chars, must start alphanumeric) |
| `Missing value for --prompt (next argument looks like a flag)` | Flag used as value | Use `--prompt="--value"` form for values starting with `--` |
| `Context file not found (resolved from repo root)` | Relative path not found from repo root | Paths are resolved from repo root, not CWD |
| `Context file exceeds ... bytes` | Large context file | Normal operation; file-reference mode is used instead of inlining |
| `_param_esc: value contains newline` | Newline in a DB parameter | Agent name or other parameter has invalid newline/CR character |
| `124` exit code | Timeout | Reduce scope or split the task |

---

## Exit codes

| Code | Meaning |
|------|---------|
| `0` | Success |
| `124` | Timed out (1-hour hard limit) |
| `129` | Interrupted by SIGHUP |
| `130` | Interrupted by SIGINT (Ctrl+C) |
| `143` | Interrupted by SIGTERM |
| Other | Propagated from underlying `copilot` command |

---

## Keep this skill consistent

If this repo's contracts change, update this file to remain consistent with:

- `.github/copilot-instructions.md` (top-level work contract)
- `scripts/run-subagent.sh` (actual wrapper behavior)
- `scripts/sandbox-create.sh` / `scripts/sandbox-cleanup.sh` (sandbox lifecycle)
