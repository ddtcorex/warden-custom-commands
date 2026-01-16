#!/usr/bin/env bash

# Helper function to get remote DB credentials from Symfony .env / .env.local
# Usage: get_remote_db_info "REMOTE_DIR" ["ENV_NAME"]
# Returns: newline-separated list of DB_VAR=VALUE
function get_remote_db_info() {
    local remote_dir="$1"
    local env_name="${2:-${ENV_SOURCE}}"
    
    # Fetch DB URL via SSH
    # Check .env.local first, then .env
    # We use -r to prevent backslash escaping issues in grep output, but SSH layer might still strict it.
    local db_url=$(warden remote-exec -e "${env_name}" -- grep -h -E '^DATABASE_URL=' "${remote_dir}/.env.local" "${remote_dir}/.env" 2>/dev/null | head -n 1)
    
    if [[ -z "${db_url}" ]]; then
        return 1
    fi

    # Parse standard URL format: db_type://db_user:db_pass@db_host:db_port/db_name...
    # Strip prefix
    db_url=${db_url#*=}
    # Strip quotes if present
    db_url=$(printf "%s" "${db_url}" | tr -d '"'"'")
    
    # Strip protocol
    db_url=${db_url#*://}
    
    local db_user_pass=${db_url%%@*}
    local db_user=${db_user_pass%%:*}
    local db_pass=${db_user_pass#*:}
    
    local db_host_port_name=${db_url#*@}
    local db_host_port=${db_host_port_name%%/*}
    local db_host=${db_host_port%%:*}
    local db_port=${db_host_port#*:}
    
    if [[ "${db_host}" == "${db_port}" ]]; then
        db_port=3306
    else
        db_port=${db_port%%\?*}
    fi
    
    local db_name_rest=${db_host_port_name#*/}
    local db_name=${db_name_rest%%\?*}

    db_host=${db_host:-127.0.0.1}
    db_port=${db_port:-3306}
    
    echo "DB_HOST=${db_host}"
    echo "DB_PORT=${db_port}"
    echo "DB_USERNAME=${db_user}"
    echo "DB_PASSWORD=${db_pass}"
    echo "DB_DATABASE=${db_name}"
}
