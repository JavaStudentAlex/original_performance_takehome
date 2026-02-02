#!/usr/bin/env bash
# run-subagent.sh - Wrapper script for running Copilot CLI subagents safely and reproducibly
#
# This script performs an *atomic* end-to-end workflow by default:
#   1) Create an isolated git worktree on a new branch (from current HEAD)
#   2) MANDATORY state sync: mirror current workspace state into the worktree
#   3) Run the Copilot CLI agent inside the worktree
#   4) Generate a patch from *committed changes only*
#   5) Cleanup: remove worktree + delete branch (after patch exists)
#
# The goal is to make "create worktree" and "cleanup" non-separable, so we never
# leave stray worktrees/branches behind.
#
# Usage:
#   ./run-subagent.sh --agent=<agent-name> --prompt "<prompt>"
#
# Examples:
#   ./run-subagent.sh --agent=compilers-expert --prompt "Optimize the VLIW bundler"
#   ./run-subagent.sh --agent=test-expert --workdir ./tests --prompt "Write unit tests"
#   ./run-subagent.sh --agent=researcher --context-file STEP.md --prompt "Follow STEP.md"
#
# Debug / escape hatches:
#   --keep-worktree   Keep the worktree and branch (no cleanup). Intended for debugging only.
#   --no-worktree     Run directly in the current workspace (legacy behavior). Avoid in normal use.

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

# Worktree defaults
DEFAULT_WORKTREE_BASE=".worktrees"
DEFAULT_SYNC_MODE="auto"   # auto|rsync|git

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
    --workdir <path>            Working directory inside the repo/worktree
    --context-file <file>       File containing additional context to prepend to prompt
    --allow-tool <tool>         Additional tool to allow (repeatable)
    --deny-tool <tool>          Additional tool to deny (repeatable)
    --allow-urls                Allow network access (--allow-all-urls)
    --allow-paths               Allow all path access (--allow-all-paths)
    --dry-run                   Print actions/command without executing
    --verbose                   Print debug information

Worktree lifecycle (default behavior):
    --branch <name>             Branch name for the worktree (default: subagent/<agent>/<timestamp>)
    --worktree-base <dir>       Worktree base directory (default: $DEFAULT_WORKTREE_BASE)
    --sync <mode>               Sync mode: auto|rsync|git (default: $DEFAULT_SYNC_MODE)
    --patch-out <path>          Where to write the patch (default: .github/agent-state/patches/<ts>-<agent>.patch)
    --keep-worktree             Keep worktree + branch after run (debug only)
    --no-worktree               Run directly in current workspace (legacy; not recommended)

Examples:
    $(basename "$0") --agent=ml-expert --prompt "Implement the loss function"
    $(basename "$0") --agent=test-expert --model gpt-5 --prompt "Write unit tests"
    $(basename "$0") --agent=researcher --workdir ./src --prompt "Analyze this module"
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

