#!/usr/bin/env bash
# cleanup-agent-sandbox.sh - Cleans up agent sandbox worktree
#
# Usage:
#   ./cleanup-agent-sandbox.sh <sandbox-dir>
#   ./cleanup-agent-sandbox.sh --prune-stale
#
# Examples:
#   ./cleanup-agent-sandbox.sh .agent-sandboxes/memory-opt-expert-20260208T134500Z
#   ./cleanup-agent-sandbox.sh --prune-stale

set -euo pipefail

# Directory containing this script
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared utilities
source "$SCRIPTS_DIR/common-utils.sh"

# ==============================================================================
# Main
# ==============================================================================

if [[ $# -lt 1 ]]; then
    echo "Usage: $(basename "$0") <sandbox-dir>" >&2
    echo "       $(basename "$0") --prune-stale" >&2
    echo "" >&2
    echo "Cleans up an agent sandbox worktree and branch." >&2
    exit 1
fi

# --prune-stale mode: find and remove orphaned sandboxes
if [[ "${1:-}" == "--prune-stale" ]]; then
    PROJECT_ROOT="$(git rev-parse --show-toplevel)"
    SANDBOX_BASE="$PROJECT_ROOT/.agent-sandboxes"

    if [[ ! -d "$SANDBOX_BASE" ]]; then
        log_info "No sandbox directory found. Nothing to prune."
        exit 0
    fi

    stale_count=0
    for dir in "$SANDBOX_BASE"/*/; do
        [[ -d "$dir" ]] || continue
        # Check if this is still a valid worktree
        if ! git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
            log_info "Pruning stale sandbox: $dir"
            rm -rf "$dir"
            stale_count=$((stale_count + 1))
        fi
    done

    # Also prune git's worktree bookkeeping
    git worktree prune 2>/dev/null || true

    log_info "Pruned $stale_count stale sandbox(es)"
    exit 0
fi

SANDBOX_DIR="$1"
PROJECT_ROOT="$(git rev-parse --show-toplevel)"
SANDBOX_BASE="$PROJECT_ROOT/.agent-sandboxes"

if [[ ! -d "$SANDBOX_DIR" ]]; then
    log_error "Sandbox directory not found: $SANDBOX_DIR"
    exit 1
fi

# Canonicalize paths to prevent directory traversal (e.g., ../../etc)
SANDBOX_DIR_REAL="$(realpath "$SANDBOX_DIR")"
SANDBOX_BASE_REAL="$(realpath "$SANDBOX_BASE" 2>/dev/null || echo "$SANDBOX_BASE")"

# Get the branch name before removing worktree
BRANCH_NAME=""
if [[ -d "$SANDBOX_DIR_REAL/.git" ]] || [[ -f "$SANDBOX_DIR_REAL/.git" ]]; then
    BRANCH_NAME=$(git -C "$SANDBOX_DIR_REAL" branch --show-current 2>/dev/null || echo "")
fi

log_info "Cleaning up sandbox: $SANDBOX_DIR_REAL"

# Remove worktree
cleanup_ok="false"
if git worktree remove "$SANDBOX_DIR_REAL" --force >/dev/null 2>&1; then
    log_info "Worktree removed"
    cleanup_ok="true"
else
    log_error "Failed to remove worktree, trying manual cleanup"
    case "$SANDBOX_DIR_REAL/" in
        "$SANDBOX_BASE_REAL/"*)
            if rm -rf "$SANDBOX_DIR_REAL"; then
                log_info "Manual cleanup removed directory"
                cleanup_ok="true"
            else
                log_error "Manual cleanup failed: $SANDBOX_DIR_REAL"
                exit 1
            fi
            ;;
        *)
            log_error "Refusing manual cleanup outside sandbox base: $SANDBOX_DIR (resolved: $SANDBOX_DIR_REAL)"
            exit 1
            ;;
    esac
fi

# Delete the branch if we got it
if [[ -n "$BRANCH_NAME" ]]; then
    if git branch -D "$BRANCH_NAME" >/dev/null 2>&1; then
        log_info "Branch deleted: $BRANCH_NAME"
    else
        log_info "Branch already deleted or not found: $BRANCH_NAME"
    fi
fi

if [[ "$cleanup_ok" == "true" ]]; then
    log_info "Sandbox cleaned up successfully"
else
    log_error "Sandbox cleanup failed"
    exit 1
fi
