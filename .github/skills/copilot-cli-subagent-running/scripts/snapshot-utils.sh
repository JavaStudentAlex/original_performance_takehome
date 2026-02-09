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
    # The tree object is written to .git/objects (cleaned up by periodic git gc).
    local repo="$1"
    local tmpdir idx tree

    tmpdir="$(mktemp -d -t subagent-index.XXXXXX)"
    idx="$tmpdir/index"

    if ! GIT_INDEX_FILE="$idx" git -C "$repo" add -A >/dev/null 2>&1; then
        log_error "snapshot_directory_state: git add failed in $repo"
        rm -rf "$tmpdir"
        return 1
    fi

    tree="$(GIT_INDEX_FILE="$idx" git -C "$repo" write-tree)" || {
        log_error "snapshot_directory_state: git write-tree failed in $repo"
        rm -rf "$tmpdir"
        return 1
    }

    rm -rf "$tmpdir"
    echo "$tree"
}
