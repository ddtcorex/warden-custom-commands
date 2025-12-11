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
    DB_USER=${DB_USER:-wordpress}
    DB_PASS=${DB_PASS:-wordpress}
    DB_NAME=${DB_NAME:-wordpress}

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
    ADMIN_PATH="wp-admin/"
    echo -e "\033[32m$ENV_SOURCE_VAR\033[0m admin at: \033[32m${APP_DOMAIN}${ADMIN_PATH}\033[0m"
    open_link "${APP_DOMAIN}${ADMIN_PATH}"
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
    # WordPress uses wp-config.php. We utilize grep/sed to parse it cleanly to avoid quoting hell.
    # We fetch the relevant lines via SSH first.
    local db_config=$(ssh -p $ENV_SOURCE_PORT $ENV_SOURCE_USER@$ENV_SOURCE_HOST "grep -E \"define\s*\(.*DB_(NAME|USER|PASSWORD|HOST)\" $ENV_SOURCE_DIR/wp-config.php")

    # Parse values using sed. Pattern: define( 'CONSTANT', 'VALUE' );
    # We allow for single or double quotes and variable whitespace.
    local db_name=$(echo "$db_config" | grep "DB_NAME" | sed -E "s/.*['\"]DB_NAME['\"]\s*,\s*['\"](.*)['\"].*/\1/")
    local db_user=$(echo "$db_config" | grep "DB_USER" | sed -E "s/.*['\"]DB_USER['\"]\s*,\s*['\"](.*)['\"].*/\1/")
    local db_pass=$(echo "$db_config" | grep "DB_PASSWORD" | sed -E "s/.*['\"]DB_PASSWORD['\"]\s*,\s*['\"](.*)['\"].*/\1/")
    local db_host_raw=$(echo "$db_config" | grep "DB_HOST" | sed -E "s/.*['\"]DB_HOST['\"]\s*,\s*['\"](.*)['\"].*/\1/")

    local db_host=${db_host_raw%%:*}
    local db_port=${db_host_raw#*:}
    if [[ "$db_host" == "$db_port" ]]; then
        db_port=3306
    fi
    # If host is localhost, we map it to 127.0.0.1 for the SSH tunnel context
    if [[ "$db_host" == "localhost" ]]; then
        db_host="127.0.0.1"
    fi

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
        # Wordpress default admin path
        local admin_path="wp-admin/"
        echo -e "\033[32m$ENV_SOURCE_VAR\033[0m admin at: \033[32m${ENV_SOURCE_URL}${admin_path}\033[0m"
        open_link "${ENV_SOURCE_URL}${admin_path}"
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
