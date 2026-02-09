#!/usr/bin/env bash
# create-agent-sandbox.sh - Creates an isolated git worktree for agent execution
#
# Usage:
#   ./create-agent-sandbox.sh <agent-name> [<base-ref>]
#
# Examples:
#   ./create-agent-sandbox.sh memory-opt-expert
#   ./create-agent-sandbox.sh memory-opt-expert HEAD

set -euo pipefail

# Directory containing this script
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared utilities
source "$SCRIPTS_DIR/common-utils.sh"

# Safety: redirect stdout to stderr by default, so only explicit
# machine-readable output goes to the caller's stdout.
exec 3>&1 1>&2

# ==============================================================================
# Configuration
# ==============================================================================

SANDBOX_BASE_DIR=".agent-sandboxes"

# ==============================================================================
# Main
# ==============================================================================

if [[ $# -lt 1 ]]; then
    echo "Usage: $(basename "$0") <agent-name> [<base-ref>]" >&2
    echo "" >&2
    echo "Creates an isolated git worktree for agent execution." >&2
    echo "" >&2
    echo "Arguments:" >&2
    echo "  agent-name    Name of the agent (e.g., memory-opt-expert)" >&2
    echo "  base-ref      Git ref to branch from (default: HEAD)" >&2
    exit 1
fi

AGENT_NAME="$1"
BASE_REF="${2:-HEAD}"

# Ensure we're in a git repo
if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
    log_error "Not inside a git repository."
    exit 1
fi

PROJECT_ROOT="$(git rev-parse --show-toplevel)"
cd "$PROJECT_ROOT"

# Generate unique identifiers
TIMESTAMP="$(make_timestamp)"
RUN_ID="${TIMESTAMP}-$$"
BRANCH_NAME="agent/${AGENT_NAME}/${RUN_ID}"
SANDBOX_DIR="${PROJECT_ROOT}/${SANDBOX_BASE_DIR}/${AGENT_NAME}-${RUN_ID}"

# Create sandbox base directory if needed
mkdir -p "$SANDBOX_BASE_DIR"

log_info "Creating sandbox for agent: $AGENT_NAME"
log_info "Branch: $BRANCH_NAME"
log_info "Directory: $SANDBOX_DIR"

# Create worktree (stdout already redirected to stderr via exec 3>&1 1>&2)
if ! git worktree add "$SANDBOX_DIR" -b "$BRANCH_NAME" "$BASE_REF" >/dev/null; then
    log_error "Failed to create worktree at $SANDBOX_DIR (branch=$BRANCH_NAME, base=$BASE_REF)"
    exit 1
fi

# Machine-readable output — only these lines go to caller's stdout (fd 3)
echo "SANDBOX_DIR=$SANDBOX_DIR" >&3
echo "BRANCH_NAME=$BRANCH_NAME" >&3
echo "RUN_ID=$RUN_ID" >&3
echo "AGENT_NAME=$AGENT_NAME" >&3

log_info "Sandbox created successfully"
