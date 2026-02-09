#!/usr/bin/env bash
# run-subagent.sh - Wrapper script for running Copilot CLI subagents safely and reproducibly
#
# This script runs the Copilot CLI agent directly in the current workspace
# (repo root by default, or --workdir <path>) and produces a patch of the
# directory-state diff (before/after snapshots; commits optional).
#
# Use --sandbox to run the agent in an isolated git worktree instead.
#
# Usage:
#   ./run-subagent.sh --agent=<agent-name> --prompt "<prompt>"
#
# Examples:
#   ./run-subagent.sh --agent=memory-opt-expert --prompt "Reduce LOAD pressure in traversal"
#   ./run-subagent.sh --agent=docs-expert --workdir .github --prompt "Review workflow docs"
#   ./run-subagent.sh --agent=planner --context-file STEP.md --prompt "Follow STEP.md"
#   ./run-subagent.sh --agent=memory-opt-expert --prompt "Optimize" --sandbox
#
# Note:
#   This wrapper always writes a patch capturing the workspace changes made
#   during the run.

set -euo pipefail

# ==============================================================================
# Configuration
# ==============================================================================

# Directory containing this script (used to locate sandbox helper scripts)
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared utilities
source "$SCRIPTS_DIR/common-utils.sh"
source "$SCRIPTS_DIR/snapshot-utils.sh"

# Max runtime for a single subagent invocation.
# Default is 1 hour (3600s). If exceeded, the job is terminated and the wrapper
# exits non-zero (124 on timeout).
MAX_RUNTIME_SECONDS=3600

# After sending SIGTERM on timeout, wait this long (in seconds) before SIGKILL.
KILL_AFTER_SECONDS=30

# Default model (can be overridden)
DEFAULT_MODEL="claude-sonnet-4.5"

# Default denied tools (safety-first, best-effort denylist).
# Effectiveness depends on Copilot CLI's tool-matching semantics.
# The sandbox and workflow constraints are the primary safety layers.
DENIED_TOOLS=(
    "shell(rm)"
    "shell(rm -rf)"
    "shell(rm -r)"
    "shell(rm -f)"
    "shell(rmdir)"
    "shell(/bin/rm)"
    "shell(/usr/bin/rm)"
    "shell(git push)"
    "shell(git push --force)"
    "shell(git push -f)"
    "shell(git push --force-with-lease)"
)

# ==============================================================================
# Helper Functions
# ==============================================================================

print_usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Note:
    This wrapper enforces a hard max runtime of 1 hour per invocation.

Required:
    --prompt <prompt>           The prompt/task for the agent

Optional:
    --agent <name>              Custom agent name (from .github/agents/ or ~/.copilot/agents/)
    --model <model>             AI model override (default: $DEFAULT_MODEL)
    --workdir <path>            Working directory inside the repo
    --context-file <file>       File containing additional context to prepend to prompt
    --allow-tool <tool>         Additional tool to allow (repeatable)
    --deny-tool <tool>          Additional tool to deny (repeatable)
    --allow-urls                Allow network access (--allow-all-urls)
    --allow-paths               Allow all path access (--allow-all-paths)
    --dry-run                   Print actions/command without executing
    --verbose                   Print debug information

Sandbox mode (--sandbox):
    --sandbox                   Run agent in an isolated git worktree sandbox
    --no-cleanup-on-success     Keep sandbox after successful run (default: clean up)
    --cleanup-on-failure        Remove sandbox even on failure (default: preserve for debug)

Output:
    --patch-out <path>          Where to write the patch (default: .github/agent-state/patches/<ts>-<agent>.patch)

Examples:
    $(basename "$0") --agent=memory-opt-expert --prompt "Reduce LOAD pressure in the hot loop"
    $(basename "$0") --agent=simd-vect-expert --model gpt-5 --prompt "Vectorize the hash stage"
    $(basename "$0") --agent=planner --workdir ./src --prompt "Analyze this module"
    $(basename "$0") --prompt "Refactor this" --context-file STEP.md
    $(basename "$0") --agent=memory-opt-expert --prompt "Optimize" --sandbox

