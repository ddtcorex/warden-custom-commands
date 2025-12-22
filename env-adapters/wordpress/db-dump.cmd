#!/usr/bin/env bash
[[ ! ${WARDEN_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

# env-variables is already sourced by the root dispatcher

if [ -z ${!ENV_SOURCE_HOST_VAR+x} ]; then
    echo "Invalid environment '${ENV_SOURCE}'"
    exit 2
fi

function dumpPremise () {
    # Fetch DB creds via SSH using grep/sed logic from wordpress/open.cmd
    local db_config=$($SSH_COMMAND -p $ENV_SOURCE_PORT $ENV_SOURCE_USER@$ENV_SOURCE_HOST "grep -E \"define\s*\(.*DB_(NAME|USER|PASSWORD|HOST)\" $ENV_SOURCE_DIR/wp-config.php")

    local db_name=$(echo "$db_config" | grep "DB_NAME" | sed -E "s/.*['\"]DB_NAME['\"]\s*,\s*['\"](.*)['\"].*/\1/")
    local db_user=$(echo "$db_config" | grep "DB_USER" | sed -E "s/.*['\"]DB_USER['\"]\s*,\s*['\"](.*)['\"].*/\1/")
    local db_pass=$(echo "$db_config" | grep "DB_PASSWORD" | sed -E "s/.*['\"]DB_PASSWORD['\"]\s*,\s*['\"](.*)['\"].*/\1/")
    local db_host_raw=$(echo "$db_config" | grep "DB_HOST" | sed -E "s/.*['\"]DB_HOST['\"]\s*,\s*['\"](.*)['\"].*/\1/")

    local db_host=${db_host_raw%%:*}
    local db_port=${db_host_raw#*:}
    if [[ "$db_host" == "$db_port" ]]; then
        db_port=3306
    fi
    if [[ "$db_host" == "localhost" ]]; then
        db_host="127.0.0.1"
    fi

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
