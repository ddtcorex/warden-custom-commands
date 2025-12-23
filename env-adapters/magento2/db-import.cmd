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

if [[ -z "${DUMP_FILENAME}" ]] && [[ -n "${WARDEN_PARAMS[0]+1}" ]]; then
    DUMP_FILENAME="${WARDEN_PARAMS[0]}"
fi

if [[ -z "${DUMP_FILENAME}" ]] && [[ "${STREAM_DB}" -eq 0 ]]; then
    printf "😮 \033[31mPlease specify a dump file or use --stream-db\033[0m\n" >&2
    exit 1
fi

if [[ -n "${DUMP_FILENAME}" ]] && [[ ! -f "${DUMP_FILENAME}" ]]; then
    printf "😮 \033[31mDump file %s not found\033[0m\n" "${DUMP_FILENAME}" >&2
    exit 1
fi

# Ensure the database service is started for this environment
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

printf "⌛ \033[1;32mDropping and initializing docker database ...\033[0m\n"
warden db connect -e 'drop database magento; create database magento character set = "utf8" collate = "utf8_general_ci";'

# Centralized SQL cleanup filters (sandbox lines, definers, row formats, and common collation fixes)
SED_FILTERS=(
    -e '/999999.*sandbox/d'
    -e 's/DEFINER=[^*]*\*/\*/g'
    -e 's/ROW_FORMAT=FIXED//g'
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
    # Get remote DB credentials from env.php
    db_info=$(${SSH_COMMAND} -p "${ENV_SOURCE_PORT}" "${ENV_SOURCE_USER}@${ENV_SOURCE_HOST}" 'php -r "\$a=include \"'"${ENV_SOURCE_DIR}"'/app/etc/env.php\"; var_export(\$a[\"db\"][\"connection\"][\"default\"]);"')
    db_host=$(warden env exec -T php-fpm php -r "\$a = ${db_info}; echo strpos(\$a['host'], ':') === false ? \$a['host'] : explode(':', \$a['host'])[0];")
    db_port=$(warden env exec -T php-fpm php -r "\$a = ${db_info}; echo strpos(\$a['host'], ':') === false ? '3306' : explode(':', \$a['host'])[1];")
    db_user=$(warden env exec -T php-fpm php -r "\$a = ${db_info}; echo \$a['username'];")
    db_pass=$(warden env exec -T php-fpm php -r "\$a = ${db_info}; echo \$a['password'];")
    db_name=$(warden env exec -T php-fpm php -r "\$a = ${db_info}; echo \$a['dbname'];")
    
    printf "Streaming mysqldump from %s:%s ...\n" "${ENV_SOURCE_HOST}" "${db_name}"
    ${SSH_COMMAND} -p "${ENV_SOURCE_PORT}" "${ENV_SOURCE_USER}@${ENV_SOURCE_HOST}" \
        "export MYSQL_PWD='${db_pass}'; mysqldump --single-transaction --no-tablespaces --routines -h${db_host} -P${db_port} -u${db_user} ${db_name}" \
        | sed "${SED_FILTERS[@]}" \
        | warden db import --force
else
    printf "🔥 \033[1;32mImporting database ...\033[0m\n"
    if gzip -t "${DUMP_FILENAME}" 2>/dev/null; then
        ${PV} "${DUMP_FILENAME}" | gunzip -c | sed "${SED_FILTERS[@]}" | warden db import --force
    else
        ${PV} "${DUMP_FILENAME}" | sed "${SED_FILTERS[@]}" | warden db import --force
    fi
fi

if [[ "${launched_database_container:-0}" -eq 1 ]]; then
    warden env stop db
fi
