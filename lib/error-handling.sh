#!/usr/bin/env bash
# Error handling utilities for warden-custom-commands
# Source this file to get consistent error handling across all scripts

# Guard against multiple sourcing
[[ -n "${_ERROR_HANDLING_LOADED:-}" ]] && return 0
_ERROR_HANDLING_LOADED=1

# Colors for output
readonly COLOR_RED='\033[0;31m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_NC='\033[0m' # No Color

# Log an error message to stderr
# Usage: error "Something went wrong"
function error() {
    printf "${COLOR_RED}ERROR: %s${COLOR_NC}\n" "$*" >&2
}

# Log a warning message to stderr
# Usage: warning "This might be a problem"
function warning() {
    printf "${COLOR_YELLOW}WARNING: %s${COLOR_NC}\n" "$*" >&2
}

# Log an info message
# Usage: info "Processing..."
function info() {
    printf "${COLOR_GREEN}%s${COLOR_NC}\n" "$*"
}

# Log a fatal error and exit
# Usage: fatal "Cannot continue"
function fatal() {
    error "$@"
    exit 1
}

# Execute a command, logging a warning if it fails but continuing execution
# Usage: run_optional "description" command arg1 arg2
# Returns: 0 always (non-fatal)
function run_optional() {
    local description="$1"
    shift
    
    if ! "$@" 2>/dev/null; then
        [[ "${VERBOSE:-0}" -eq 1 ]] && warning "${description} (non-fatal, continuing)"
        return 0
    fi
    return 0
}

# Execute a command that may fail on first run (e.g., creating something that may exist)
# Usage: run_idempotent "Creating admin user" warden env exec php-fpm bin/magento admin:user:create ...
# Returns: 0 always (idempotent operations are expected to potentially fail)
function run_idempotent() {
    local description="$1"
    shift
    
    if ! "$@" 2>/dev/null; then
        [[ "${VERBOSE:-0}" -eq 1 ]] && info "${description} - already exists or skipped"
    fi
    return 0
}

# Execute a command and exit on failure
# Usage: run_required "Installing dependencies" composer install
function run_required() {
    local description="$1"
    shift
    
    if ! "$@"; then
        fatal "${description} failed"
    fi
}

# Try multiple commands until one succeeds
# Usage: try_commands "command1" "command2" "command3"
# Returns: Result of first successful command, or 1 if all fail
function try_commands() {
    for cmd in "$@"; do
        if eval "$cmd" 2>/dev/null; then
            return 0
        fi
    done
    return 1
}

# Detect available command from a list
# Usage: OPEN_CMD=$(detect_command xdg-open open start)
function detect_command() {
    for cmd in "$@"; do
        if command -v "$cmd" &>/dev/null; then
            printf "%s" "$cmd"
            return 0
        fi
    done
    return 1
}

# Source a file if it exists (for profile loading)
# Usage: source_if_exists ~/.bash_profile ~/.bashrc ~/.profile
function source_if_exists() {
    for file in "$@"; do
        if [[ -f "$file" ]]; then
            # shellcheck source=/dev/null
            source "$file" 2>/dev/null && return 0
        fi
    done
    return 1
}
