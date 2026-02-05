# Copilot CLI Subagent Skill (compilers-expert)

This skill defines how to run the repository's **single** Copilot CLI subagents safely and reproducibly via `.github/skills/copilot-cli-subagent-running/run-subagent.sh`.

**Important update:** `run-subagent.sh` now runs the agent directly in the **current workspace** (repo root by default, or `--workdir <path>`) and produces a patch from a **directory-state diff**:

1. Snapshot workspace directory state (**before**) the agent run
2. Run the Copilot CLI agent in the workspace
3. Snapshot workspace directory state (**after**) the agent run
4. Write a patch from **before -> after** (binary-safe)

The wrapper also writes a small state file at `.github/agent-state/subagents/<timestamp>-<agent>.workspace-state.txt` that records `base_commit`, `before_tree`, and `after_tree` used for patch generation.

**Repo contract:** `.github/copilot-instructions.md` is the top-level contract for how work is done in this repo. This skill must stay consistent with it and should **not** duplicate repository rules or architecture theory--reference `VLIW.md` instead.

---

## When to use this skill

Use `compilers-expert` when you want a focused pass on compiler-style optimization work:

- Static scheduling / bundling for the VLIW target
- Memory-traffic reduction and latency hiding (loads as the bottleneck)
- SIMD vectorization / if-conversion guidance
- Trace-driven debugging and optimization ideas

If you just need edits, formatting, or non-compiler work, do **not** spawn the agent.

---

## Hard rules

1. **Always invoke via the wrapper script**: `.github/skills/copilot-cli-subagent-running/run-subagent.sh`  
   Never call the raw `copilot ...` command directly.
2. **Workspace execution**:  
   Runs happen in the current workspace. If you need isolation, run from a clean branch or a clean clone.
3. **Keep outputs small in terminal/chat**:  
   Redirect full stdout/stderr to `.github/agent-state/` and summarize from the log.
4. **Ground truth remains ground truth**:  
   Tests and reference behavior are authoritative; don't change them unless explicitly requested.
5. **Reference, don't duplicate**:  
   Point the agent to `.github/copilot-instructions.md` and `VLIW.md` instead of restating theory.

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
log=".github/agent-state/subagents/${ts}-compilers-expert.log"

.github/skills/copilot-cli-subagent-running/run-subagent.sh \
  --agent=compilers-expert \
  --prompt "..." \
  >"$log" 2>&1

echo "log: $log"
```

If you want streaming output while logging, use `tee`:

```bash
.github/skills/copilot-cli-subagent-running/run-subagent.sh --agent=compilers-expert --prompt "..." 2>&1 \
  | tee ".github/agent-state/subagents/${ts}-compilers-expert.log"
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
.github/skills/copilot-cli-subagent-running/run-subagent.sh \
  --agent=compilers-expert \
  --context-file STEP.md \
  --prompt "Propose the minimal kernel changes described in STEP.md"
```

---

## Wrapper script options

| Flag | Purpose | Example |
|------|---------|---------|
| `--prompt <text>` | Task for the agent (required) | `--prompt "Optimize the hash loop"` |
| `--agent <name>` | Custom agent name | `--agent=compilers-expert` |
| `--model <model>` | AI model override | `--model claude-sonnet-4` |
| `--workdir <path>` | Working directory inside the repo | `--workdir ./src` |
| `--context-file <file>` | Prepend file contents to prompt | `--context-file STEP.md` |
| `--allow-tool <tool>` | Allow additional tool (repeatable) | `--allow-tool 'shell(npm run test:*)'` |
| `--deny-tool <tool>` | Deny additional tool (repeatable) | `--deny-tool 'shell(docker)'` |
| `--allow-urls` | Allow network access | |
| `--allow-paths` | Allow all path access | |
| `--dry-run` | Print command without executing | |
| `--verbose` | Print debug information | |
| `--patch-out <path>` | Patch output path | `--patch-out .github/agent-state/patches/run1.patch` |

---

## Model selection

`run-subagent.sh` has a default model configured internally (`claude-sonnet-4.5`). Override per run if needed:

```bash
.github/skills/copilot-cli-subagent-running/run-subagent.sh --agent=compilers-expert --model gpt-5 --prompt "..."
```

Availability depends on your Copilot plan / org policy.

---

## Tool permissions and safety

The wrapper runs with broad tool access but **denies destructive commands by default**:

- `shell(rm)`, `shell(rm -rf)`, `shell(rmdir)`
- `shell(git push)`, `shell(git push --force)`, `shell(git push -f)`

Add more restrictions as needed:

```bash
.github/skills/copilot-cli-subagent-running/run-subagent.sh \
  --agent=compilers-expert \
  --deny-tool 'shell(curl)' \
  --deny-tool 'shell(wget)' \
  --prompt "..."
```

Allow URLs only when you explicitly need network access:

```bash
.github/skills/copilot-cli-subagent-running/run-subagent.sh --agent=compilers-expert --allow-urls --prompt "..."
```

---

## Where the agent profile lives

Copilot CLI resolves custom agents from these locations (highest priority first):

1. `~/.copilot/agents/compilers-expert.agent.md`
2. `.github/agents/compilers-expert.agent.md`

Keep the agent description and tool list in the agent profile; keep this file focused on **how to run** the agent safely.

---

## Output handling and `.github/agent-state/`

Use `.github/agent-state/` as the audit trail:

- Raw subagent logs: `.github/agent-state/subagents/<timestamp>-compilers-expert.log`
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
| `Authentication failed` | Token/auth issue | Re-authenticate with `gh auth login` |
| `Tool denied` | Missing permission | Add `--allow-tool ...` or adjust deny patterns |
| `124` exit code | Timeout | Reduce scope or split the task |

---

## Exit codes

| Code | Meaning |
|------|---------|
| `0` | Success |
| `124` | Timed out (1-hour hard limit) |
| Other | Propagated from underlying `copilot` command |

---

## Keep this skill consistent

If this repo's contracts change, update this file to remain consistent with:

- `.github/copilot-instructions.md` (top-level work contract)
- `run-subagent.sh` (actual wrapper behavior)
