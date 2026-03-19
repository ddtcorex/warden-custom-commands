#!/usr/bin/env bash

# Helper function to get remote DB credentials (supports .env and .env.php)
# Usage: get_remote_db_info "REMOTE_DIR" ["ENV_NAME"]
# Returns: newline-separated list of DB_VAR=VALUE
function get_remote_db_info() {
    local remote_dir="$1"
    local env_name="${2:-${ENV_SOURCE}}"
    
    # Try .env first
    local db_info=$(warden remote-exec -e "${env_name}" -- grep -h -E '^(DB_HOST|DB_PORT|DB_DATABASE|DB_USERNAME|DB_PASSWORD)=' "${remote_dir}/.env" 2>/dev/null)
    
    local db_name=$(printf "%s" "${db_info}" | grep "^DB_DATABASE=" | tail -n 1 | cut -d= -f2- | tr -d '"'"'")
    
    # Fallback to .env.php for Laravel 4+ legacy projects
    if [[ -z "${db_name}" ]]; then
        local php_code="\$f=\"${remote_dir}/.env.php\"; if(file_exists(\$f)) { \$c=include \$f; if(is_array(\$c)) { echo \"DB_HOST=\" . (\$c[\"DB_HOST\"]??\$c[\"DATABASE_HOST\"]??\"127.0.0.1\") . PHP_EOL; echo \"DB_PORT=\" . (\$c[\"DB_PORT\"]??\$c[\"DATABASE_PORT\"]??\"3306\") . PHP_EOL; echo \"DB_DATABASE=\" . (\$c[\"DB_DATABASE\"]??\$c[\"DATABASE_NAME\"]??\"\") . PHP_EOL; echo \"DB_USERNAME=\" . (\$c[\"DB_USERNAME\"]??\$c[\"DATABASE_USER\"]??\"\") . PHP_EOL; echo \"DB_PASSWORD=\" . (\$c[\"DB_PASSWORD\"]??\$c[\"DATABASE_PASSWORD\"]??\"\") . PHP_EOL; echo \"DB_PREFIX=\" . (\$c[\"DB_PREFIX\"]??\"\") . PHP_EOL; } }"
        
        db_info=$(warden remote-exec -e "${env_name}" -- php -r "${php_code}" 2>/dev/null)
    else
        local db_prefix=$(printf "%s" "${db_info}" | grep "^DB_PREFIX=" | tail -n 1 | cut -d= -f2- | tr -d '"'"'")
        db_info="${db_info}"$'\n'"DB_PREFIX=${db_prefix}"
    fi
    
    printf "%s" "${db_info}"
}

# List of tables to ignore during standard (no-noise flag) database dumps
IGNORED_TABLES=(
    'cache'
    'cache_locks'
    'failed_jobs'
    'job_batches'
    'jobs'
    'sessions'
    'telescope_entries'
    'telescope_entries_tags'
    'telescope_monitoring'
)

# List of tables containing sensitive data to be ignored when --no-pii is passed
SENSITIVE_TABLES=(
    'password_reset_tokens'
    'password_resets'
    'personal_access_tokens'
    'users'
)
