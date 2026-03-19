#!/usr/bin/env bash
set -euo pipefail

[[ ! "${WARDEN_DIR:-}" ]] && >&2 printf "\033[31mNot intended to run directly!\033[0m\n" && exit 1

# env-variables is already sourced by the root dispatcher

SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
source "${SCRIPT_DIR}/utils.sh"

function open_link() {
    if [[ "${OPEN_CL:-0}" -eq "1" ]]; then
        # Detect available opener command
        local OPEN
        OPEN=$(command -v xdg-open || command -v open || command -v start || true)
        if [[ -n "${OPEN:-}" ]]; then
            "${OPEN}" "${1}"
        fi
    fi
}

function find_local_port() {
    LOCAL_PORT="${1}"

    while [[ $(lsof -Pi :"${LOCAL_PORT}" -sTCP:LISTEN -t 2>/dev/null) ]]; do
        LOCAL_PORT=$((LOCAL_PORT+1))
    done
}

# URL encode special characters for database connection strings
function urlencode() {
    local string="${1}"
    local strlen=${#string}
    local encoded=""
    local pos c o

    for (( pos=0 ; pos<strlen ; pos++ )); do
        c=${string:$pos:1}
        case "$c" in
            [-_.~a-zA-Z0-9] ) o="$c" ;;
            * ) printf -v o '%%%02X' "'$c" ;;
        esac
        encoded+="$o"
    done
    printf "%s" "$encoded"
}

function get_db_info() {
    DB_USER=$(warden env exec -T db printenv MYSQL_USER)
    DB_PASS=$(warden env exec -T db printenv MYSQL_PASSWORD)
    DB_NAME=$(warden env exec -T db printenv MYSQL_DATABASE)
}

function remote_db () {
    local db_info=$(get_remote_db_info "${ENV_SOURCE_DIR}")
    local db_host=$(echo "${db_info}" | grep "^DB_HOST=" | cut -d= -f2-)
    local db_port=$(echo "${db_info}" | grep "^DB_PORT=" | cut -d= -f2-)
    local db_user=$(echo "${db_info}" | grep "^DB_USERNAME=" | cut -d= -f2-)
    local db_pass=$(echo "${db_info}" | grep "^DB_PASSWORD=" | cut -d= -f2-)
    local db_name=$(echo "${db_info}" | grep "^DB_DATABASE=" | cut -d= -f2-)

    find_local_port "${db_port}"

    # URL encode credentials for special characters
    local encoded_user=$(urlencode "${db_user}")
    local encoded_pass=$(urlencode "${db_pass}")

    local DB="mysql://${encoded_user}:${encoded_pass}@127.0.0.1:${LOCAL_PORT}/${db_name}"

    printf "SSH tunnel opened to \033[32m%s\033[0m at: \033[32m%s\033[0m\n" "${db_name}" "${DB}"
    printf "\nQuitting this command (with Ctrl+C or equivalent) will close the tunnel.\n\n"

    open_link "${DB}"

    # SSH tunnel - user terminates with Ctrl+C, non-zero exit is expected
    ssh ${SSH_OPTS:-} -L "${LOCAL_PORT}:${db_host}:${db_port}" -N -p "${ENV_SOURCE_PORT}" "${ENV_SOURCE_USER}@${ENV_SOURCE_HOST}" || true
}

function local_db() {
    local REMOTE_PORT=3306
    find_local_port "${REMOTE_PORT}"

    get_db_info
    
    # Fallback if exec failed
    DB_USER=${DB_USER:-magento}
    DB_PASS=${DB_PASS:-magento}
    DB_NAME=${DB_NAME:-magento}

    # URL encode credentials for special characters
    local encoded_user=$(urlencode "${DB_USER}")
    local encoded_pass=$(urlencode "${DB_PASS}")

    local DB_ENV_NAME="${WARDEN_ENV_NAME}-db-1"
    local DB="mysql://${encoded_user}:${encoded_pass}@127.0.0.1:${LOCAL_PORT}/${DB_NAME}"

    printf "SSH tunnel opened to \033[32m%s\033[0m at: \033[32m%s\033[0m\n" "${DB_ENV_NAME}" "${DB}"
    printf "\nQuitting this command (with Ctrl+C or equivalent) will close the tunnel.\n\n"

    open_link "${DB}"

    # SSH tunnel - user terminates with Ctrl+C, non-zero exit is expected
    ssh ${SSH_OPTS:-} -L "${LOCAL_PORT}:${DB_ENV_NAME}:${REMOTE_PORT}" -N -p 2222 -i ~/.warden/tunnel/ssh_key user@tunnel.warden.test || true
}

