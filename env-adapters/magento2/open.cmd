#!/usr/bin/env bash
set -u

# env-variables is already sourced by the root dispatcher

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

function remote_db () {
    local db_info=$(ssh ${SSH_OPTS} -p "${ENV_SOURCE_PORT}" "${ENV_SOURCE_USER}@${ENV_SOURCE_HOST}" 'php -r "\$a=include \"'"${ENV_SOURCE_DIR}"'/app/etc/env.php\"; var_export(\$a[\"db\"][\"connection\"][\"default\"]);"')
    local db_host=$(warden env exec php-fpm php -r "\$a = ${db_info}; echo strpos(\$a['host'], ':') === false ? \$a['host'] : explode(':', \$a['host'])[0];")
    local db_port=$(warden env exec php-fpm php -r "\$a = ${db_info}; echo strpos(\$a['host'], ':') === false ? '3306' : explode(':', \$a['host'])[1];")
    local db_user=$(warden env exec php-fpm php -r "\$a = ${db_info}; echo \$a['username'];")
    local db_pass=$(warden env exec php-fpm php -r "\$a = ${db_info}; echo \$a['password'];")
    local db_name=$(warden env exec php-fpm php -r "\$a = ${db_info}; echo \$a['dbname'];")

    find_local_port "${db_port}"

    # URL encode credentials for special characters
    local encoded_user=$(urlencode "${db_user}")
    local encoded_pass=$(urlencode "${db_pass}")

    DB="mysql://${encoded_user}:${encoded_pass}@127.0.0.1:${LOCAL_PORT}/${db_name}"

    printf "SSH tunnel opened to \033[32m%s\033[0m at: \033[32m%s\033[0m\n" "${db_name}" "${DB}"
    printf "\nQuitting this command (with Ctrl+C or equivalent) will close the tunnel.\n\n"

    open_link "${DB}"

    ssh ${SSH_OPTS} -L "${LOCAL_PORT}:${db_host}:${db_port}" -N -p "${ENV_SOURCE_PORT}" "${ENV_SOURCE_USER}@${ENV_SOURCE_HOST}" || true
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

    ssh -L "${LOCAL_PORT}:${DB_ENV_NAME}:${REMOTE_PORT}" -N -p 2222 -i ~/.warden/tunnel/ssh_key user@tunnel.warden.test || true
}

function cloud_db() {
    magento-cloud tunnel:single -e "${ENV_SOURCE_HOST}" -p "${CLOUD_PROJECT}" -r database
}

function local_shell() {
    warden shell
}

function remote_shell() {
    ssh ${SSH_OPTS} -t -p "${ENV_SOURCE_PORT}" "${ENV_SOURCE_USER}@${ENV_SOURCE_HOST}" "cd ${ENV_SOURCE_DIR}; bash"
}

function cloud_shell() {
    magento-cloud ssh -e "${ENV_SOURCE_HOST}" -p "${CLOUD_PROJECT}"
}

function local_sftp() {
    printf "Not Supported.\n"
}

function remote_sftp() {
    local SFTP_LINK="sftp://${ENV_SOURCE_USER}@${ENV_SOURCE_HOST}:${ENV_SOURCE_PORT}${ENV_SOURCE_DIR}"
    printf "SFTP to \033[32m%s\033[0m at: \033[32m%s\033[0m\n" "${ENV_SOURCE_VAR}" "${SFTP_LINK}"
    open_link "${SFTP_LINK}"
}

function cloud_sftp() {
    local SFTP_LINK="sftp://$(magento-cloud ssh --pipe -e "${ENV_SOURCE_HOST}" -p "${CLOUD_PROJECT}")"
    printf "SFTP to \033[32m%s\033[0m at: \033[32m%s\033[0m\n" "${ENV_SOURCE_HOST}" "${SFTP_LINK}"
    open_link "${SFTP_LINK}"
}

function local_admin() {
    local APP_DOMAIN="https://${TRAEFIK_SUBDOMAIN}.${TRAEFIK_DOMAIN}/"
    local admin_path=$(php -r "\$a=include \"app/etc/env.php\"; echo \$a[\"backend\"][\"frontName\"];")
    printf "\033[32m%s\033[0m admin at: \033[32m%s%s\033[0m\n" "${ENV_SOURCE_VAR}" "${APP_DOMAIN}" "${admin_path}"
    open_link "${APP_DOMAIN}${admin_path}"
}

function remote_admin() {
    local admin_path=$(ssh ${SSH_OPTS} -p "${ENV_SOURCE_PORT}" "${ENV_SOURCE_USER}@${ENV_SOURCE_HOST}" 'php -r "\$a=include \"'"${ENV_SOURCE_DIR}"'/app/etc/env.php\"; echo \$a[\"backend\"][\"frontName\"];"')
    printf "\033[32m%s\033[0m admin at: \033[32m%s%s\033[0m\n" "${ENV_SOURCE_VAR}" "${ENV_SOURCE_URL}" "${admin_path}"
    if [[ -n "${ENV_SOURCE_URL:-}" ]]; then
        open_link "${ENV_SOURCE_URL}${admin_path}"
    fi
}

function cloud_admin() {
    local admin_path=$(magento-cloud variable:get -P value ADMIN_URL -e "${ENV_SOURCE_HOST}" -p "${CLOUD_PROJECT}")
    printf "\033[32m%s\033[0m admin at: \033[32m%s%s\033[0m\n" "${ENV_SOURCE_HOST}" "${ENV_SOURCE_URL}" "${admin_path}"
    if [[ -n "${ENV_SOURCE_URL:-}" ]]; then
        open_link "${ENV_SOURCE_URL}${admin_path}"
    fi
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

    ssh -L "${LOCAL_PORT}:${ES_ENV_NAME}:${REMOTE_PORT}" -N -p 2222 -i ~/.warden/tunnel/ssh_key user@tunnel.warden.test || true
}

function remote_elasticsearch() {
    printf "Not yet supported.\n"
    exit
}

function cloud_elasticsearch() {
    local ES_ENV_NAME='elasticsearch'
    magento-cloud service:list \
      --project="${CLOUD_PROJECT}" \
      --environment="${ENV_SOURCE_HOST}" \
      --columns=name \
      --format=plain \
      --no-header | grep -q 'opensearch' && ES_ENV_NAME='opensearch'

    magento-cloud tunnel:single -e "${ENV_SOURCE_HOST}" -p "${CLOUD_PROJECT}" -r "${ES_ENV_NAME}"
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
    if [[ -z "${CLOUD_PROJECT+x}" ]]; then
        remote_"${SERVICE}"
    else
        cloud_"${SERVICE}"
    fi
fi
