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
# Path Safety Helpers
# ==============================================================================

strip_trailing_slashes() {
    local path="$1"
    while [[ "$path" != "/" ]] && [[ "$path" == */ ]]; do
        path="${path%/}"
    done
    printf '%s' "$path"
}

is_within_base() {
    local target_real="$1"
    local base_real="$2"
    case "$target_real/" in
        "$base_real/"*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

resolve_path() {
    # P05: Portable realpath replacement using cd -P / pwd -P.
    # Returns the canonical physical path. Follows symlinks.
    # Returns non-zero if the path does not exist.
    local target="$1"
    if command -v realpath &>/dev/null; then
        realpath "$target"
        return $?
    fi
    # Fallback: cd -P into the directory and use pwd -P
    if [[ -d "$target" ]]; then
        (cd -P "$target" && pwd -P)
    elif [[ -e "$target" ]]; then
        local dir base
        dir="$(cd -P "$(dirname "$target")" && pwd -P)" || return 1
        base="$(basename "$target")"
        printf '%s/%s\n' "$dir" "$base"
    else
        return 1
    fi
}

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

    SANDBOX_BASE_REAL="$(resolve_path "$SANDBOX_BASE")"
    stale_count=0
    shopt -s nullglob
    sandbox_entries=("$SANDBOX_BASE"/*)
    shopt -u nullglob

    for entry in "${sandbox_entries[@]}"; do
        entry_norm="$(strip_trailing_slashes "$entry")"
        [[ -e "$entry_norm" ]] || [[ -L "$entry_norm" ]] || continue

        # Never traverse symlinks in prune mode.
        if [[ -L "$entry_norm" ]]; then
            log_warn "Pruning symlink entry without traversal: $entry_norm"
            rm -f -- "$entry_norm"
            stale_count=$((stale_count + 1))
            continue
        fi

        [[ -d "$entry_norm" ]] || continue

        entry_real="$(resolve_path "$entry_norm" 2>/dev/null || true)"
        if [[ -z "$entry_real" ]]; then
            log_warn "Skipping entry with unresolved realpath: $entry_norm"
            continue
        fi

        # A valid sandbox worktree reports itself as its own git top-level.
        entry_toplevel="$(git -C "$entry_norm" rev-parse --show-toplevel 2>/dev/null || true)"
        entry_toplevel_real=""
        if [[ -n "$entry_toplevel" ]]; then
            entry_toplevel_real="$(resolve_path "$entry_toplevel" 2>/dev/null || true)"
        fi
        if [[ "$entry_toplevel_real" == "$entry_real" ]]; then
            continue
        fi

        if ! is_within_base "$entry_real" "$SANDBOX_BASE_REAL"; then
            log_error "Refusing prune outside sandbox base: $entry_norm (resolved: $entry_real)"
            continue
        fi
        log_info "Pruning stale sandbox: $entry_norm"
        rm -rf -- "$entry_norm"
        stale_count=$((stale_count + 1))
    done

    # Also prune git's worktree bookkeeping
    git worktree prune 2>/dev/null || true

    log_info "Pruned $stale_count stale sandbox(es)"
    exit 0
fi

SANDBOX_DIR="$1"
PROJECT_ROOT="$(git rev-parse --show-toplevel)"
SANDBOX_BASE="$PROJECT_ROOT/.agent-sandboxes"
SANDBOX_DIR_NORM="$(strip_trailing_slashes "$SANDBOX_DIR")"

if [[ ! -d "$SANDBOX_DIR_NORM" ]]; then
    log_error "Sandbox directory not found: $SANDBOX_DIR_NORM"
    exit 1
fi

# Canonicalize paths to prevent directory traversal (e.g., ../../etc)
SANDBOX_DIR_REAL="$(resolve_path "$SANDBOX_DIR_NORM")"
SANDBOX_BASE_REAL="$(resolve_path "$SANDBOX_BASE" 2>/dev/null || echo "$SANDBOX_BASE")"

# Refuse cleanup if the resolved path is outside sandbox base.
if ! is_within_base "$SANDBOX_DIR_REAL" "$SANDBOX_BASE_REAL"; then
    log_error "Refusing cleanup outside sandbox base: $SANDBOX_DIR_NORM (resolved: $SANDBOX_DIR_REAL)"
    exit 1
fi

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
    if rm -rf "$SANDBOX_DIR_REAL"; then
        log_info "Manual cleanup removed directory"
        cleanup_ok="true"
    else
        log_error "Manual cleanup failed: $SANDBOX_DIR_REAL"
        exit 1
    fi
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
