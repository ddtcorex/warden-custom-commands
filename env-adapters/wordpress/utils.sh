#!/usr/bin/env bash

# Helper function to get remote DB credentials from WordPress wp-config.php
# Usage: get_remote_db_info "HOST" "PORT" "USER" "DIR"
# Returns: newline-separated list of DB_VAR=VALUE
function get_remote_db_info() {
    local remote_host="$1"
    local remote_port="$2"
    local remote_user="$3"
    local remote_dir="$4"
    
    # Fetch DB creds via SSH
    local db_config=$(ssh ${SSH_OPTS} -p "${remote_port}" "${remote_user}@${remote_host}" "grep -E \"^\s*define\s*\(\s*['\\\"]DB_(NAME|USER|PASSWORD|HOST)\" \"${remote_dir}/wp-config.php\"")
    
    if [[ -z "${db_config}" ]]; then
        return 1
    fi

    local db_name=$(printf "%s" "${db_config}" | grep "DB_NAME" | head -n 1 | sed -E "s/.*['\"]DB_NAME['\"]\s*,\s*['\"](.*)['\"].*/\1/")
    local db_user=$(printf "%s" "${db_config}" | grep "DB_USER" | head -n 1 | sed -E "s/.*['\"]DB_USER['\"]\s*,\s*['\"](.*)['\"].*/\1/")
    local db_pass=$(printf "%s" "${db_config}" | grep "DB_PASSWORD" | head -n 1 | sed -E "s/.*['\"]DB_PASSWORD['\"]\s*,\s*['\"](.*)['\"].*/\1/")
    local db_host_raw=$(printf "%s" "${db_config}" | grep "DB_HOST" | head -n 1 | sed -E "s/.*['\"]DB_HOST['\"]\s*,\s*['\"](.*)['\"].*/\1/")

    local db_host=${db_host_raw%%:*}
    local db_port=${db_host_raw#*:}
    if [[ "${db_host}" == "${db_port}" ]]; then
        db_port=3306
    fi
    if [[ "${db_host}" == "localhost" ]]; then
        db_host="127.0.0.1"
    fi
    
    echo "DB_HOST=${db_host}"
    echo "DB_PORT=${db_port}"
    echo "DB_USERNAME=${db_user}"
    echo "DB_PASSWORD=${db_pass}"
    echo "DB_DATABASE=${db_name}"
}
