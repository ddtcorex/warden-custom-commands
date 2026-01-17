#!/usr/bin/env bash

# Helper function to get remote DB credentials from Magento 2 env.php
# Usage: get_remote_db_info "REMOTE_DIR" ["ENV_NAME"]
# Returns: newline-separated list of DB_VAR=VALUE
function get_remote_db_info() {
    local remote_dir="$1"
    local env_name="${2:-${ENV_SOURCE}}"
    
    # Determine PHP command for local decoding
    # Prefer local php if available, otherwise use warden container
    local php_cmd="php"
    if ! command -v php &> /dev/null; then
        # Check if warden is available (should be since this is a warden command)
        if command -v warden &> /dev/null; then
             # We might need to ensure container is up, but usually 'exec' will scream if not.
             # We assume if no local php, user relies on warden containers.
             php_cmd="warden env exec -T php-fpm php"
        else
             printf "Error: 'php' command not found locally and 'warden' not available for fallback.\n" >&2
             return 1
        fi
    fi

    # Get remote DB credentials from env.php via base64 encoded JSON for maximum reliability
    local php_code="\$a=@include \"${remote_dir}/app/etc/env.php\"; echo base64_encode(json_encode(\$a['db']['connection']['default']));"
    local db_info_json=$(warden remote-exec -e "${env_name}" -- php -r "${php_code}" 2>/dev/null)
    
    if [[ -z "${db_info_json}" ]]; then
        return 1
    fi
    
    # Decode locally using determined php command
    local db_host=$(${php_cmd} -r "\$a = json_decode(base64_decode(\$argv[1]), true); echo strpos(\$a['host'] ?? 'db', ':') === false ? (\$a['host'] ?? 'db') : explode(':', \$a['host'])[0];" -- "${db_info_json}")
    local db_port=$(${php_cmd} -r "\$a = json_decode(base64_decode(\$argv[1]), true); echo strpos(\$a['host'] ?? '', ':') === false ? '3306' : explode(':', \$a['host'])[1];" -- "${db_info_json}")
    local db_user=$(${php_cmd} -r "\$a = json_decode(base64_decode(\$argv[1]), true); echo \$a['username'] ?? '';" -- "${db_info_json}")
    local db_pass=$(${php_cmd} -r "\$a = json_decode(base64_decode(\$argv[1]), true); echo \$a['password'] ?? '';" -- "${db_info_json}")
    local db_name=$(${php_cmd} -r "\$a = json_decode(base64_decode(\$argv[1]), true); echo \$a['dbname'] ?? '';" -- "${db_info_json}")
    
    echo "DB_HOST=${db_host}"
    echo "DB_PORT=${db_port}"
    echo "DB_USERNAME=${db_user}"
    echo "DB_PASSWORD=${db_pass}"
    echo "DB_DATABASE=${db_name}"
}
