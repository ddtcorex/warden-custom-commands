#!/usr/bin/env bash
# Strict mode inherited from env-variables

# env-variables is already sourced by the root dispatcher

PV="pv"
if ! command -v pv &>/dev/null; then
    PV="cat"
fi
STREAM_DB=${STREAM_DB:-0}
DUMP_FILENAME=""

# Arguments for stream-db
it_no_noise=${SYNC_DB_NO_NOISE:-0}
it_exclude_sensitive=${SYNC_DB_NO_PII:-0}

while (( "$#" )); do
    case "$1" in
        -f=*|--file=*) DUMP_FILENAME="${1#*=}"; shift ;;
        -f|--file) DUMP_FILENAME="$2"; shift 2 ;;
        --stream-db) STREAM_DB=1; shift ;;
        -N|--no-noise) it_no_noise=1; shift ;;
        -S|--no-pii) it_exclude_sensitive=1; shift ;;
        *) shift ;;
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
DB_CONTAINER_ID=$(warden env ps --filter status=running -q db 2>/dev/null) || DB_CONTAINER_ID=""
if [[ -z "${DB_CONTAINER_ID}" ]]; then
    warden env up db
    DB_CONTAINER_ID=$(warden env ps --filter status=running -q db 2>/dev/null) || DB_CONTAINER_ID=""
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

DB_BIN="mysql"
if [[ "${MYSQL_DISTRIBUTION:-}" == *"mariadb"* ]]; then
    DB_BIN="mariadb"
fi

warden env exec db ${DB_BIN} -u "${DB_USER}" -p"${DB_PASS}" -e "drop database if exists ${DB_NAME}; create database ${DB_NAME} character set = \"utf8mb4\" collate = \"utf8mb4_unicode_ci\";"

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
    # Fetch DB creds via SSH (using helper)
    db_info=$(get_remote_db_info "${ENV_SOURCE_DIR}")

    db_host=$(echo "${db_info}" | grep "^DB_HOST=" | cut -d= -f2-)
    db_port=$(echo "${db_info}" | grep "^DB_PORT=" | cut -d= -f2-)
    db_user=$(echo "${db_info}" | grep "^DB_USERNAME=" | cut -d= -f2-)
    db_pass=$(echo "${db_info}" | grep "^DB_PASSWORD=" | cut -d= -f2-)
    db_name=$(echo "${db_info}" | grep "^DB_DATABASE=" | cut -d= -f2-)
    
    current_ignored=()
    if [[ "${it_no_noise:-0}" -eq 1 ]]; then
        current_ignored+=("${IGNORED_TABLES[@]}")
    fi
    if [[ "${it_exclude_sensitive:-0}" -eq "1" ]]; then
        current_ignored+=("${SENSITIVE_TABLES[@]}")
    fi

    ignored_opts=""
    for table in "${current_ignored[@]}"; do
        ignored_opts+=" --ignore-table=${db_name}.${table}"
    done

    printf "Streaming dump from %s:%s ...\n" "${ENV_SOURCE_HOST}" "${db_name}"
    warden remote-exec -e "${ENV_SOURCE}" -- bash -c \
        "export MYSQL_PWD='${db_pass}'; \$(command -v mariadb-dump || echo mysqldump) --max-allowed-packet=512M --single-transaction --no-tablespaces --routines ${ignored_opts} -h${db_host} -P${db_port} -u${db_user} ${db_name} | gzip -1" \
        | gunzip -c \
        | sed "${SED_FILTERS[@]}" \
        | warden env exec -T db bash -c 'export MYSQL_PWD="$MYSQL_PASSWORD"; { echo "SET FOREIGN_KEY_CHECKS=0; SET UNIQUE_CHECKS=0; SET AUTOCOMMIT=0;"; cat; echo "COMMIT; SET FOREIGN_KEY_CHECKS=1; SET UNIQUE_CHECKS=1; SET AUTOCOMMIT=1;"; } | $(command -v mariadb || echo mysql) --max-allowed-packet=512M -hdb -u"$MYSQL_USER" "$MYSQL_DATABASE" -f'
else
    mysql_import_cmd='export MYSQL_PWD="$MYSQL_PASSWORD"; { echo "SET FOREIGN_KEY_CHECKS=0; SET UNIQUE_CHECKS=0; SET AUTOCOMMIT=0;"; cat; echo "COMMIT; SET FOREIGN_KEY_CHECKS=1; SET UNIQUE_CHECKS=1; SET AUTOCOMMIT=1;"; } | $(command -v mariadb || echo mysql) --max-allowed-packet=512M -hdb -u"$MYSQL_USER" "$MYSQL_DATABASE" -f'

    if [[ "${PV}" == "pv" ]]; then
        PV_CMD="pv -N Importing"
    else
        PV_CMD="cat"
    fi

    if gzip -t "${DUMP_FILENAME}" 2>/dev/null; then
        cat "${DUMP_FILENAME}" | ${PV_CMD} | gunzip -c | sed "${SED_FILTERS[@]}" | warden env exec -T db bash -c "${mysql_import_cmd}"
    else
        cat "${DUMP_FILENAME}" | ${PV_CMD} | sed "${SED_FILTERS[@]}" | warden env exec -T db bash -c "${mysql_import_cmd}"
    fi
fi

if [[ "${launched_database_container:-0}" -eq 1 ]]; then
    warden env stop db
fi