sanitize_branch_name() {
    # Keep branch names git-safe and filesystem-safe.
    # - Replace spaces and unsafe chars with '-'
    # - Collapse repeated '-'
    # - Strip leading/trailing '-'
    local raw="$1"
    local cleaned

    cleaned=$(echo "$raw" \
        | tr '[:upper:]' '[:lower:]' \
        | sed -E 's#[^a-z0-9._/-]+#-#g; s#-+#-#g; s#(^-|-$)##g')

    # Avoid empty branch names.
    if [[ -z "$cleaned" ]]; then
        cleaned="subagent/auto"
    fi

    # Git dislikes '..' segments and branch components ending with '.'.
    cleaned=$(echo "$cleaned" \
        | sed -E 's#\.{2,}#-#g; s#(^|/)\.#\1-#g; s#\.+$##g')
    echo "$cleaned"
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

sync_workspace_state() {
    # Sync current workspace state into worktree.
    # Invariants:
    # - Must run immediately after worktree add
    # - Fail-closed: if sync fails, remove worktree and branch
    local project_root="$1"
    local worktree_path="$2"
    local worktree_base="$3"
    local mode="$4"   # auto|rsync|git

    log_info "Syncing workspace state into worktree (mandatory)..."

    # Safety: worktree must start clean.
    if [[ -n "$(git -C "$worktree_path" status --porcelain)" ]]; then
        log_error "Fresh worktree is not clean. This should not happen."
        return 1
    fi

    local sync_ok=false

    # Prefer rsync when available unless mode forces git.
    if [[ "$mode" == "rsync" || "$mode" == "auto" ]]; then
        if command -v rsync &>/dev/null; then
            # Run rsync from the repo root so ".gitignore" filter resolves correctly.
            if (cd "$project_root" && rsync -a --delete --itemize-changes \
                --exclude="${worktree_base%/}/" \
                --exclude='.git/' --exclude='.git' \
                --filter=':- .gitignore' \
                ./ "${worktree_path%/}/"); then
                sync_ok=true
                log_info "Worktree synced via rsync."
            else
                log_warn "rsync failed."
            fi
        else
            log_verbose "rsync not available."
        fi
    fi

    # Fallback: git-based sync
    if [[ "$sync_ok" != "true" ]]; then
        if [[ "$mode" == "git" || "$mode" == "auto" ]]; then
            log_info "Attempting git-based sync fallback..."
            local temp_patch
            temp_patch="/tmp/workspace-state-$$.patch"
            git -C "$project_root" diff HEAD > "$temp_patch" || true

            # Copy untracked files (respecting .gitignore)
            while IFS= read -r file; do
                [[ -z "$file" ]] && continue
                mkdir -p "$worktree_path/$(dirname "$file")"
                cp "$project_root/$file" "$worktree_path/$file" 2>/dev/null || true
            done < <(git -C "$project_root" ls-files --others --exclude-standard)

            if [[ -s "$temp_patch" ]]; then
                if git -C "$worktree_path" apply --3way "$temp_patch" 2>/dev/null \
                    || git -C "$worktree_path" apply --reject "$temp_patch" 2>/dev/null; then
                    sync_ok=true
                fi
            else
                # No tracked diffs; still consider sync successful.
                sync_ok=true
            fi

            rm -f "$temp_patch"
            if [[ "$sync_ok" == "true" ]]; then
                log_info "Worktree synced via git fallback."
            else
                log_error "Git-based sync fallback failed."
            fi
        else
            log_error "Sync mode is '$mode' but rsync was unavailable/failed."
        fi
    fi

    [[ "$sync_ok" == "true" ]]
}

cleanup_worktree() {
    local project_root="$1"
    local worktree_path="$2"
    local branch_name="$3"

    log_info "Cleaning up worktree and branch..."
    git -C "$project_root" worktree remove --force "$worktree_path" 2>/dev/null || true
    git -C "$project_root" branch -D "$branch_name" 2>/dev/null || true
    git -C "$project_root" worktree prune 2>/dev/null || true
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

USE_WORKTREE="true"
KEEP_WORKTREE="false"
WORKTREE_BASE="$DEFAULT_WORKTREE_BASE"
BRANCH_NAME=""
SYNC_MODE="$DEFAULT_SYNC_MODE"
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

        --branch)
            BRANCH_NAME="$2"; shift 2 ;;
        --branch=*)
            BRANCH_NAME="${1#*=}"; shift ;;
        --worktree-base)
            WORKTREE_BASE="$2"; shift 2 ;;
        --worktree-base=*)
            WORKTREE_BASE="${1#*=}"; shift ;;
        --sync)
            SYNC_MODE="$2"; shift 2 ;;
        --sync=*)
            SYNC_MODE="${1#*=}"; shift ;;
        --patch-out)
            PATCH_OUT="$2"; shift 2 ;;
        --patch-out=*)
            PATCH_OUT="${1#*=}"; shift ;;
        --keep-worktree)
            KEEP_WORKTREE="true"; shift ;;
        --no-worktree)
            USE_WORKTREE="false"; shift ;;

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
    # For worktree mode, WORKDIR is interpreted relative to repo root.
    # Absolute paths are not allowed because they break isolation.
    if [[ "$USE_WORKTREE" == "true" ]] && [[ "$WORKDIR" = /* ]]; then
        log_error "--workdir must be a relative path when using worktrees"
        exit 1
    fi
fi

case "$SYNC_MODE" in
    auto|rsync|git) ;;
    *)
        log_error "Invalid --sync mode: $SYNC_MODE (expected auto|rsync|git)"
        exit 1
        ;;
esac

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
log_verbose "Worktree enabled: $USE_WORKTREE"

if [[ "$DRY_RUN" == "true" ]]; then
    if [[ "$USE_WORKTREE" == "true" ]]; then
        local_branch="${BRANCH_NAME:-subagent/${AGENT_FOR_NAMES}/${TS}}"
        local_branch="$(sanitize_branch_name "$local_branch")"
        local_worktree="$PROJECT_ROOT/${WORKTREE_BASE%/}/$local_branch"
        echo "DRY RUN - Would perform atomic worktree workflow:" >&2
        echo "  - create worktree: $local_worktree (branch: $local_branch)" >&2
        echo "  - sync workspace state (mandatory)" >&2
        echo "  - run: ${CMD[*]}" >&2
        echo "  - write patch: $PATCH_OUT" >&2
        echo "  - cleanup worktree + delete branch" >&2
    else
        echo "DRY RUN - Would execute:" >&2
        echo "  cd ${WORKDIR:-.} && ${CMD[*]}" >&2
    fi
    exit 0
fi

exit_code=0
worktree_path=""
branch_name=""
base_commit=""
cleanup_needed="false"

cleanup_trap() {
    if [[ "$USE_WORKTREE" == "true" && "$KEEP_WORKTREE" != "true" && "$cleanup_needed" == "true" ]]; then
        cleanup_worktree "$PROJECT_ROOT" "$worktree_path" "$branch_name"
    fi
}
trap cleanup_trap EXIT

if [[ "$USE_WORKTREE" == "false" ]]; then
    # Legacy: run in current workspace.
    if [[ -n "$WORKDIR" ]]; then
        if [[ ! -d "$PROJECT_ROOT/$WORKDIR" ]]; then
            log_error "Working directory not found: $WORKDIR"
            exit 1
        fi
        cd "$PROJECT_ROOT/$WORKDIR"
    else
        cd "$PROJECT_ROOT"
    fi
    log_info "Running agent directly in workspace (no worktree)."
    run_with_timeout "${CMD[@]}" || exit_code=$?
    exit "$exit_code"
fi

# --- Worktree lifecycle ---

base_commit="$(git -C "$PROJECT_ROOT" rev-parse HEAD)"

branch_name="${BRANCH_NAME:-subagent/${AGENT_FOR_NAMES}/${TS}}"
branch_name="$(sanitize_branch_name "$branch_name")"
worktree_path="$PROJECT_ROOT/${WORKTREE_BASE%/}/$branch_name"

mkdir -p "$PROJECT_ROOT/${WORKTREE_BASE%/}"

# Ensure the worktree base is gitignored. This is important for rsync-based sync,
# which relies on .gitignore as the single source of truth for exclusions.
if ! git -C "$PROJECT_ROOT" check-ignore -q "${WORKTREE_BASE%/}/" 2>/dev/null; then
    log_warn "Worktree base '${WORKTREE_BASE%/}/' is not ignored. Adding it to .gitignore."
    if [[ ! -f "$PROJECT_ROOT/.gitignore" ]]; then
        touch "$PROJECT_ROOT/.gitignore"
    fi
    if ! grep -qxF "${WORKTREE_BASE%/}/" "$PROJECT_ROOT/.gitignore"; then
        {
            echo ""
            echo "# Git worktrees"
            echo "${WORKTREE_BASE%/}/"
        } >> "$PROJECT_ROOT/.gitignore"
    fi
fi

if git -C "$PROJECT_ROOT" worktree list --porcelain | grep -Fq "branch refs/heads/$branch_name"; then
    log_error "Worktree already exists for branch: $branch_name"
    exit 1
fi

if git -C "$PROJECT_ROOT" rev-parse --verify "$branch_name" >/dev/null 2>&1; then
    log_error "Branch already exists: $branch_name"
    exit 1
fi

log_info "Creating worktree..."
log_info "  Branch: $branch_name"
log_info "  Path:   $worktree_path"

mkdir -p "$(dirname "$worktree_path")"
git -C "$PROJECT_ROOT" worktree add "$worktree_path" -b "$branch_name" "$base_commit"
cleanup_needed="true"

if ! sync_workspace_state "$PROJECT_ROOT" "$worktree_path" "$WORKTREE_BASE" "$SYNC_MODE"; then
    log_error "FATAL: Workspace sync failed. Removing invalid worktree/branch and aborting."
    cleanup_worktree "$PROJECT_ROOT" "$worktree_path" "$branch_name"
    cleanup_needed="false"
    exit 1
fi

# Run agent inside worktree
run_dir="$worktree_path"
if [[ -n "$WORKDIR" ]]; then
    run_dir="$worktree_path/${WORKDIR#./}"
    if [[ ! -d "$run_dir" ]]; then
        log_error "Working directory not found in worktree: $WORKDIR"
        exit 1
    fi
fi

log_info "Running subagent in worktree..."
log_verbose "Run directory: $run_dir"

pushd "$run_dir" >/dev/null
run_with_timeout "${CMD[@]}" || exit_code=$?
popd >/dev/null

if [[ "$exit_code" -eq 124 ]]; then
    log_error "Subagent run timed out after $TIMEOUT_HUMAN"
fi

# Patch creation (commits only)
mkdir -p "$(dirname "$PATCH_OUT")"

if git -C "$worktree_path" status --porcelain | grep -q .; then
    log_warn "Uncommitted changes exist in worktree and will be discarded during cleanup."
fi

log_info "Writing patch (committed changes only): $PATCH_OUT"
git -C "$worktree_path" diff "$base_commit" HEAD > "$PATCH_OUT"

if [[ ! -s "$PATCH_OUT" ]]; then
    log_warn "Patch is empty. The agent may not have committed changes."
fi

# Cleanup after patch exists
if [[ "$KEEP_WORKTREE" == "true" ]]; then
    log_warn "Keeping worktree (debug): $worktree_path"
    log_warn "Keeping branch (debug):  $branch_name"
    cleanup_needed="false"
else
    cleanup_worktree "$PROJECT_ROOT" "$worktree_path" "$branch_name"
    cleanup_needed="false"
fi

log_info "Done. Patch: $PATCH_OUT"
exit "$exit_code"
