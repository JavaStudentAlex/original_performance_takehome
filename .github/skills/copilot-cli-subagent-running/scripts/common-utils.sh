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

# ==============================================================================
# SQL Utilities
# ==============================================================================

# Helper for SQL-safe single-quote escaping
_sql_esc() {
    printf '%s' "$1" | sed "s/'/''/g"
}
