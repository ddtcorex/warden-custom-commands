#!/usr/bin/env bash

# Helper function to get remote DB credentials from WordPress wp-config.php
# Usage: get_remote_db_info "REMOTE_DIR" ["ENV_NAME"]
# Returns: newline-separated list of DB_VAR=VALUE
function get_remote_db_info() {
    local remote_dir="$1"
    local env_name="${2:-${ENV_SOURCE}}"
    
    # Fetch DB creds via SSH
    local db_config=$(warden remote-exec -e "${env_name}" -- grep -E "^\s*define\s*\(\s*['\\\"]DB_(NAME|USER|PASSWORD|HOST)" "${remote_dir}/wp-config.php" 2>/dev/null)
    
    if [[ -z "${db_config}" ]]; then
        return 1
    fi

    local db_name=$(printf "%s" "${db_config}" | grep "DB_NAME" | awk 'NR==1' | sed -E "s/.*['\"]DB_NAME['\"]\s*,\s*['\"](.*)['\"].*/\1/")
    local db_user=$(printf "%s" "${db_config}" | grep "DB_USER" | awk 'NR==1' | sed -E "s/.*['\"]DB_USER['\"]\s*,\s*['\"](.*)['\"].*/\1/")
    local db_pass=$(printf "%s" "${db_config}" | grep "DB_PASSWORD" | awk 'NR==1' | sed -E "s/.*['\"]DB_PASSWORD['\"]\s*,\s*['\"](.*)['\"].*/\1/")
    local db_host_raw=$(printf "%s" "${db_config}" | grep "DB_HOST" | awk 'NR==1' | sed -E "s/.*['\"]DB_HOST['\"]\s*,\s*['\"](.*)['\"].*/\1/")

    local db_host=${db_host_raw%%:*}
    local db_port=${db_host_raw#*:}
    if [[ "${db_host}" == "${db_port}" ]]; then
        db_port=3306
    fi
    if [[ "${db_host}" == "localhost" ]]; then
        db_host="127.0.0.1"
    fi

    local db_prefix=$(warden remote-exec -e "${env_name}" -- grep -E "^\s*\\\$table_prefix\s*=" "${remote_dir}/wp-config.php" 2>/dev/null | sed -E "s/.*['\"](.*)['\"].*/\1/")
    db_prefix=${db_prefix:-wp_}
    
    echo "DB_HOST=${db_host}"
    echo "DB_PORT=${db_port}"
    echo "DB_USERNAME=${db_user}"
    echo "DB_PASSWORD=${db_pass}"
    echo "DB_DATABASE=${db_name}"
    echo "DB_PREFIX=${db_prefix}"
}

# List of tables to ignore during standard (no-noise flag) database dumps
IGNORED_TABLES=(
    'options_bak'
    'options_replica'
    'options_tmp'
    'redirection_404'
    'wflogs'
)

# List of tables containing sensitive data to be ignored when --no-pii is passed
SENSITIVE_TABLES=(
    'commentmeta'
    'comments'
    'usermeta'
    'users'
)