function local_shell() {
    warden shell
}

function remote_shell() {
    warden remote-exec -e "${ENV_SOURCE_VAR}" -- bash
}

function local_sftp() {
    printf "Not Supported.\n"
}

function remote_sftp() {
    local SFTP_LINK="sftp://${ENV_SOURCE_USER}@${ENV_SOURCE_HOST}:${ENV_SOURCE_PORT}${ENV_SOURCE_DIR}"
    printf "SFTP to \033[32m%s\033[0m at: \033[32m%s\033[0m\n" "${ENV_SOURCE_VAR}" "${SFTP_LINK}"
    open_link "${SFTP_LINK}"
}

function local_admin() {
    local APP_DOMAIN="https://${TRAEFIK_SUBDOMAIN}.${TRAEFIK_DOMAIN}/"
    local admin_path=$(warden env exec -T php-fpm php <<EOF
<?php
echo (string)(@simplexml_load_file('/var/www/html/app/etc/local.xml'))->admin->routers->adminhtml->args->frontName ?: 'admin';
EOF
)
    if [[ -z "${admin_path}" ]]; then admin_path="admin"; fi
    printf "\033[32m%s\033[0m admin at: \033[32m%s%s\033[0m\n" "${ENV_SOURCE_VAR}" "${APP_DOMAIN}" "${admin_path}"
    open_link "${APP_DOMAIN}${admin_path}"
}

function remote_admin() {
    local admin_path=$(warden remote-exec -e "${ENV_SOURCE_VAR}" -- php <<EOF
<?php
echo (string)(@simplexml_load_file('${ENV_SOURCE_DIR}/app/etc/local.xml'))->admin->routers->adminhtml->args->frontName ?: 'admin';
EOF
)
    if [[ -z "${admin_path}" ]]; then admin_path="admin"; fi
    printf "\033[32m%s\033[0m admin at: \033[32m%s%s\033[0m\n" "${ENV_SOURCE_VAR}" "${ENV_SOURCE_URL}" "${admin_path}"
    if [[ -n "${ENV_SOURCE_URL:-}" ]]; then
        open_link "${ENV_SOURCE_URL}${admin_path}"
    fi
}

function local_elasticsearch() {
    printf "Not yet supported for Magento 1.\n"
    exit
}

function remote_elasticsearch() {
    printf "Not yet supported for Magento 1.\n"
    exit
}


# Default to LOCAL if no -e specified or -e local
ENV_SOURCE_VAR="${ENV_SOURCE:-LOCAL}"
if [[ "${ENV_SOURCE_DEFAULT:-0}" -eq "1" ]] || [[ "${ENV_SOURCE:-}" == "local" ]]; then
    ENV_SOURCE_VAR="LOCAL"
elif [[ -z "${!ENV_SOURCE_HOST_VAR+x}" ]]; then
    printf "Invalid environment '%s'\n" "${ENV_SOURCE:-}" >&2
    exit 2
fi

OPEN_CL=0

while (( "$#" )); do
    case "$1" in
        -a)
            OPEN_CL=1
            shift
            ;;
        -a=*)
            if [[ "${1#*=}" =~ ^(true|1)$ ]]; then OPEN_CL=1; fi
            shift
            ;;
        *)
            shift
            ;;
    esac
done

SERVICE=""

if [[ -z "${WARDEN_PARAMS[0]+x}" ]]; then
    printf "Please specify the service you want to open\n" >&2
    exit 2
else
    SERVICE="${WARDEN_PARAMS[0]}"
fi

VALID_SERVICES=( 'db' 'shell' 'sftp' 'elasticsearch' 'opensearch' 'admin' )
IS_VALID=$(array_contains VALID_SERVICES "${SERVICE}")

if [[ "${IS_VALID}" -eq "1" ]]; then
    printf "Invalid service. Valid services: \n" >&2
    printf "  ${VALID_SERVICES[*]}\n" >&2
    exit 2
fi

if [[ "${SERVICE}" = "opensearch" ]]; then
    SERVICE="elasticsearch"
fi

if [[ "${ENV_SOURCE_VAR}" = "LOCAL" ]]; then
    local_"${SERVICE}"
else
    remote_"${SERVICE}"
fi
