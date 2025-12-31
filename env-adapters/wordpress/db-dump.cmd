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
    # Fetch DB creds via SSH using logic
    local db_config=$(ssh ${SSH_OPTS} -p "${ENV_SOURCE_PORT}" "${ENV_SOURCE_USER}@${ENV_SOURCE_HOST}" "grep -E \"define\s*\(.*DB_(NAME|USER|PASSWORD|HOST)\" \"${ENV_SOURCE_DIR}/wp-config.php\"")

    local db_name=$(printf "%s" "${db_config}" | grep "DB_NAME" | sed -E "s/.*['\"]DB_NAME['\"]\s*,\s*['\"](.*)['\"].*/\1/")
    local db_user=$(printf "%s" "${db_config}" | grep "DB_USER" | sed -E "s/.*['\"]DB_USER['\"]\s*,\s*['\"](.*)['\"].*/\1/")
    local db_pass=$(printf "%s" "${db_config}" | grep "DB_PASSWORD" | sed -E "s/.*['\"]DB_PASSWORD['\"]\s*,\s*['\"](.*)['\"].*/\1/")
    local db_host_raw=$(printf "%s" "${db_config}" | grep "DB_HOST" | sed -E "s/.*['\"]DB_HOST['\"]\s*,\s*['\"](.*)['\"].*/\1/")

    local db_host=${db_host_raw%%:*}
    local db_port=${db_host_raw#*:}
    if [[ "${db_host}" == "${db_port}" ]]; then
        db_port=3306
    fi
    if [[ "${db_host}" == "localhost" ]]; then
        db_host="127.0.0.1"
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
