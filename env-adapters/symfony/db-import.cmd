#!/usr/bin/env bash
set -u

# env-variables is already sourced by the root dispatcher

PV=$(command -v pv || command -v cat)
STREAM_DB=0
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
        --stream-db)
            STREAM_DB=1
            shift
            ;;
        *)
            shift
            ;;
    esac
done

if [[ -z "${DUMP_FILENAME}" ]] && [[ "${STREAM_DB}" -eq 0 ]]; then
    printf "😮 \033[31mPlease specify a dump file or use --stream-db\033[0m\n" >&2
    exit 1
fi

if [[ -n "${DUMP_FILENAME}" ]] && [[ ! -f "${DUMP_FILENAME}" ]]; then
    printf "😮 \033[31mDump file %s not found\033[0m\n" "${DUMP_FILENAME}" >&2
    exit 1
fi

# Ensure database service is running
launched_database_container=0
DB_CONTAINER_ID=$(warden env ps --filter status=running -q db 2>/dev/null || true)
if [[ -z "${DB_CONTAINER_ID}" ]]; then
    warden env up db
    DB_CONTAINER_ID=$(warden env ps --filter status=running -q db 2>/dev/null || true)
    if [[ -z "${DB_CONTAINER_ID}" ]]; then
        printf "😮 \033[31mDatabase container failed to start\033[0m\n" >&2
        exit 1
    fi
    launched_database_container=1
fi

printf "⌛ \033[1;32mDropping and initializing database...\033[0m\n"
DB_USER=$(warden env exec db printenv MYSQL_USER)
DB_PASS=$(warden env exec db printenv MYSQL_PASSWORD)
DB_NAME=$(warden env exec db printenv MYSQL_DATABASE)

DB_USER=${DB_USER:-symfony}
DB_PASS=${DB_PASS:-symfony}
DB_NAME=${DB_NAME:-symfony}

warden env exec db mysql -u "${DB_USER}" -p"${DB_PASS}" -e "drop database if exists ${DB_NAME}; create database ${DB_NAME} character set = \"utf8mb4\" collate = \"utf8mb4_unicode_ci\";"

# Standard SQL cleanup filters (definers and common collation fixes)
SED_FILTERS=(
    -e '/999999.*sandbox/d'
    -e 's/DEFINER=[^*]*\*/\*/g'
    -e 's/utf8mb4_0900_ai_ci/utf8mb4_general_ci/g'
    -e 's/utf8mb4_unicode_520_ci/utf8mb4_general_ci/g'
    -e 's/utf8_unicode_520_ci/utf8_general_ci/g'
)

if [[ "${STREAM_DB}" -eq 1 ]]; then
    if [[ "${ENV_SOURCE}" == "local" ]] || [[ -z "${ENV_SOURCE_HOST+x}" ]]; then
        printf "😮 \033[31mStreaming requires a remote environment. Specify one with -e (e.g. -e staging)\033[0m\n" >&2
        exit 1
    fi

    # Streaming database from remote (direct import)
    # Fetch DB creds via SSH (using logic from db-dump.cmd)
    db_url=$(ssh ${SSH_OPTS} -p "${ENV_SOURCE_PORT}" "${ENV_SOURCE_USER}@${ENV_SOURCE_HOST}" "grep -h -E '^DATABASE_URL=' \"${ENV_SOURCE_DIR}/.env.local\" \"${ENV_SOURCE_DIR}/.env\" 2>/dev/null | head -n 1")
    
    # Parse URL format: db_type://db_user:db_pass@db_host:db_port/db_name...
    db_url=${db_url#*=}
    db_url=$(printf "%s" "${db_url}" | tr -d '"'"'")
    db_url=${db_url#*://}
    db_user_pass=${db_url%%@*}
    db_user=${db_user_pass%%:*}
    db_pass=${db_user_pass#*:}
    db_host_port_name=${db_url#*@}
    db_host_port=${db_host_port_name%%/*}
    db_host=${db_host_port%%:*}
    db_port=${db_host_port#*:}
    if [[ "${db_host}" == "${db_port}" ]]; then db_port=3306; else db_port=${db_port%%\?*}; fi
    db_name_rest=${db_host_port_name#*/}
    db_name=${db_name_rest%%\?*}

    db_host=${db_host:-127.0.0.1}
    db_port=${db_port:-3306}
    
    printf "Streaming mysqldump from %s:%s ...\n" "${ENV_SOURCE_HOST}" "${db_name}"
    ssh ${SSH_OPTS} -p "${ENV_SOURCE_PORT}" "${ENV_SOURCE_USER}@${ENV_SOURCE_HOST}" \
        "export MYSQL_PWD='${db_pass}'; mysqldump --single-transaction --no-tablespaces --routines -h${db_host} -P${db_port} -u${db_user} ${db_name}" \
        | sed "${SED_FILTERS[@]}" \
        | warden db import --force
else
    printf "🔥 \033[1;32mImporting database...\033[0m\n"
    if gzip -t "${DUMP_FILENAME}" 2>/dev/null; then
        ${PV} "${DUMP_FILENAME}" | gunzip -c | sed "${SED_FILTERS[@]}" | warden db import --force
    else
        ${PV} "${DUMP_FILENAME}" | sed "${SED_FILTERS[@]}" | warden db import --force
    fi
fi

if [[ "${launched_database_container:-0}" -eq 1 ]]; then
    warden env stop db
fi
