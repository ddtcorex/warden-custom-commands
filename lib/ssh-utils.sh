#!/usr/bin/env bash
#
# Shared SSH Utilities
#

# Build common SSH options used across all commands
# Usage: ssh_opts=$(build_ssh_opts)
function build_ssh_opts() {
    # SSH KeepAlive is added to prevent long-running processes (like stream-db) from dropping
    local opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes -o ServerAliveInterval=60 -o ServerAliveCountMax=10"
    
    if [[ -n "${SSH_AUTH_SOCK:-}" ]]; then
        opts="${opts} -A"
    fi
    
    # Allow overriding identity file usage via environment variable
    if [[ "${WARDEN_SSH_IDENTITIES_ONLY:-0}" -eq 1 ]]; then
        opts="${opts} -o IdentitiesOnly=yes"
    fi
    
    if [[ -n "${WARDEN_SSH_IDENTITY_FILE:-}" ]]; then
        opts="${opts} -i ${WARDEN_SSH_IDENTITY_FILE}"
    fi
    
    echo "${opts}"
}

# Normalize environment name aliases
# Usage: env_name=$(normalize_env_name "stag") -> "STAGING"
function normalize_env_name() {
    local input="${1}"
    local upper
    upper=$(printf "%s" "${input}" | tr '[:lower:]' '[:upper:]' | tr -c '[:alnum:]_' '_')
    
    case "${upper}" in
        PRODUCTION)
            echo "PROD"
            ;;
        STAG|STG|PREPROD)
            echo "STAGING"
            ;;
        DEVELOP|DEVELOPER|DEVELOPMENT)
            echo "DEV"
            ;;
        *)
            echo "${upper}"
            ;;
    esac
}

# Get remote environment configuration variables by prefix
# Usage: eval $(get_remote_env "STAGING" "ENV_SOURCE")
# This exports: ENV_SOURCE_HOST, ENV_SOURCE_USER, etc.
function get_remote_env() {
    local prefix="${1}" # e.g. PROD, STAGING, DEV
    local var_prefix="${2:-ENV_SOURCE}" # e.g. ENV_SOURCE, DEST_REMOTE
    
    local host_var="REMOTE_${prefix}_HOST"
    local user_var="REMOTE_${prefix}_USER"
    local port_var="REMOTE_${prefix}_PORT"
    local path_var="REMOTE_${prefix}_PATH"
    local url_var="REMOTE_${prefix}_URL"
    
    # We use indirect reference to check if the HOST variable exists
    if [[ -n "${!host_var:-}" ]]; then
        echo "export ${var_prefix}_HOST='${!host_var}'"
        echo "export ${var_prefix}_USER='${!user_var:-}'"
        echo "export ${var_prefix}_PORT='${!port_var:-22}'"
        echo "export ${var_prefix}_DIR='${!path_var:-}'"
        echo "export ${var_prefix}_URL='${!url_var:-}'"
        return 0
    else
        return 1
    fi
}
