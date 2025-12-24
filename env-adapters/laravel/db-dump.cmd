#!/usr/bin/env bash
set -u

# env-variables is already sourced by the root dispatcher

if [ -z "${ENV_SOURCE_HOST_VAR+x}" ]; then
    printf "Invalid environment '%s'\n" "${ENV_SOURCE}" >&2
    exit 2
fi

function dump_premise () {
    # Fetch DB creds via SSH using grep/sed logic
    local db_info=$(ssh ${SSH_OPTS} -p "${ENV_SOURCE_PORT}" "${ENV_SOURCE_USER}@${ENV_SOURCE_HOST}" "grep -E '^DB_(HOST|PORT|DATABASE|USERNAME|PASSWORD)=' \"${ENV_SOURCE_DIR}/.env\"")

    local db_host=$(printf "%s" "${db_info}" | grep DB_HOST | cut -d= -f2 | tr -d '"'"'")
    local db_port=$(printf "%s" "${db_info}" | grep DB_PORT | cut -d= -f2 | tr -d '"'"'")
    local db_name=$(printf "%s" "${db_info}" | grep DB_DATABASE | cut -d= -f2 | tr -d '"'"'")
    local db_user=$(printf "%s" "${db_info}" | grep DB_USERNAME | cut -d= -f2 | tr -d '"'"'")
    local db_pass=$(printf "%s" "${db_info}" | grep DB_PASSWORD | cut -d= -f2 | tr -d '"'"'")

    # Defaults
    db_host=${db_host:-127.0.0.1}
    db_port=${db_port:-3306}

    printf "⌛ \033[1;32mDumping \033[33m%s\033[1;32m database from \033[33m%s\033[1;32m...\033[0m\n" "${db_name}" "${ENV_SOURCE_HOST}"

    # mysqldump command
    local db_dump="export MYSQL_PWD='${db_pass}'; mysqldump --no-tablespaces --single-transaction --routines -h${db_host} -P${db_port} -u${db_user} ${db_name} | gzip"
    
    ssh ${SSH_OPTS} -p "${ENV_SOURCE_PORT}" "${ENV_SOURCE_USER}@${ENV_SOURCE_HOST}" "set -o pipefail; ${db_dump}" > "${DUMP_FILENAME}"

    printf "✅ \033[32mDatabase dump complete! File: %s\033[0m\n" "${DUMP_FILENAME}"
}

DUMP_FILENAME=""

while (( "$#" )); do
    case "$1" in
        -f=*|--file=*)
            DUMP_FILENAME="${1#*=}"
            shift
            ;;
        -f|--file)
            DUMP_FILENAME="$2"
            shift 2
            ;;

        *)
            shift
            ;;
    esac
done

if [[ -z "${DUMP_FILENAME}" ]] && [[ -n "${WARDEN_PARAMS[0]+1}" ]]; then
    DUMP_FILENAME="${WARDEN_PARAMS[0]}"
fi

if [[ -z "${DUMP_FILENAME}" ]]; then
    DUMP_FILENAME="var/${WARDEN_ENV_NAME}_${ENV_SOURCE}-$(date +%Y%m%dT%H%M%S).sql.gz"
fi

dump_premise
