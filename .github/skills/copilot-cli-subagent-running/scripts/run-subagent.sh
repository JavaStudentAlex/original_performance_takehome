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
    --tool-policy <policy>      Tool permission policy: 'allowlist' (default) or 'legacy-denylist'
    --allow-all-tools-unsafe    Shortcut for --tool-policy=legacy-denylist
    --allow-tool <tool>         Additional tool to allow (repeatable)
    --deny-tool <tool>          Additional tool to deny (repeatable)
    --max-inline-context-bytes <N>  Max context file size to inline (default: 65536)
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
MAX_INLINE_CONTEXT_BYTES=65536
TOOL_POLICY="allowlist"
USE_SANDBOX="false"
SANDBOX_CLEANUP_ON_SUCCESS="true"
SANDBOX_CLEANUP_ON_FAILURE="false"

require_value() {
    local opt="$1"
    local remaining="$2"
    local next_val="${3:-}"
    if [[ "$remaining" -lt 2 ]]; then
        log_error "Missing value for $opt"
        print_usage
        exit 1
    fi
    # Detect when the next token looks like another flag (starts with --).
    # Use --opt=value form if the value legitimately starts with dashes.
    if [[ -n "$next_val" ]] && [[ "$next_val" == --* ]]; then
        log_error "Missing value for $opt (next argument '$next_val' looks like a flag; use ${opt}=<value> if the value starts with '--')"
        print_usage
        exit 1
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --prompt)
            require_value "--prompt" "$#" "${2:-}"
            PROMPT="$2"; shift 2 ;;
        --prompt=*)
            PROMPT="${1#*=}"; shift ;;
        --agent)
            require_value "--agent" "$#" "${2:-}"
            AGENT="$2"; shift 2 ;;
        --agent=*)
            AGENT="${1#*=}"; shift ;;
        --model)
            require_value "--model" "$#" "${2:-}"
            MODEL="$2"; shift 2 ;;
        --model=*)
            MODEL="${1#*=}"; shift ;;
        --workdir)
            require_value "--workdir" "$#" "${2:-}"
            WORKDIR="$2"; shift 2 ;;
        --workdir=*)
            WORKDIR="${1#*=}"; shift ;;
        --context-file)
            require_value "--context-file" "$#" "${2:-}"
            CONTEXT_FILE="$2"; shift 2 ;;
        --context-file=*)
            CONTEXT_FILE="${1#*=}"; shift ;;
        --allow-tool)
            require_value "--allow-tool" "$#" "${2:-}"
            EXTRA_ALLOW_TOOLS+=("$2"); shift 2 ;;
        --allow-tool=*)
            EXTRA_ALLOW_TOOLS+=("${1#*=}"); shift ;;
        --deny-tool)
            require_value "--deny-tool" "$#" "${2:-}"
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
            require_value "--patch-out" "$#" "${2:-}"
            PATCH_OUT="$2"; shift 2 ;;
        --patch-out=*)
            PATCH_OUT="${1#*=}"; shift ;;
        --max-inline-context-bytes)
            require_value "--max-inline-context-bytes" "$#" "${2:-}"
            MAX_INLINE_CONTEXT_BYTES="$2"; shift 2 ;;
        --max-inline-context-bytes=*)
            MAX_INLINE_CONTEXT_BYTES="${1#*=}"; shift ;;
        --tool-policy)
            require_value "--tool-policy" "$#" "${2:-}"
            TOOL_POLICY="$2"; shift 2 ;;
        --tool-policy=*)
            TOOL_POLICY="${1#*=}"; shift ;;
        --allow-all-tools-unsafe)
            TOOL_POLICY="legacy-denylist"; shift ;;
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

# Validate agent name (P06): reject unsafe characters before any DB/sandbox work.
# Allowed: alphanumeric, dot, hyphen, underscore. Must start with alphanumeric.
# Max 64 characters. Empty is allowed (means "auto" / no custom agent).
if [[ -n "$AGENT" ]]; then
    if ! [[ "$AGENT" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]]; then
        log_error "Invalid --agent value: '$AGENT'"
        log_error "Agent name must match ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ (alphanumeric start, max 64 chars, no whitespace/slashes/newlines)"
        exit 1
    fi
fi

# Validate tool-policy value
case "$TOOL_POLICY" in
    allowlist|legacy-denylist) ;;
    *)
        log_error "Invalid --tool-policy: '$TOOL_POLICY' (must be 'allowlist' or 'legacy-denylist')"
        exit 1
        ;;
esac