Tool Permission Examples:
    $(basename "$0") --prompt "..." --allow-tool 'shell(npm run test:*)'
    $(basename "$0") --prompt "..." --deny-tool 'shell(docker)'
EOF
}

run_with_timeout() {
    local -a cmd=("$@")

    if command -v timeout &> /dev/null; then
        timeout --foreground --signal=TERM --kill-after="${KILL_AFTER_SECONDS}s" "${MAX_RUNTIME_SECONDS}s" "${cmd[@]}"
        return $?
    fi

    "${cmd[@]}" &
    local pid=$!
    local start=$SECONDS

    while kill -0 "$pid" 2>/dev/null; do
        local elapsed=$((SECONDS - start))
        if (( elapsed >= MAX_RUNTIME_SECONDS )); then
            log_error "Subagent exceeded max runtime (${MAX_RUNTIME_SECONDS}s). Terminating (pid=$pid)..."
            kill -TERM "$pid" 2>/dev/null || true

            local waited=0
            while kill -0 "$pid" 2>/dev/null && (( waited < KILL_AFTER_SECONDS )); do
                sleep 1
                waited=$((waited + 1))
            done

            if kill -0 "$pid" 2>/dev/null; then
                log_error "Subagent still running after SIGTERM. Sending SIGKILL..."
                kill -KILL "$pid" 2>/dev/null || true
            fi

            wait "$pid" 2>/dev/null || true
            return 124
        fi
        sleep 2
    done

    wait "$pid"
}

# ==============================================================================
# Argument Parsing
# ==============================================================================

PROMPT=""
AGENT=""
MODEL="$DEFAULT_MODEL"
WORKDIR=""
CONTEXT_FILE=""
EXTRA_ALLOW_TOOLS=()
EXTRA_DENY_TOOLS=()
ALLOW_URLS="false"
ALLOW_PATHS="false"
DRY_RUN="false"
VERBOSE="false"
PATCH_OUT=""
USE_SANDBOX="false"
SANDBOX_CLEANUP_ON_SUCCESS="true"
SANDBOX_CLEANUP_ON_FAILURE="false"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --prompt)
            PROMPT="$2"; shift 2 ;;
        --prompt=*)
            PROMPT="${1#*=}"; shift ;;
        --agent)
            AGENT="$2"; shift 2 ;;
        --agent=*)
            AGENT="${1#*=}"; shift ;;
        --model)
            MODEL="$2"; shift 2 ;;
        --model=*)
            MODEL="${1#*=}"; shift ;;
        --workdir)
            WORKDIR="$2"; shift 2 ;;
        --workdir=*)
            WORKDIR="${1#*=}"; shift ;;
        --context-file)
            CONTEXT_FILE="$2"; shift 2 ;;
        --context-file=*)
            CONTEXT_FILE="${1#*=}"; shift ;;
        --allow-tool)
            EXTRA_ALLOW_TOOLS+=("$2"); shift 2 ;;
        --allow-tool=*)
            EXTRA_ALLOW_TOOLS+=("${1#*=}"); shift ;;
        --deny-tool)
            EXTRA_DENY_TOOLS+=("$2"); shift 2 ;;
        --deny-tool=*)
            EXTRA_DENY_TOOLS+=("${1#*=}"); shift ;;
        --allow-urls)
            ALLOW_URLS="true"; shift ;;
        --allow-paths)
            ALLOW_PATHS="true"; shift ;;
        --dry-run)
            DRY_RUN="true"; shift ;;
        --verbose)
            VERBOSE="true"; shift ;;
        --patch-out)
            PATCH_OUT="$2"; shift 2 ;;
        --patch-out=*)
            PATCH_OUT="${1#*=}"; shift ;;
        --sandbox)
            USE_SANDBOX="true"; shift ;;
        --no-cleanup-on-success)
            SANDBOX_CLEANUP_ON_SUCCESS="false"; shift ;;
        --cleanup-on-failure)
            SANDBOX_CLEANUP_ON_FAILURE="true"; shift ;;
        --help|-h)
            print_usage; exit 0 ;;
        *)
            log_error "Unknown option: $1"; print_usage; exit 1 ;;
    esac
