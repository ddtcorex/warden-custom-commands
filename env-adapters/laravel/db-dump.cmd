#!/usr/bin/env bash
set -u

# env-variables is already sourced by the root dispatcher

ENV_SOURCE="${ENV_SOURCE:-local}"
if [[ "${ENV_SOURCE_DEFAULT:-0}" -eq "1" ]] || [[ "${ENV_SOURCE}" == "local" ]]; then
    ENV_SOURCE="local"
elif [[ -z "${!ENV_SOURCE_HOST_VAR+x}" ]]; then
    printf "Invalid environment '%s'\n" "${ENV_SOURCE:-}" >&2
    exit 2
fi

SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
source "${SCRIPT_DIR}/utils.sh"

function dump_local () {
    DB_USER=$(warden env exec -T db printenv MYSQL_USER)
    DB_PASS=$(warden env exec -T db printenv MYSQL_PASSWORD)
    DB_NAME=$(warden env exec -T db printenv MYSQL_DATABASE)

    printf "⌛ \033[1;32mDumping local database (\033[33m%s\033[1;32m)...\033[0m\n" "${DB_NAME}"

    local db_dump="export MYSQL_PWD='${DB_PASS}'; mysqldump --no-tablespaces --single-transaction --routines -hdb -u${DB_USER} ${DB_NAME} | gzip"
    warden env exec -T db bash -c "${db_dump}" > "${DUMP_FILENAME}"

    printf "✅ \033[32mDatabase dump complete! File: %s\033[0m\n" "${DUMP_FILENAME}"
}

function dump_premise () {
    # Fetch DB creds via SSH
    local db_vars=$(get_remote_db_info "${ENV_SOURCE_HOST}" "${ENV_SOURCE_PORT}" "${ENV_SOURCE_USER}" "${ENV_SOURCE_DIR}")
    
    # Parse the output
    local db_host=$(echo "${db_vars}" | grep "^DB_HOST=" | tail -n 1 | cut -d= -f2- | tr -d '"'"'")
    local db_port=$(echo "${db_vars}" | grep "^DB_PORT=" | tail -n 1 | cut -d= -f2- | tr -d '"'"'")
    local db_name=$(echo "${db_vars}" | grep "^DB_DATABASE=" | tail -n 1 | cut -d= -f2- | tr -d '"'"'")
    local db_user=$(echo "${db_vars}" | grep "^DB_USERNAME=" | tail -n 1 | cut -d= -f2- | tr -d '"'"'")
    local db_pass=$(echo "${db_vars}" | grep "^DB_PASSWORD=" | tail -n 1 | cut -d= -f2- | tr -d '"'"'")

    # Fallbacks / Defaults
    db_host=${db_host:-127.0.0.1}
    db_port=${db_port:-3306}

    if [[ -z "${db_name}" ]]; then
      printf "❌ \033[31mCould not detect DB_DATABASE from remote .env or .env.php\033[0m\n" >&2
      exit 1
    fi

    printf "⌛ \033[1;32mDumping \033[33m%s\033[1;32m database from \033[33m%s\033[1;32m...\033[0m\n" "${db_name}" "${ENV_SOURCE_HOST}"

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

if [[ "${ENV_SOURCE}" = "local" ]]; then
    dump_local
else
    dump_premise
fi
