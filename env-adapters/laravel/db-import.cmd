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
DB_USER=$(warden env exec -T db printenv MYSQL_USER)
DB_PASS=$(warden env exec -T db printenv MYSQL_PASSWORD)
DB_NAME=$(warden env exec -T db printenv MYSQL_DATABASE)

DB_USER=${DB_USER:-laravel}
DB_PASS=${DB_PASS:-laravel}
DB_NAME=${DB_NAME:-laravel}

DB_BIN="mysql"
if [[ "${MYSQL_DISTRIBUTION:-}" == *"mariadb"* ]]; then
    DB_BIN="mariadb"
fi

warden env exec -T db ${DB_BIN} -u "${DB_USER}" -p"${DB_PASS}" -e "drop database if exists ${DB_NAME}; create database ${DB_NAME} character set = \"utf8mb4\" collate = \"utf8mb4_unicode_ci\";"

# Standard SQL cleanup filters (definers and common collation fixes)
SED_FILTERS=(
    -e '/999999.*sandbox/d'
    -e 's/DEFINER=[^*]*\*/\*/g'
    -e 's/utf8mb4_0900_ai_ci/utf8mb4_general_ci/g'
    -e 's/utf8mb4_unicode_520_ci/utf8mb4_general_ci/g'
    -e 's/utf8_unicode_520_ci/utf8_general_ci/g'
)

SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
source "${SCRIPT_DIR}/utils.sh"

if [[ "${STREAM_DB}" -eq 1 ]]; then
    if [[ "${ENV_SOURCE}" == "local" ]] || [[ -z "${ENV_SOURCE_HOST+x}" ]]; then
        printf "😮 \033[31mStreaming requires a remote environment. Specify one with -e (e.g. -e staging)\033[0m\n" >&2
        exit 1
    fi

    # Streaming database from remote (direct import)
    # Fetch DB creds via SSH (using logic from db-dump.cmd via utils.sh)
    db_vars=$(get_remote_db_info "${ENV_SOURCE_HOST}" "${ENV_SOURCE_PORT}" "${ENV_SOURCE_USER}" "${ENV_SOURCE_DIR}")
    
    db_host=$(echo "${db_vars}" | grep "^DB_HOST=" | tail -n 1 | cut -d= -f2- | tr -d '"'"'")
    db_port=$(echo "${db_vars}" | grep "^DB_PORT=" | tail -n 1 | cut -d= -f2- | tr -d '"'"'")
    db_name=$(echo "${db_vars}" | grep "^DB_DATABASE=" | tail -n 1 | cut -d= -f2- | tr -d '"'"'")
    db_user=$(echo "${db_vars}" | grep "^DB_USERNAME=" | tail -n 1 | cut -d= -f2- | tr -d '"'"'")
    db_pass=$(echo "${db_vars}" | grep "^DB_PASSWORD=" | tail -n 1 | cut -d= -f2- | tr -d '"'"'")

    db_host=${db_host:-127.0.0.1}
    db_port=${db_port:-3306}

    if [[ -z "${db_name}" ]]; then
      printf "❌ \033[31mCould not detect DB_DATABASE from remote .env or .env.php\033[0m\n" >&2
      exit 1
    fi

    printf "Streaming dump from %s:%s ...\n" "${ENV_SOURCE_HOST}" "${db_name}"
    ssh ${SSH_OPTS} -p "${ENV_SOURCE_PORT}" "${ENV_SOURCE_USER}@${ENV_SOURCE_HOST}" \
        "export MYSQL_PWD='${db_pass}'; \$(command -v mariadb-dump || echo mysqldump) --single-transaction --no-tablespaces --routines -h${db_host} -P${db_port} -u${db_user} ${db_name}" \
        | sed "${SED_FILTERS[@]}" \
        | warden env exec -T db bash -c '$(command -v mariadb || echo mysql) -hdb -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" -f'
else
    local mysql_import_cmd='export MYSQL_PWD="$MYSQL_PASSWORD"; { echo "SET FOREIGN_KEY_CHECKS=0; SET UNIQUE_CHECKS=0;"; cat; } | $(command -v mariadb || echo mysql) -hdb -u"$MYSQL_USER" "$MYSQL_DATABASE" -f'
    
    if gzip -t "${DUMP_FILENAME}" 2>/dev/null; then
        ${PV} -N "Importing" "${DUMP_FILENAME}" | gunzip -c | sed "${SED_FILTERS[@]}" | warden env exec -T db bash -c "${mysql_import_cmd}"
    else
        ${PV} -N "Importing" "${DUMP_FILENAME}" | sed "${SED_FILTERS[@]}" | warden env exec -T db bash -c "${mysql_import_cmd}"
    fi
fi

if [[ "${launched_database_container:-0}" -eq 1 ]]; then
    warden env stop db
fi