ensure_in_git_repo
if [[ "$DRY_RUN" != "true" ]]; then
    check_copilot_installed
    check_sqlite_installed
fi

# Note: context-file validation is deferred until after PROJECT_ROOT is computed
# (see P04/G03 — repo-root-relative path resolution).

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

# --- Tool policy (P05/G02) ---
# Conservative fallback allowlist when no agent-specific tools are found.
DEFAULT_ALLOWLIST_TOOLS=(
    "read"
    "search"
    "execute"
    "edit"
    "agent"
    "todo"
    "web"
    "vscode"
)

log_verbose "Tool policy: $TOOL_POLICY"

if [[ "$TOOL_POLICY" == "legacy-denylist" ]]; then
    # Legacy mode: allow all tools, deny destructive ones (original behavior).
    CMD+=(--allow-all-tools)
    log_verbose "Tool policy: legacy-denylist (--allow-all-tools with deny patterns)"
else
    # Allowlist mode (default): build tool set from agent definition or fallback.
    ALLOWLIST_TOOLS=()
    ALLOWLIST_SOURCE=""

    # Try to parse tools from agent definition file.
    # Resolution order: user-global first, then repo-local.
    AGENT_DEF_FILE=""
    if [[ -n "$AGENT" ]]; then
        if [[ -f "$HOME/.copilot/agents/${AGENT}.agent.md" ]]; then
            AGENT_DEF_FILE="$HOME/.copilot/agents/${AGENT}.agent.md"
        elif [[ -f "$(git rev-parse --show-toplevel 2>/dev/null)/.github/agents/${AGENT}.agent.md" ]]; then
            AGENT_DEF_FILE="$(git rev-parse --show-toplevel)/.github/agents/${AGENT}.agent.md"
        fi
    fi

    if [[ -n "$AGENT_DEF_FILE" ]]; then
        # Parse tools from agent file: look for lines matching "- tool: <name>"
        # or a YAML/markdown tools block. Simple line-based extraction.
        while IFS= read -r line; do
            # Match lines like "- tool: read" or "- read" under a tools section
            tool_name=""
            if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+tool:[[:space:]]*(.+)$ ]]; then
                tool_name="${BASH_REMATCH[1]}"
            fi
            if [[ -n "$tool_name" ]]; then
                # Trim whitespace
                tool_name="$(echo "$tool_name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
                ALLOWLIST_TOOLS+=("$tool_name")
            fi
        done < "$AGENT_DEF_FILE"
        if [[ ${#ALLOWLIST_TOOLS[@]} -gt 0 ]]; then
            ALLOWLIST_SOURCE="agent-definition ($AGENT_DEF_FILE)"
        fi
    fi

    if [[ ${#ALLOWLIST_TOOLS[@]} -eq 0 ]]; then
        # No tools parsed from agent definition — use conservative fallback.
        ALLOWLIST_TOOLS=("${DEFAULT_ALLOWLIST_TOOLS[@]}")
        ALLOWLIST_SOURCE="default-fallback"
    fi

    # Add allowlist tools
    for tool in "${ALLOWLIST_TOOLS[@]}"; do
        CMD+=(--allow-tool "$tool")
    done
    log_verbose "Allowlist source: $ALLOWLIST_SOURCE"
    log_verbose "Allowlist tools: ${ALLOWLIST_TOOLS[*]}"
fi

# Always apply deny patterns as defense-in-depth (both policies).
for tool in "${DENIED_TOOLS[@]}"; do
    CMD+=(--deny-tool "$tool")
done
for tool in "${EXTRA_DENY_TOOLS[@]}"; do
    CMD+=(--deny-tool "$tool")
done
# Extra allow-tools from CLI override (union with policy allowlist).
for tool in "${EXTRA_ALLOW_TOOLS[@]}"; do
    CMD+=(--allow-tool "$tool")
done

if [[ "$ALLOW_URLS" == "true" ]]; then
    CMD+=(--allow-all-urls)
fi
if [[ "$ALLOW_PATHS" == "true" ]]; then
    CMD+=(--allow-all-paths)
fi

# ==============================================================================
# Execute
# ==============================================================================

TIMEOUT_HUMAN="$(seconds_to_human "$MAX_RUNTIME_SECONDS")"
AGENT_FOR_NAMES="${AGENT:-auto}"
TS="$(make_timestamp)"

PROJECT_ROOT="$(git rev-parse --show-toplevel)"

# --- Context-file resolution (P04/G03): repo-root-relative semantics ---
CONTEXT_FILE_REPO_ABS=""
if [[ -n "$CONTEXT_FILE" ]]; then
    if [[ "$CONTEXT_FILE" = /* ]]; then
        # Absolute path: must be inside repo root
        case "$CONTEXT_FILE" in
            "$PROJECT_ROOT"/*)
                CONTEXT_FILE_REPO_ABS="$CONTEXT_FILE"
                ;;
            *)
                log_error "--context-file absolute path must be inside the repo root ($PROJECT_ROOT): $CONTEXT_FILE"
                exit 1
                ;;
        esac
    else
        # Relative path: resolve from PROJECT_ROOT (not caller CWD)
        case "$CONTEXT_FILE" in
            ..|../*|*/..|*/../*)
                log_error "--context-file must not contain '..' (path traversal): $CONTEXT_FILE"
                exit 1
                ;;
        esac
        CONTEXT_FILE_REPO_ABS="$PROJECT_ROOT/$CONTEXT_FILE"
    fi
    if [[ ! -f "$CONTEXT_FILE_REPO_ABS" ]]; then
        log_error "Context file not found: $CONTEXT_FILE_REPO_ABS (resolved from repo root)"
        exit 1
    fi
fi

# --- Prompt assembly (P03): handle large context files ---
CONTRACT_DIRECTIVE="READ FIRST: .github/copilot-instructions.md"
FULL_PROMPT="$CONTRACT_DIRECTIVE

$PROMPT"
if [[ -n "$CONTEXT_FILE_REPO_ABS" ]]; then
    context_size=$(wc -c < "$CONTEXT_FILE_REPO_ABS")
    log_verbose "Context file size: $context_size bytes (max inline: $MAX_INLINE_CONTEXT_BYTES)"
    if [[ "$context_size" -le "$MAX_INLINE_CONTEXT_BYTES" ]]; then
        # Small enough to inline
        CONTEXT_CONTENT=$(cat "$CONTEXT_FILE_REPO_ABS")
        FULL_PROMPT="$CONTRACT_DIRECTIVE

CONTEXT FROM FILE ($CONTEXT_FILE):
---
$CONTEXT_CONTENT
---

TASK:
$PROMPT"
    else
        # Too large to inline — inject a file-read directive instead
        log_warn "Context file exceeds ${MAX_INLINE_CONTEXT_BYTES} bytes ($context_size bytes). Using file-reference mode to avoid ARG_MAX issues."
        FULL_PROMPT="$CONTRACT_DIRECTIVE

IMPORTANT: READ THIS FILE FIRST before starting work: $CONTEXT_FILE_REPO_ABS
(Context file too large to inline — $context_size bytes. You must read it using your file-read tool.)

TASK:
$PROMPT"
    fi
fi

CMD+=(-p "$FULL_PROMPT")

if [[ -z "$PATCH_OUT" ]]; then
    PATCH_OUT="$PROJECT_ROOT/.github/agent-state/patches/${TS}-${AGENT_FOR_NAMES}.patch"
elif [[ "$PATCH_OUT" != /* ]]; then
    PATCH_OUT="$PROJECT_ROOT/$PATCH_OUT"
fi

log_verbose "Model: $MODEL"
log_verbose "Agent: ${AGENT:-<auto>}"
log_verbose "Tool policy: $TOOL_POLICY"
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

fail_after_run_registered() {
    local msg="$1"
    log_error "$msg"
    db_exec "$DB_FILE" "UPDATE agents SET agent_status='failed' WHERE id=?1;" "$ROW_ID" || true
    if [[ "$USE_SANDBOX" == "true" ]] && [[ -n "${SANDBOX_DIR:-}" ]] && [[ "$SANDBOX_CLEANUP_ON_FAILURE" == "true" ]]; then
        "$SCRIPTS_DIR/sandbox-cleanup.sh" "$SANDBOX_DIR" || log_warn "Sandbox cleanup failed"
    fi
    exit 1
}

# P07+G04: Signal trap for cleanup on interrupt.
# If the script is interrupted after the DB row is created but before the
# final status update, mark the row as 'interrupted' and optionally clean up
# the sandbox. RUN_FINALIZED guards against race with normal finalization.
RUN_FINALIZED="false"
cleanup_on_signal() {
    local sig="$1"
    if [[ "$RUN_FINALIZED" == "true" ]]; then
        # Normal finalization already completed; just exit with signal code.
        case "$sig" in
            INT)  exit 130 ;;
            TERM) exit 143 ;;
            HUP)  exit 129 ;;
            *)    exit 1 ;;
        esac
    fi
    log_warn "Received signal $sig — cleaning up agent run id=$ROW_ID..."
    db_exec "$DB_FILE" \
        "UPDATE agents SET agent_status='interrupted' WHERE id=?1;" \
        "$ROW_ID" || true
    if [[ "$USE_SANDBOX" == "true" ]] && [[ -n "${SANDBOX_DIR:-}" ]]; then
        log_warn "Cleaning up sandbox after interruption: $SANDBOX_DIR"
        "$SCRIPTS_DIR/sandbox-cleanup.sh" "$SANDBOX_DIR" 2>/dev/null || true
    fi
    case "$sig" in
        INT)  exit 130 ;;
        TERM) exit 143 ;;
        HUP)  exit 129 ;;
        *)    exit 1 ;;
    esac
}
trap 'cleanup_on_signal INT'  INT
trap 'cleanup_on_signal TERM' TERM
trap 'cleanup_on_signal HUP'  HUP

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
# P01: State file is written AFTER patch generation to avoid contaminating
# the before/after diff window. We only prepare the output dir here.
STATE_OUT="$PROJECT_ROOT/.github/agent-state/subagents/${TS}-${AGENT_FOR_NAMES}.workspace-state.txt"
if ! mkdir -p "$(dirname "$STATE_OUT")"; then
    fail_after_run_registered "Failed to create state output directory: $(dirname "$STATE_OUT")"
fi
before_tree="$(snapshot_directory_state "$SNAPSHOT_ROOT")" || fail_after_run_registered "Failed to snapshot directory state before run"

# Determine run directory
run_dir="$SNAPSHOT_ROOT"
if [[ -n "$WORKDIR" ]]; then
    run_dir="$SNAPSHOT_ROOT/${WORKDIR#./}"
    if [[ ! -d "$run_dir" ]]; then
        fail_after_run_registered "Working directory not found: $WORKDIR"
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

after_tree="$(snapshot_directory_state "$SNAPSHOT_ROOT")" || fail_after_run_registered "Failed to snapshot directory state after run"

if [[ "$before_tree" == "$after_tree" ]]; then
    log_info "No directory changes detected between snapshots."
else
    log_info "Directory changes detected between snapshots."
fi

# Patch creation (workspace state diff)
if ! mkdir -p "$(dirname "$PATCH_OUT")"; then
    fail_after_run_registered "Failed to create patch directory: $(dirname "$PATCH_OUT")"
fi

log_info "Writing patch (workspace state diff): $PATCH_OUT"
patch_ok="true"
# P09: Capture stderr to a temp file instead of discarding it, so we can
# log the actual diagnostic on failure (not just "returned non-zero").
_diff_stderr_file="$(mktemp)"
if ! git -C "$SNAPSHOT_ROOT" diff --binary --no-color "$before_tree" "$after_tree" \
        > "$PATCH_OUT" 2>"$_diff_stderr_file"; then
    log_error "Patch generation failed (git diff returned non-zero). Trees: before=$before_tree after=$after_tree"
    if [[ -s "$_diff_stderr_file" ]]; then
        log_error "git diff stderr: $(cat "$_diff_stderr_file")"
    fi
    patch_ok="false"
fi
rm -f "$_diff_stderr_file"

if [[ ! -s "$PATCH_OUT" ]]; then
    if [[ "$before_tree" != "$after_tree" ]]; then
        log_error "Patch output is empty despite detected directory changes."
        patch_ok="false"
    else
        log_warn "Patch is empty. The agent may not have changed any files."
    fi
fi

if [[ "$patch_ok" != "true" ]]; then
    log_error "Patch generation failed; marking run as failed"
    exit_code=1
fi

# P01: Write state file AFTER patch generation to avoid contaminating the diff.
if ! {
    echo "base_commit=$base_commit"
    echo "before_tree=$before_tree"
    echo "after_tree=$after_tree"
} > "$STATE_OUT"
then
    log_warn "Failed to write workspace state file: $STATE_OUT"
fi

# Update agent status in database
if [[ "$exit_code" -eq 0 ]]; then
    db_exec "$DB_FILE" "UPDATE agents SET agent_status='completed' WHERE id=?1;" "$ROW_ID"
else
    db_exec "$DB_FILE" "UPDATE agents SET agent_status='failed' WHERE id=?1;" "$ROW_ID"
fi

# G04: Mark finalization complete and disarm signal trap to prevent race.
RUN_FINALIZED="true"
trap - INT TERM HUP

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
