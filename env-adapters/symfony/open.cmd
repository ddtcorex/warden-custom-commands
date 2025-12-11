#!/usr/bin/env bash
[[ ! ${WARDEN_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

source "${WARDEN_HOME_DIR:-~/.warden}/commands/env-variables"

function open_link() {
    if [[ "$OPEN_CL" -eq "1" ]]; then
        OPEN=$(which xdg-open || which open || which start) || true
        if [ -n "$OPEN" ]; then
            $OPEN "${1}"
        fi
    fi
}

function findLocalPort() {
    LOCAL_PORT=$1

    while [[ $(lsof -Pi :$LOCAL_PORT -sTCP:LISTEN -t) ]]; do
        LOCAL_PORT=$((LOCAL_PORT+1))
    done
}

function get_db_info() {
    DB_USER=$(warden env exec -T db printenv MYSQL_USER)
    DB_PASS=$(warden env exec -T db printenv MYSQL_PASSWORD)
    DB_NAME=$(warden env exec -T db printenv MYSQL_DATABASE)
}

function local_db() {
    REMOTE_PORT=3306
    findLocalPort $REMOTE_PORT

    get_db_info
    
    # Fallback
    DB_USER=${DB_USER:-symfony}
    DB_PASS=${DB_PASS:-symfony}
    DB_NAME=${DB_NAME:-symfony}

    DB_ENV_NAME="$WARDEN_ENV_NAME"-db-1
    DB="mysql://${DB_USER}:${DB_PASS}@127.0.0.1:$LOCAL_PORT/${DB_NAME}"

    echo -e "SSH tunnel opened to \033[32m$DB_ENV_NAME\033[0m at: \033[32m$DB\033[0m"
    echo
    echo "Quitting this command (with Ctrl+C or equivalent) will close the tunnel."
    echo

    open_link $DB

    ssh -L "$LOCAL_PORT":"$DB_ENV_NAME":"$REMOTE_PORT" -N -p 2222 -i ~/.warden/tunnel/ssh_key user@tunnel.warden.test || true
}

function local_shell() {
    warden shell
}

function local_sftp() {
    echo "Not Supported."
}

function local_admin() {
    APP_DOMAIN="https://${TRAEFIK_SUBDOMAIN}.${TRAEFIK_DOMAIN}/"
    echo -e "\033[32m$ENV_SOURCE_VAR\033[0m app at: \033[32m${APP_DOMAIN}\033[0m"
    open_link "${APP_DOMAIN}"
}

function local_elasticsearch() {
    REMOTE_PORT=9200
    findLocalPort $REMOTE_PORT

    if [[ "$WARDEN_ELASTICSEARCH" -eq "1" ]] || [[ "$WARDEN_OPENSEARCH" -eq "1" ]]; then
        if [[ "$WARDEN_OPENSEARCH" -eq "1" ]]; then
            ES_ENV_NAME="$WARDEN_ENV_NAME"-opensearch-1
        else
            ES_ENV_NAME="$WARDEN_ENV_NAME"-elasticsearch-1
        fi
    else
        echo "Elastic Search or Open Search not enabled for project"
        exit
    fi

    ES="http://localhost:$LOCAL_PORT"

    echo -e "Elastic Search tunnel opened to \033[32m$ES_ENV_NAME\033[0m at: \033[32m$ES\033[0m"
    echo
    echo "Quitting this command (with Ctrl+C or equivalent) will close the tunnel."
    echo

    open_link $ES

    ssh -L "$LOCAL_PORT":"$ES_ENV_NAME":"$REMOTE_PORT" -N -p 2222 -i ~/.warden/tunnel/ssh_key user@tunnel.warden.test || true
}

# Remote stubs
function remote_db() {
    # Symfony uses .env for DB config (usually DATABASE_URL). We fetch it via SSH.
    local db_url=$(ssh -p $ENV_SOURCE_PORT $ENV_SOURCE_USER@$ENV_SOURCE_HOST "grep -E '^DATABASE_URL=' $ENV_SOURCE_DIR/.env")
    
    # Parse standard URL format: db_type://db_user:db_pass@db_host:db_port/db_name...
    # Remove prefix
    db_url=${db_url#*://}
    
    local db_user_pass=${db_url%%@*}
    local db_user=${db_user_pass%%:*}
    local db_pass=${db_user_pass#*:}
    
    local db_host_port_name=${db_url#*@}
    local db_host_port=${db_host_port_name%%/*}
    local db_host=${db_host_port%%:*}
    local db_port=${db_host_port#*:}
    # Handle port if missing (if no colon)
    if [[ "$db_host" == "$db_port" ]]; then
        db_port=3306
    else
        # db_port might contain query parameters start, strip them
        db_port=${db_port%%\?*}
    fi
    
    local db_name_rest=${db_host_port_name#*/}
    local db_name=${db_name_rest%%\?*}

    # Defaults/Fallbacks
    db_host=${db_host:-127.0.0.1}
    db_port=${db_port:-3306}

    findLocalPort $db_port

    DB="mysql://$db_user:$db_pass@127.0.0.1:$LOCAL_PORT/$db_name"

    echo -e "SSH tunnel opened to \033[32m$db_name\033[0m at: \033[32m$DB\033[0m"
    echo
    echo "Quitting this command (with Ctrl+C or equivalent) will close the tunnel."
    echo

    open_link $DB

    ssh -L $LOCAL_PORT:"$db_host":"$db_port" -N -p $ENV_SOURCE_PORT $ENV_SOURCE_USER@$ENV_SOURCE_HOST || true
}

function remote_shell() {
    ssh -t -p $ENV_SOURCE_PORT $ENV_SOURCE_USER@$ENV_SOURCE_HOST "cd $ENV_SOURCE_DIR; bash"
}

function remote_sftp() {
    SFTP_LINK="sftp://$ENV_SOURCE_USER@$ENV_SOURCE_HOST:$ENV_SOURCE_PORT$ENV_SOURCE_DIR"
    echo -e "SFTP to \033[32m$ENV_SOURCE_VAR\033[0m at: \033[32m$SFTP_LINK\033[0m"
    open_link $SFTP_LINK
}

function remote_admin() {
    if [[ ! -z "$ENV_SOURCE_URL" ]]; then
        echo -e "\033[32m$ENV_SOURCE_VAR\033[0m app at: \033[32m${ENV_SOURCE_URL}\033[0m"
        open_link "${ENV_SOURCE_URL}"
    else
        echo "REMOTE_${ENV_SOURCE_VAR}_URL is not set in .env"
    fi
}

if [[ "$ENV_SOURCE_DEFAULT" -eq "1" ]]; then
    ENV_SOURCE_VAR="LOCAL"
else
    if [ -z ${ENV_SOURCE_HOST+x} ]; then
        echo "Invalid environment '${ENV_SOURCE}' or missing configuration."
        exit 2
    fi
fi

OPEN_CL=0

while (( "$#" )); do
    case "$1" in
        -a)
            OPEN_CL=1
            shift
            ;;
        *)
            shift
            ;;
    esac
done

SERVICE=

if [ -z ${WARDEN_PARAMS[0]+x} ]; then
    echo "Please specify the service you want to open"
    exit 2
else
    SERVICE=${WARDEN_PARAMS[0]}
fi

if [[ "$SERVICE" = "opensearch" ]]; then
    SERVICE="elasticsearch"
fi

if [[ "$ENV_SOURCE_VAR" = "LOCAL" ]]; then
    if type "local_${SERVICE}" &>/dev/null; then
        local_"${SERVICE}"
    else
        echo "Service '$SERVICE' not supported."
        exit 1
    fi
else
    if type "remote_${SERVICE}" &>/dev/null; then
        remote_"${SERVICE}"
    else
        echo "Service '$SERVICE' not supported remotely."
        exit 1
    fi
fi
