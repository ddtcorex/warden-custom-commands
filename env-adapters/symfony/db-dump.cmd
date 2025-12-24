#!/usr/bin/env bash
set -u

# env-variables is already sourced by the root dispatcher

if [ -z "${ENV_SOURCE_HOST_VAR+x}" ]; then
    printf "Invalid environment '%s'\n" "${ENV_SOURCE}" >&2
    exit 2
fi

function dump_premise () {
    # Fetch DB creds via SSH using logic
    # Check .env.local first, then .env
    local db_url=$(ssh ${SSH_OPTS} -p "${ENV_SOURCE_PORT}" "${ENV_SOURCE_USER}@${ENV_SOURCE_HOST}" "grep -h -E '^DATABASE_URL=' \"${ENV_SOURCE_DIR}/.env.local\" \"${ENV_SOURCE_DIR}/.env\" 2>/dev/null | head -n 1")
    
    # Parse standard URL format: db_type://db_user:db_pass@db_host:db_port/db_name...
    # Strip prefix
    db_url=${db_url#*=}
    # Strip quotes if present
    db_url=$(printf "%s" "${db_url}" | tr -d '"'"'")
    
    db_url=${db_url#*://}
    local db_user_pass=${db_url%%@*}
    local db_user=${db_user_pass%%:*}
    local db_pass=${db_user_pass#*:}
    local db_host_port_name=${db_url#*@}
    local db_host_port=${db_host_port_name%%/*}
    local db_host=${db_host_port%%:*}
    local db_port=${db_host_port#*:}
    
    if [[ "${db_host}" == "${db_port}" ]]; then
        db_port=3306
    else
        db_port=${db_port%%\?*}
    fi
    local db_name_rest=${db_host_port_name#*/}
    local db_name=${db_name_rest%%\?*}

    db_host=${db_host:-127.0.0.1}
    db_port=${db_port:-3306}

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

dump_premise
