#!/usr/bin/env bash
# snapshot-utils.sh - Git directory state snapshot utilities
# This file is meant to be sourced, not executed directly

# ==============================================================================
# Directory State Management
# ==============================================================================

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
