#!/usr/bin/env bash
# run-subagent.sh - Wrapper script for running Copilot CLI subagents safely and reproducibly
#
# This script runs the Copilot CLI agent directly in the current workspace
# (repo root by default, or --workdir <path>) and produces a patch of the
# directory-state diff (before/after snapshots; commits optional).
#
# Usage:
#   ./run-subagent.sh --agent=<agent-name> --prompt "<prompt>"
#
# Examples:
#   ./run-subagent.sh --agent=compilers-expert --prompt "Optimize the VLIW bundler"
#   ./run-subagent.sh --agent=test-expert --workdir ./tests --prompt "Write unit tests"
#   ./run-subagent.sh --agent=planner --context-file STEP.md --prompt "Follow STEP.md"
#
# Note:
#   This wrapper always writes a patch capturing the workspace changes made
#   during the run.

set -euo pipefail

# ==============================================================================
# Configuration
# ==============================================================================

# Max runtime for a single subagent invocation.
# Default is 1 hour (3600s). If exceeded, the job is terminated and the wrapper
# exits non-zero (124 on timeout).
MAX_RUNTIME_SECONDS=3600

# After sending SIGTERM on timeout, wait this long (in seconds) before SIGKILL.
KILL_AFTER_SECONDS=30

# Default model (can be overridden)
DEFAULT_MODEL="claude-sonnet-4.5"

# Default denied tools (safety first)
DENIED_TOOLS=(
    "shell(rm)"
    "shell(rm -rf)"
    "shell(rmdir)"
    "shell(git push)"
    "shell(git push --force)"
    "shell(git push -f)"
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

Output:
    --patch-out <path>          Where to write the patch (default: .github/agent-state/patches/<ts>-<agent>.patch)

Examples:
    $(basename "$0") --agent=ml-expert --prompt "Implement the loss function"
    $(basename "$0") --agent=test-expert --model gpt-5 --prompt "Write unit tests"
    $(basename "$0") --agent=planner --workdir ./src --prompt "Analyze this module"
    $(basename "$0") --prompt "Refactor this" --context-file STEP.md

Tool Permission Examples:
    $(basename "$0") --prompt "..." --allow-tool 'shell(npm run test:*)'
    $(basename "$0") --prompt "..." --deny-tool 'shell(docker)'
EOF
}

log_verbose() {
    if [[ "${VERBOSE:-false}" == "true" ]]; then
        echo "[VERBOSE] $*" >&2
    fi
}

log_info() {
    echo "[INFO] $*" >&2
}

log_warn() {
    echo "[WARN] $*" >&2
}

log_error() {
    echo "[ERROR] $*" >&2
}

seconds_to_human() {
    local total=$1
    local h=$(( total / 3600 ))
    local m=$(( (total % 3600) / 60 ))
    local s=$(( total % 60 ))

    if (( h > 0 )); then
        printf '%dh %dm %ds' "$h" "$m" "$s"
    elif (( m > 0 )); then
        printf '%dm %ds' "$m" "$s"
    else
        printf '%ds' "$s"
    fi
}

check_copilot_installed() {
    if ! command -v copilot &> /dev/null; then
        log_error "GitHub Copilot CLI is not installed."
        log_error "Install with: npm install -g @github/copilot"
        exit 1
    fi
}

ensure_in_git_repo() {
    if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
        log_error "Not inside a git repository."
        exit 1
    fi
}

make_timestamp() {
    date -u +"%Y%m%dT%H%M%SZ"
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

snapshot_directory_state() {
    # Snapshot current directory state into a git tree object.
    # Captures tracked + untracked files; excludes ignored files.
    # Uses a temporary alternate index so it does not disturb the repo's real index.
    local repo="$1"
    local tmpdir
    local idx

    tmpdir="$(mktemp -d -t subagent-index.XXXXXX)"
    idx="$tmpdir/index"

    # Populate the temporary index with the current working tree contents.
    GIT_INDEX_FILE="$idx" git -C "$repo" add -A >/dev/null

    local tree
    tree="$(GIT_INDEX_FILE="$idx" git -C "$repo" write-tree)"

    rm -rf "$tmpdir"
    echo "$tree"
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
fi

if [[ -n "$CONTEXT_FILE" ]] && [[ ! -f "$CONTEXT_FILE" ]]; then
    log_error "Context file not found: $CONTEXT_FILE"
    exit 1
fi

if [[ -n "$WORKDIR" ]]; then
    # WORKDIR is interpreted relative to repo root.
    # Absolute paths are not allowed.
    if [[ "$WORKDIR" = /* ]]; then
        log_error "--workdir must be a relative path"
        exit 1
    fi
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

FULL_PROMPT="$PROMPT"
if [[ -n "$CONTEXT_FILE" ]]; then
    CONTEXT_CONTENT=$(cat "$CONTEXT_FILE")
    FULL_PROMPT="CONTEXT FROM FILE ($CONTEXT_FILE):
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

if [[ "$DRY_RUN" == "true" ]]; then
    echo "DRY RUN - Would execute in workspace:" >&2
    echo "  cd ${WORKDIR:-.} && ${CMD[*]}" >&2
    echo "  write patch (state diff): $PATCH_OUT" >&2
    exit 0
fi

exit_code=0
base_commit="$(git -C "$PROJECT_ROOT" rev-parse HEAD)"

# Snapshot directory state before the run (baseline for patch generation).
STATE_OUT="$PROJECT_ROOT/.github/agent-state/subagents/${TS}-${AGENT_FOR_NAMES}.workspace-state.txt"
mkdir -p "$(dirname "$STATE_OUT")"
before_tree="$(snapshot_directory_state "$PROJECT_ROOT")"
{
    echo "base_commit=$base_commit"
    echo "before_tree=$before_tree"
} > "$STATE_OUT"

# Run agent inside workspace
run_dir="$PROJECT_ROOT"
if [[ -n "$WORKDIR" ]]; then
    run_dir="$PROJECT_ROOT/${WORKDIR#./}"
    if [[ ! -d "$run_dir" ]]; then
        log_error "Working directory not found in workspace: $WORKDIR"
        exit 1
    fi
fi

log_info "Running subagent in workspace..."
log_verbose "Run directory: $run_dir"

pushd "$run_dir" >/dev/null
run_with_timeout "${CMD[@]}" || exit_code=$?
popd >/dev/null

if [[ "$exit_code" -eq 124 ]]; then
    log_error "Subagent run timed out after $TIMEOUT_HUMAN"
fi

after_tree="$(snapshot_directory_state "$PROJECT_ROOT")"
echo "after_tree=$after_tree" >> "$STATE_OUT"

if [[ "$before_tree" == "$after_tree" ]]; then
    log_info "No directory changes detected between snapshots."
else
    log_info "Directory changes detected between snapshots."
fi

# Patch creation (workspace state diff)
mkdir -p "$(dirname "$PATCH_OUT")"

log_info "Writing patch (workspace state diff): $PATCH_OUT"
git -C "$PROJECT_ROOT" diff --binary --no-color "$before_tree" "$after_tree" > "$PATCH_OUT"

if [[ ! -s "$PATCH_OUT" ]]; then
    log_warn "Patch is empty. The agent may not have changed any files."
fi

log_info "Done. Patch: $PATCH_OUT"
exit "$exit_code"
