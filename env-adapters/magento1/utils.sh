#!/usr/bin/env bash
set -euo pipefail

[[ ! "${WARDEN_DIR:-}" ]] && >&2 printf "\033[31mNot intended to run directly!\033[0m\n" && exit 1

# Helper function to get remote DB credentials from Magento 1 local.xml
# Usage: get_remote_db_info "HOST" "PORT" "USER" "DIR"
# Returns: newline-separated list of DB_VAR=VALUE
function get_remote_db_info() {
    local remote_host="$1"
    local remote_port="$2"
    local remote_user="$3"
    local remote_dir="$4"

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

    # Get remote DB credentials from local.xml via base64 encoded JSON for maximum reliability
    # We pass the PHP script via stdin to avoid SSH command quoting issues with $ variables
    local db_info_json=$(ssh ${SSH_OPTS:-} -o IdentityAgent=none -p "${remote_port}" "${remote_user}@${remote_host}" "php" 2>/dev/null <<EOF
<?php
\$x=@simplexml_load_file("${remote_dir}/app/etc/local.xml"); 
\$c=\$x->global->resources->default_setup->connection; 
echo base64_encode(json_encode(['host'=>(string)\$c->host,'username'=>(string)\$c->username,'password'=>(string)\$c->password,'dbname'=>(string)\$c->dbname]));
EOF
)

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
