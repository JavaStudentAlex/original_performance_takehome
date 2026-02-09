#!/usr/bin/env bash
# cleanup-agent-sandbox.sh - Cleans up agent sandbox worktree
#
# Usage:
#   ./cleanup-agent-sandbox.sh <sandbox-dir>
#
# Examples:
#   ./cleanup-agent-sandbox.sh .agent-sandboxes/memory-opt-expert-20260208T134500Z

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
    echo "" >&2
    echo "Cleans up an agent sandbox worktree and branch." >&2
    exit 1
fi

SANDBOX_DIR="$1"

if [[ ! -d "$SANDBOX_DIR" ]]; then
    log_error "Sandbox directory not found: $SANDBOX_DIR"
    exit 1
fi

# Get the branch name before removing worktree
BRANCH_NAME=""
if [[ -d "$SANDBOX_DIR/.git" ]] || [[ -f "$SANDBOX_DIR/.git" ]]; then
    BRANCH_NAME=$(git -C "$SANDBOX_DIR" branch --show-current 2>/dev/null || echo "")
fi

log_info "Cleaning up sandbox: $SANDBOX_DIR"

# Remove worktree
if git worktree remove "$SANDBOX_DIR" --force >/dev/null 2>&1; then
    log_info "Worktree removed"
else
    log_error "Failed to remove worktree, trying manual cleanup"
    rm -rf "$SANDBOX_DIR"
fi

# Delete the branch if we got it
if [[ -n "$BRANCH_NAME" ]]; then
    if git branch -D "$BRANCH_NAME" >/dev/null 2>&1; then
        log_info "Branch deleted: $BRANCH_NAME"
    else
        log_info "Branch already deleted or not found: $BRANCH_NAME"
    fi
fi

log_info "Sandbox cleaned up successfully"
