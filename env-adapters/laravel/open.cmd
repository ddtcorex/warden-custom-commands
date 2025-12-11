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
    
    # Fallback if exec failed (e.g. container down)
    DB_USER=${DB_USER:-laravel}
    DB_PASS=${DB_PASS:-laravel}
    DB_NAME=${DB_NAME:-laravel}

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
    # Laravel projects might not use ES, but if they do:
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
    # Laravel uses .env for DB config. We fetch it via SSH.
    # PHP script to parse .env lines for DB_ config
    local db_info=$(ssh -p $ENV_SOURCE_PORT $ENV_SOURCE_USER@$ENV_SOURCE_HOST "grep -E '^DB_(HOST|PORT|DATABASE|USERNAME|PASSWORD)=' $ENV_SOURCE_DIR/.env")

    # Parse variables from the grep output
    local db_host=$(echo "$db_info" | grep DB_HOST | cut -d= -f2)
    local db_port=$(echo "$db_info" | grep DB_PORT | cut -d= -f2)
    local db_name=$(echo "$db_info" | grep DB_DATABASE | cut -d= -f2)
    local db_user=$(echo "$db_info" | grep DB_USERNAME | cut -d= -f2)
    local db_pass=$(echo "$db_info" | grep DB_PASSWORD | cut -d= -f2)

    # Defaults if not found
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

# Map opensearch to elasticsearch logic
if [[ "$SERVICE" = "opensearch" ]]; then
    SERVICE="elasticsearch"
fi

# Dispatch
if [[ "$ENV_SOURCE_VAR" = "LOCAL" ]]; then
    if type "local_${SERVICE}" &>/dev/null; then
        local_"${SERVICE}"
    else
        echo "Service '$SERVICE' not supported."
        exit 1
    fi
else
    # Remote dispatch
    if type "remote_${SERVICE}" &>/dev/null; then
        remote_"${SERVICE}"
    else
        echo "Service '$SERVICE' not supported remotely."
        exit 1
    fi
fi
