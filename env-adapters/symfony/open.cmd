#!/usr/bin/env bash
set -u

# env-variables is already sourced by the root dispatcher

SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
source "${SCRIPT_DIR}/utils.sh"

function open_link() {
    if [[ "${OPEN_CL:-0}" -eq "1" ]]; then
        local OPEN=$(command -v xdg-open || command -v open || command -v start || true)
        if [[ -n "${OPEN:-}" ]]; then
            "${OPEN}" "${1}"
        fi
    fi
}

function find_local_port() {
    LOCAL_PORT="${1}"

    while [[ $(lsof -Pi :"${LOCAL_PORT}" -sTCP:LISTEN -t) ]]; do
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

function local_db() {
    local REMOTE_PORT=3306
    find_local_port "${REMOTE_PORT}"

    get_db_info
    
    # Fallback
    DB_USER=${DB_USER:-symfony}
    DB_PASS=${DB_PASS:-symfony}
    DB_NAME=${DB_NAME:-symfony}

    # URL encode credentials for special characters
    local encoded_user=$(urlencode "${DB_USER}")
    local encoded_pass=$(urlencode "${DB_PASS}")

    local DB_ENV_NAME="${WARDEN_ENV_NAME}-db-1"
    local DB="mysql://${encoded_user}:${encoded_pass}@127.0.0.1:${LOCAL_PORT}/${DB_NAME}"

    printf "SSH tunnel opened to \033[32m%s\033[0m at: \033[32m%s\033[0m\n" "${DB_ENV_NAME}" "${DB}"
    printf "\nQuitting this command (with Ctrl+C or equivalent) will close the tunnel.\n\n"

    open_link "${DB}"

    ssh ${SSH_OPTS} -L "${LOCAL_PORT}:${DB_ENV_NAME}:${REMOTE_PORT}" -N -p 2222 -i ~/.warden/tunnel/ssh_key user@tunnel.warden.test || true
}

function local_shell() {
    warden shell
}

function local_sftp() {
    printf "Not Supported.\n"
}

function local_admin() {
    local APP_DOMAIN="https://${TRAEFIK_SUBDOMAIN}.${TRAEFIK_DOMAIN}/"
    printf "\033[32m%s\033[0m app at: \033[32m%s\033[0m\n" "${ENV_SOURCE_VAR}" "${APP_DOMAIN}"
    open_link "${APP_DOMAIN}"
}

function local_elasticsearch() {
    local REMOTE_PORT=9200
    find_local_port "${REMOTE_PORT}"

    local ES_ENV_NAME=""
    if [[ "${WARDEN_ELASTICSEARCH:-0}" -eq "1" ]] || [[ "${WARDEN_OPENSEARCH:-0}" -eq "1" ]]; then
        if [[ "${WARDEN_OPENSEARCH:-0}" -eq "1" ]]; then
            ES_ENV_NAME="${WARDEN_ENV_NAME}-opensearch-1"
        else
            ES_ENV_NAME="${WARDEN_ENV_NAME}-elasticsearch-1"
        fi
    else
        printf "Elastic Search or Open Search not enabled for project\n"
        exit
    fi

    local ES="http://localhost:${LOCAL_PORT}"

    printf "Elastic Search tunnel opened to \033[32m%s\033[0m at: \033[32m%s\033[0m\n" "${ES_ENV_NAME}" "${ES}"
    printf "\nQuitting this command (with Ctrl+C or equivalent) will close the tunnel.\n\n"

    open_link "${ES}"

    ssh ${SSH_OPTS} -L "${LOCAL_PORT}:${ES_ENV_NAME}:${REMOTE_PORT}" -N -p 2222 -i ~/.warden/tunnel/ssh_key user@tunnel.warden.test || true
}

function remote_db() {
    # Symfony uses .env for DB config (usually DATABASE_URL). We fetch it via helper.
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

    ssh ${SSH_OPTS} -L "${LOCAL_PORT}:${db_host}:${db_port}" -N -p "${ENV_SOURCE_PORT}" "${ENV_SOURCE_USER}@${ENV_SOURCE_HOST}" || true
}

function remote_shell() {
    warden remote-exec -e "${ENV_SOURCE_VAR}" -- bash
}

function remote_sftp() {
    local SFTP_LINK="sftp://${ENV_SOURCE_USER}@${ENV_SOURCE_HOST}:${ENV_SOURCE_PORT}${ENV_SOURCE_DIR}"
    printf "SFTP to \033[32m%s\033[0m at: \033[32m%s\033[0m\n" "${ENV_SOURCE_VAR}" "${SFTP_LINK}"
    open_link "${SFTP_LINK}"
}

function remote_admin() {
    if [[ -n "${ENV_SOURCE_URL:-}" ]]; then
        printf "\033[32m%s\033[0m app at: \033[32m%s\033[0m\n" "${ENV_SOURCE_VAR}" "${ENV_SOURCE_URL}"
        open_link "${ENV_SOURCE_URL}"
    else
        printf "REMOTE_%s_URL is not set in .env\n" "${ENV_SOURCE_VAR}" >&2
    fi
}

# Default to LOCAL if no -e specified or -e local
ENV_SOURCE_VAR="${ENV_SOURCE:-LOCAL}"
if [[ "${ENV_SOURCE_DEFAULT:-0}" -eq "1" ]] || [[ "${ENV_SOURCE:-}" == "local" ]]; then
    ENV_SOURCE_VAR="LOCAL"
elif [[ -z "${ENV_SOURCE_HOST:-}" ]]; then
    printf "Invalid environment '%s' or missing configuration.\n" "${ENV_SOURCE:-}" >&2
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

if [[ "${SERVICE}" = "opensearch" ]]; then
    SERVICE="elasticsearch"
fi

if [[ "${ENV_SOURCE_VAR}" = "LOCAL" ]]; then
    if type "local_${SERVICE}" &>/dev/null; then
        local_"${SERVICE}"
    else
        printf "Service '%s' not supported.\n" "${SERVICE}" >&2
        exit 1
    fi
else
    if type "remote_${SERVICE}" &>/dev/null; then
        remote_"${SERVICE}"
    else
        printf "Service '%s' not supported remotely.\n" "${SERVICE}" >&2
        exit 1
    fi
fi
