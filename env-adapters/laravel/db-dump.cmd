#!/usr/bin/env bash
[[ ! ${WARDEN_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

# env-variables is already sourced by the root dispatcher

if [ -z ${!ENV_SOURCE_HOST_VAR+x} ]; then
    echo "Invalid environment '${ENV_SOURCE}'"
    exit 2
fi

function dumpPremise () {
    # Fetch DB creds via SSH using grep/sed logic from open.cmd
    local db_info=$($SSH_COMMAND -p $ENV_SOURCE_PORT $ENV_SOURCE_USER@$ENV_SOURCE_HOST "grep -E '^DB_(HOST|PORT|DATABASE|USERNAME|PASSWORD)=' $ENV_SOURCE_DIR/.env")

    local db_host=$(echo "$db_info" | grep DB_HOST | cut -d= -f2 | tr -d '"'"'")
    local db_port=$(echo "$db_info" | grep DB_PORT | cut -d= -f2 | tr -d '"'"'")
    local db_name=$(echo "$db_info" | grep DB_DATABASE | cut -d= -f2 | tr -d '"'"'")
    local db_user=$(echo "$db_info" | grep DB_USERNAME | cut -d= -f2 | tr -d '"'"'")
    local db_pass=$(echo "$db_info" | grep DB_PASSWORD | cut -d= -f2 | tr -d '"'"'")

    # Defaults
    db_host=${db_host:-127.0.0.1}
    db_port=${db_port:-3306}

    echo -e "⌛ \033[1;32mDumping \033[33m${db_name}\033[1;32m database from \033[33m${ENV_SOURCE_HOST}\033[1;32m...\033[0m"

    # mysqldump command
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