done

# ==============================================================================
# Validation
# ==============================================================================

if [[ -z "$PROMPT" ]]; then
    log_error "Missing required --prompt argument"
    print_usage
    exit 1
fi

ensure_in_git_repo
if [[ "$DRY_RUN" != "true" ]]; then
    check_copilot_installed
    check_sqlite_installed
fi

if [[ -n "$CONTEXT_FILE" ]] && [[ ! -f "$CONTEXT_FILE" ]]; then
    log_error "Context file not found: $CONTEXT_FILE"
    exit 1
fi

if [[ -n "$WORKDIR" ]]; then
    # WORKDIR is interpreted relative to repo root.
    # Absolute paths and path traversal are not allowed.
    if [[ "$WORKDIR" = /* ]]; then
        log_error "--workdir must be a relative path"
        exit 1
    fi
    # Reject paths containing ".." to prevent directory traversal
    case "$WORKDIR" in
        ..|../*|*/..|*/../*)
            log_error "--workdir must not contain '..' (path traversal)"
            exit 1
            ;;
    esac
fi

if [[ "$USE_SANDBOX" == "true" ]]; then
    for helper in sandbox-create.sh sandbox-cleanup.sh; do
        if [[ ! -x "$SCRIPTS_DIR/$helper" ]]; then
            log_error "Sandbox helper not found or not executable: $SCRIPTS_DIR/$helper"
            exit 1
        fi
    done
fi

# ==============================================================================
# Build Copilot CLI Command
# ==============================================================================

CMD=(copilot)
CMD+=(--model "$MODEL")

if [[ -n "$AGENT" ]]; then
    CMD+=(--agent="$AGENT")
fi

CMD+=(--allow-all-tools)

for tool in "${DENIED_TOOLS[@]}"; do
    CMD+=(--deny-tool "$tool")
done
for tool in "${EXTRA_DENY_TOOLS[@]}"; do
    CMD+=(--deny-tool "$tool")
done
for tool in "${EXTRA_ALLOW_TOOLS[@]}"; do
    CMD+=(--allow-tool "$tool")
done

if [[ "$ALLOW_URLS" == "true" ]]; then
    CMD+=(--allow-all-urls)
fi
if [[ "$ALLOW_PATHS" == "true" ]]; then
    CMD+=(--allow-all-paths)
fi

CONTRACT_DIRECTIVE="READ FIRST: .github/copilot-instructions.md"
FULL_PROMPT="$CONTRACT_DIRECTIVE

$PROMPT"
if [[ -n "$CONTEXT_FILE" ]]; then
    CONTEXT_CONTENT=$(cat "$CONTEXT_FILE")
    FULL_PROMPT="$CONTRACT_DIRECTIVE

CONTEXT FROM FILE ($CONTEXT_FILE):
---
$CONTEXT_CONTENT
---

TASK:
$PROMPT"
fi

CMD+=(-p "$FULL_PROMPT")

# ==============================================================================
# Execute
# ==============================================================================

TIMEOUT_HUMAN="$(seconds_to_human "$MAX_RUNTIME_SECONDS")"
AGENT_FOR_NAMES="${AGENT:-auto}"
TS="$(make_timestamp)"

PROJECT_ROOT="$(git rev-parse --show-toplevel)"

if [[ -z "$PATCH_OUT" ]]; then
    PATCH_OUT="$PROJECT_ROOT/.github/agent-state/patches/${TS}-${AGENT_FOR_NAMES}.patch"
elif [[ "$PATCH_OUT" != /* ]]; then
    PATCH_OUT="$PROJECT_ROOT/$PATCH_OUT"
fi

log_verbose "Model: $MODEL"
log_verbose "Agent: ${AGENT:-<auto>}"
log_verbose "Denied tools: ${DENIED_TOOLS[*]} ${EXTRA_DENY_TOOLS[*]:-}"
log_verbose "Extra allowed tools: ${EXTRA_ALLOW_TOOLS[*]:-<none>}"
log_verbose "Max runtime: $TIMEOUT_HUMAN"
log_verbose "Working directory: ${WORKDIR:-.}"
log_verbose "Sandbox mode: $USE_SANDBOX"

if [[ "$DRY_RUN" == "true" ]]; then
    WORKDIR_FOR_RUN="${WORKDIR:-.}"
    if [[ "$WORKDIR_FOR_RUN" == "./" ]]; then
        WORKDIR_FOR_RUN="."
    fi
    echo "DRY RUN - Would execute:" >&2
    if [[ "$USE_SANDBOX" == "true" ]]; then
        SANDBOX_WORKDIR="${WORKDIR_FOR_RUN#./}"
        if [[ "$SANDBOX_WORKDIR" == "." ]]; then
            echo "  cd <sandbox-root> && ${CMD[*]}" >&2
        else
            echo "  cd <sandbox-root>/$SANDBOX_WORKDIR && ${CMD[*]}" >&2
        fi
    else
        echo "  cd $WORKDIR_FOR_RUN && ${CMD[*]}" >&2
    fi
    echo "  write patch (state diff): $PATCH_OUT" >&2
    [[ "$USE_SANDBOX" == "true" ]] && echo "  sandbox: create worktree, run agent inside it" >&2
    exit 0
fi

# Initialize SQLite database for agent tracking
DB_FILE="$PROJECT_ROOT/agents.db"
db_exec "$DB_FILE" "CREATE TABLE IF NOT EXISTS agents (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    agent_name TEXT NOT NULL,
    agent_path TEXT,
    agent_sandbox TEXT,
    agent_status TEXT NOT NULL DEFAULT 'pending'
);"

# Resolve agent definition path
AGENT_PATH=""
if [[ -n "$AGENT" ]] && [[ -f "$PROJECT_ROOT/.github/agents/${AGENT}.agent.md" ]]; then
    AGENT_PATH=".github/agents/${AGENT}.agent.md"
fi

# Create sandbox if requested
SANDBOX_DIR=""
if [[ "$USE_SANDBOX" == "true" ]]; then
    log_info "Creating sandbox for agent: $AGENT_FOR_NAMES"
    sandbox_output=$("$SCRIPTS_DIR/sandbox-create.sh" "$AGENT_FOR_NAMES")
    SANDBOX_DIR=$(printf '%s\n' "$sandbox_output" | grep '^SANDBOX_DIR=' | cut -d= -f2-)
    if [[ -z "$SANDBOX_DIR" ]]; then
        log_error "Failed to create sandbox (could not parse SANDBOX_DIR)"
        exit 1
    fi
    log_info "Sandbox created: $SANDBOX_DIR"
fi

# Record agent run in database
ROW_ID=$(db_query "$DB_FILE" \
    "INSERT INTO agents (agent_name, agent_path, agent_sandbox, agent_status)
     VALUES (?1, ?2, ?3, 'running');
     SELECT last_insert_rowid();" \
    "$AGENT_FOR_NAMES" "$AGENT_PATH" "$SANDBOX_DIR")

# Validate ROW_ID is numeric
if ! [[ "$ROW_ID" =~ ^[0-9]+$ ]]; then
    log_error "Failed to record agent run in database (got: $ROW_ID)"
    exit 1
fi
log_verbose "Agent run recorded in agents.db (id=$ROW_ID)"

exit_code=0
base_commit="$(git -C "$PROJECT_ROOT" rev-parse HEAD)"

# In sandbox mode, snapshot and run from the worktree; otherwise use main workspace
SNAPSHOT_ROOT="$PROJECT_ROOT"
if [[ "$USE_SANDBOX" == "true" ]] && [[ -n "$SANDBOX_DIR" ]]; then
    SNAPSHOT_ROOT="$SANDBOX_DIR"
fi

# Snapshot directory state before the run (baseline for patch generation).
# Note: creates git tree objects that become dangling after the diff.
# These are cleaned up by periodic `git gc` (automatic on most systems).
STATE_OUT="$PROJECT_ROOT/.github/agent-state/subagents/${TS}-${AGENT_FOR_NAMES}.workspace-state.txt"
mkdir -p "$(dirname "$STATE_OUT")"
before_tree="$(snapshot_directory_state "$SNAPSHOT_ROOT")" || {
    log_error "Failed to snapshot directory state before run"
    db_exec "$DB_FILE" "UPDATE agents SET agent_status='failed' WHERE id=?1;" "$ROW_ID"
    exit 1
}
{
    echo "base_commit=$base_commit"
    echo "before_tree=$before_tree"
} > "$STATE_OUT"

# Determine run directory
run_dir="$SNAPSHOT_ROOT"
if [[ -n "$WORKDIR" ]]; then
    run_dir="$SNAPSHOT_ROOT/${WORKDIR#./}"
    if [[ ! -d "$run_dir" ]]; then
        log_error "Working directory not found: $WORKDIR"
        db_exec "$DB_FILE" "UPDATE agents SET agent_status='failed' WHERE id=?1;" "$ROW_ID"
        exit 1
    fi
fi

if [[ "$USE_SANDBOX" == "true" ]]; then
    log_info "Running subagent in sandbox..."
else
    log_info "Running subagent in workspace..."
fi
log_verbose "Run directory: $run_dir"

pushd "$run_dir" >/dev/null
run_with_timeout "${CMD[@]}" || exit_code=$?
popd >/dev/null

if [[ "$exit_code" -eq 124 ]]; then
    log_error "Subagent run timed out after $TIMEOUT_HUMAN"
fi

after_tree="$(snapshot_directory_state "$SNAPSHOT_ROOT")" || {
    log_error "Failed to snapshot directory state after run"
    db_exec "$DB_FILE" "UPDATE agents SET agent_status='failed' WHERE id=?1;" "$ROW_ID"
    exit 1
}
echo "after_tree=$after_tree" >> "$STATE_OUT"

if [[ "$before_tree" == "$after_tree" ]]; then
    log_info "No directory changes detected between snapshots."
else
    log_info "Directory changes detected between snapshots."
fi

# Patch creation (workspace state diff)
mkdir -p "$(dirname "$PATCH_OUT")"

log_info "Writing patch (workspace state diff): $PATCH_OUT"
if ! git -C "$SNAPSHOT_ROOT" diff --binary --no-color "$before_tree" "$after_tree" > "$PATCH_OUT" 2>/dev/null; then
    log_error "Patch generation failed (git diff returned non-zero). Trees: before=$before_tree after=$after_tree"
    # Still continue — patch is best-effort, agent status is what matters
fi

if [[ ! -s "$PATCH_OUT" ]]; then
    log_warn "Patch is empty. The agent may not have changed any files."
fi

# Update agent status in database
if [[ "$exit_code" -eq 0 ]]; then
    db_exec "$DB_FILE" "UPDATE agents SET agent_status='completed' WHERE id=?1;" "$ROW_ID"
else
    db_exec "$DB_FILE" "UPDATE agents SET agent_status='failed' WHERE id=?1;" "$ROW_ID"
fi

# Sandbox cleanup
if [[ "$USE_SANDBOX" == "true" ]] && [[ -n "$SANDBOX_DIR" ]]; then
    should_cleanup="false"
    if [[ "$exit_code" -eq 0 ]] && [[ "$SANDBOX_CLEANUP_ON_SUCCESS" == "true" ]]; then
        should_cleanup="true"
    elif [[ "$exit_code" -ne 0 ]] && [[ "$SANDBOX_CLEANUP_ON_FAILURE" == "true" ]]; then
        should_cleanup="true"
    fi
    if [[ "$should_cleanup" == "true" ]]; then
        log_info "Cleaning up sandbox: $SANDBOX_DIR"
        "$SCRIPTS_DIR/sandbox-cleanup.sh" "$SANDBOX_DIR" || log_warn "Sandbox cleanup failed"
    else
        log_info "Sandbox preserved: $SANDBOX_DIR"
    fi
fi

log_info "Done. Patch: $PATCH_OUT"
exit "$exit_code"
