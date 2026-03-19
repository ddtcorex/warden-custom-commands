#!/usr/bin/env bash
set -euo pipefail

[[ ! "${WARDEN_DIR:-}" ]] && >&2 printf "\033[31mNot intended to run directly!\033[0m\n" && exit 1

_ADAPTER_DIR=$(dirname "${BASH_SOURCE[0]}")
source "${_ADAPTER_DIR}"/env-variables
source "${_ADAPTER_DIR}"/utils.sh

PV="pv"
if ! command -v pv &>/dev/null; then
    PV="cat"
fi
STREAM_DB=${STREAM_DB:-0}
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
        -N|--no-noise)
            SYNC_DB_NO_NOISE=1
            shift
            ;;
        -S|--no-pii)
            SYNC_DB_NO_PII=1
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

# If no file and not streaming-db, we might be receiving data via stdin
if [[ -z "${DUMP_FILENAME}" ]] && [[ "${STREAM_DB}" -eq 0 ]]; then
    if [[ -t 0 ]]; then
        printf "😮 \033[31mPlease specify a dump file, use --stream-db, or pipe SQL data to stdin\033[0m\n" >&2
        exit 1
    fi
fi

if [[ -n "${DUMP_FILENAME}" ]] && [[ ! -f "${DUMP_FILENAME}" ]]; then
    printf "😮 \033[31mDump file %s not found\033[0m\n" "${DUMP_FILENAME}" >&2
    exit 1
fi

# Ensure the database service is started for this environment
_DB_CONTAINER_ID=$(warden env ps --filter status=running -q db 2>/dev/null || true)
if [[ -z "${_DB_CONTAINER_ID}" ]]; then
    warden env up db
    _DB_CONTAINER_ID=$(warden env ps --filter status=running -q db 2>/dev/null || true)
    if [[ -z "${_DB_CONTAINER_ID}" ]]; then
        printf "😮 \033[31mDatabase container failed to start\033[0m\n" >&2
        exit 1
    fi
fi

printf "⌛ \033[1;32mDropping and initializing docker database ...\033[0m\n"
warden env exec -T db bash -c '$(command -v mariadb || echo mysql) -hdb -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" -e "drop database if exists $MYSQL_DATABASE; create database $MYSQL_DATABASE character set = \"utf8\" collate = \"utf8_general_ci\""' 2> >(grep -v 'Deprecated program name' >&2)

# SQL cleanup filters
SED_FILTERS=(
    -e '/999999.*sandbox/d'
    -e 's/DEFINER=[^*]*\*/\*/g'
    -e 's/ROW_FORMAT=FIXED//g'
    -e 's/utf8mb4_0900_ai_ci/utf8mb4_general_ci/g'
    -e 's/utf8mb4_unicode_520_ci/utf8mb4_general_ci/g'
    -e 's/utf8_unicode_520_ci/utf8_general_ci/g'
)

mysql_import_cmd='export MYSQL_PWD="$MYSQL_PASSWORD"; { echo "SET FOREIGN_KEY_CHECKS=0; SET UNIQUE_CHECKS=0; SET AUTOCOMMIT=0; SET SQL_MODE='\''NO_AUTO_VALUE_ON_ZERO'\'';"; cat; echo "COMMIT; SET FOREIGN_KEY_CHECKS=1; SET UNIQUE_CHECKS=1; SET AUTOCOMMIT=1;"; } | $(command -v mariadb || echo mysql) --max-allowed-packet=512M -hdb -u"$MYSQL_USER" "$MYSQL_DATABASE" -f'

if [[ "${STREAM_DB}" -eq 1 ]]; then
    if [[ "${ENV_SOURCE}" == "local" ]] || [[ -z "${ENV_SOURCE_HOST+x}" ]]; then
        printf "😮 \033[31mStreaming requires a remote environment. Specify one with -e (e.g. -e staging)\033[0m\n" >&2
        exit 1
    fi

    # Streaming database from remote
    db_info=$(get_remote_db_info "${ENV_SOURCE_DIR}")
    db_host=$(echo "${db_info}" | grep "^DB_HOST=" | cut -d= -f2-)
    db_port=$(echo "${db_info}" | grep "^DB_PORT=" | cut -d= -f2-)
    db_user=$(echo "${db_info}" | grep "^DB_USERNAME=" | cut -d= -f2-)
    db_pass=$(echo "${db_info}" | grep "^DB_PASSWORD=" | cut -d= -f2-)
    db_name=$(echo "${db_info}" | grep "^DB_DATABASE=" | cut -d= -f2-)

    # Calculate ignored tables for sync
    current_ignored=("${IGNORED_TABLES[@]}")
    if [[ "${SYNC_DB_NO_PII:-0}" -eq 1 ]]; then
        current_ignored+=("${SENSITIVE_TABLES[@]}")
    fi

    ignored_opts=""
    if [[ "${SYNC_DB_NO_NOISE:-0}" -eq 1 ]]; then
        for table in "${current_ignored[@]}"; do
            ignored_opts+=" --ignore-table=\"${db_name}.${DB_PREFIX:-}${table}\""
        done
    fi

    printf "Streaming mysqldump from %s:%s ...\n" "${ENV_SOURCE_HOST}" "${db_name}"
    
    # Using two-stage dump (schema then data) for better reliability and avoiding DEFINER issues
    dump_cmd="export MYSQL_PWD='${db_pass}'; { \$(command -v mariadb-dump || echo mysqldump) --max-allowed-packet=512M --force --single-transaction --no-tablespaces --no-data --routines -h${db_host} -P${db_port} -u${db_user} ${db_name} 2>/dev/null; \$(command -v mariadb-dump || echo mysqldump) --max-allowed-packet=512M --force --single-transaction --no-tablespaces --skip-triggers --no-create-info ${ignored_opts} -h${db_host} -P${db_port} -u${db_user} ${db_name} 2>/dev/null; } | gzip -1"

    warden remote-exec -e "${ENV_SOURCE}" -- bash -c "${dump_cmd}" \
        | gunzip -c \
        | sed "${SED_FILTERS[@]}" \
        | ${PV} -N "Importing" \
        | warden env exec -T db bash -c "${mysql_import_cmd}"
elif [[ -n "${DUMP_FILENAME}" ]]; then
    printf "🔥 \033[1;32mImporting database from %s ...\033[0m\n" "${DUMP_FILENAME}"
    [[ "${PV}" == "pv" ]] && PV_CMD="pv -N Importing" || PV_CMD="cat"

    if gzip -t "${DUMP_FILENAME}" 2>/dev/null; then
        cat "${DUMP_FILENAME}" | ${PV_CMD} | gunzip -c | sed "${SED_FILTERS[@]}" | warden env exec -T db bash -c "${mysql_import_cmd}"
    else
        cat "${DUMP_FILENAME}" | ${PV_CMD} | sed "${SED_FILTERS[@]}" | warden env exec -T db bash -c "${mysql_import_cmd}"
    fi
else
    # Importing from stdin
    printf "🔥 \033[1;32mImporting database from stdin ...\033[0m\n"
    sed "${SED_FILTERS[@]}" | warden env exec -T db bash -c "${mysql_import_cmd}"
fi

printf "✅ \033[32mDatabase import complete!\033[0m\n"
