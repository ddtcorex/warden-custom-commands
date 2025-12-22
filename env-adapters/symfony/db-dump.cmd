#!/usr/bin/env bash
[[ ! ${WARDEN_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

# env-variables is already sourced by the root dispatcher

if [ -z ${!ENV_SOURCE_HOST_VAR+x} ]; then
    echo "Invalid environment '${ENV_SOURCE}'"
    exit 2
fi

function dumpPremise () {
    # Fetch DB creds via SSH using logic from symfony/open.cmd
    # Check .env.local first, then .env
    local db_url=$($SSH_COMMAND -p $ENV_SOURCE_PORT $ENV_SOURCE_USER@$ENV_SOURCE_HOST "grep -h -E '^DATABASE_URL=' $ENV_SOURCE_DIR/.env.local $ENV_SOURCE_DIR/.env 2>/dev/null | head -n 1")
    
    # Parse standard URL format: db_type://db_user:db_pass@db_host:db_port/db_name...
    # Strip prefix
    db_url=${db_url#*=}
    # Strip quotes if present (both single and double)
    db_url=$(echo "$db_url" | tr -d '"'"'")
    
    db_url=${db_url#*://}
    local db_user_pass=${db_url%%@*}
    local db_user=${db_user_pass%%:*}
    local db_pass=${db_user_pass#*:}
    local db_host_port_name=${db_url#*@}
    local db_host_port=${db_host_port_name%%/*}
    local db_host=${db_host_port%%:*}
    local db_port=${db_host_port#*:}
    
    if [[ "$db_host" == "$db_port" ]]; then
        db_port=3306
    else
        db_port=${db_port%%\?*}
    fi
    local db_name_rest=${db_host_port_name#*/}
    local db_name=${db_name_rest%%\?*}

    db_host=${db_host:-127.0.0.1}
    db_port=${db_port:-3306}

    echo -e "⌛ \033[1;32mDumping \033[33m${db_name}\033[1;32m database from \033[33m${ENV_SOURCE_HOST}\033[1;32m...\033[0m"

    local db_dump="export MYSQL_PWD='${db_pass}'; mysqldump --no-tablespaces --single-transaction --routines -h$db_host -P$db_port -u$db_user $db_name | gzip"
    $SSH_COMMAND -p $ENV_SOURCE_PORT $ENV_SOURCE_USER@$ENV_SOURCE_HOST "set -o pipefail; $db_dump" > "$DUMP_FILENAME"

    echo -e "✅ \033[32mDatabase dump complete! File: $DUMP_FILENAME\033[0m"
}

DUMP_FILENAME=

while (( "$#" )); do
    case "$1" in
        -f|--file)
            if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
                DUMP_FILENAME="$2"
                shift 2
            else
                echo "Error: Argument for $1 is missing" >&2
                exit 1
            fi
            ;;
        --file=*|-f=*)
            DUMP_FILENAME="${1#*=}"
            shift
            ;;

        *)
            shift
            ;;
    esac
done

if [[ -z "$DUMP_FILENAME" ]] && [[ -n "${WARDEN_PARAMS[0]+1}" ]]; then
    DUMP_FILENAME="${WARDEN_PARAMS[0]}"
fi

if [ -z "$DUMP_FILENAME" ]; then
    DUMP_FILENAME="var/${WARDEN_ENV_NAME}_${ENV_SOURCE}-`date +%Y%m%dT%H%M%S`.sql.gz"
fi

dumpPremise
