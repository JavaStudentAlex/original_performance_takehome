#!/usr/bin/env bash
# common-utils.sh - Shared utilities for agent runner scripts
# This file is meant to be sourced, not executed directly

# ==============================================================================
# Logging Functions
# ==============================================================================

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

# ==============================================================================
# Time Utilities
# ==============================================================================

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

make_timestamp() {
    date -u +"%Y%m%dT%H%M%SZ"
}

# ==============================================================================
# Git Utilities
# ==============================================================================

ensure_in_git_repo() {
    if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
        log_error "Not inside a git repository."
        exit 1
    fi
}

# ==============================================================================
# Validation
# ==============================================================================

check_copilot_installed() {
    if ! command -v copilot &> /dev/null; then
        log_error "GitHub Copilot CLI is not installed."
        log_error "Install with: npm install -g @github/copilot"
        exit 1
    fi
}

check_sqlite_installed() {
    if ! command -v sqlite3 &> /dev/null; then
        log_error "sqlite3 is required for agent run tracking but is not installed."
        exit 1
    fi
}

# ==============================================================================
# SQL Utilities
# ==============================================================================

# Escape a value for use inside double-quoted sqlite3 .param set.
# Escapes backslashes and double-quotes so the value survives sqlite3 parsing.
# Values with embedded newlines are rejected (not expected in our data model).
_param_esc() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# Run a SQL statement against the agent-tracking database.
# Uses .timeout (5s) to handle concurrent access.
# Usage: db_exec <db_file> <sql> [args...]
#   - Use ?1, ?2, ... placeholders in SQL
#   - Pass corresponding values as positional args
db_exec() {
    local db_file="$1"; shift
    local sql="$1"; shift

    local param_cmds=""
    local i=1
    for val in "$@"; do
        param_cmds="${param_cmds}.param set ?${i} \"$(_param_esc "$val")\"
"
        i=$((i + 1))
    done

    sqlite3 "$db_file" <<EOF
.timeout 5000
.param init
${param_cmds}${sql}
EOF
}

# Variant that returns query output (e.g., INSERT...SELECT).
# Same interface as db_exec.
db_query() {
    local db_file="$1"; shift
    local sql="$1"; shift

    local param_cmds=""
    local i=1
    for val in "$@"; do
        param_cmds="${param_cmds}.param set ?${i} \"$(_param_esc "$val")\"
"
        i=$((i + 1))
    done

    sqlite3 "$db_file" <<EOF
.timeout 5000
.param init
${param_cmds}${sql}
EOF
}
