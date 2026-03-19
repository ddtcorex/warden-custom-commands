#!/usr/bin/env bash
set -euo pipefail

[[ ! "${WARDEN_DIR:-}" ]] && >&2 printf "\033[31mNot intended to run directly!\033[0m\n" && exit 1

# Ensure SSH_OPTS is set
SSH_OPTS=${SSH_OPTS:-${WARDEN_SSH_OPTS:-}}

_ADAPTER_DIR=$(dirname "${BASH_SOURCE[0]}")
source "${_ADAPTER_DIR}"/env-variables
source "${_ADAPTER_DIR}"/utils.sh

ENV_SOURCE="${ENV_SOURCE:-local}"
if [[ "${ENV_SOURCE_DEFAULT:-0}" -eq "1" ]] || [[ "${ENV_SOURCE}" == "local" ]]; then
    ENV_SOURCE="local"
elif [[ -z "${!ENV_SOURCE_HOST_VAR+x}" ]]; then
    printf "Invalid environment '%s'\n" "${ENV_SOURCE:-}" >&2
    exit 2
fi

DUMP_FILENAME=""
NO_NOISE=${NO_NOISE:-0}
NO_PII=${NO_PII:-0}
LOCAL_DOWNLOAD=${LOCAL_DOWNLOAD:-0}

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
        -N|--no-noise)
            NO_NOISE=1
            shift
            ;;
        -S|--no-pii)
            NO_PII=1
            shift
            ;;
        --local)
            LOCAL_DOWNLOAD=1
            shift
            ;;
        *)
            WARDEN_PARAMS+=("$1")
            shift
            ;;
    esac
done

if [[ -z "${DUMP_FILENAME}" ]] && [[ -n "${WARDEN_PARAMS[0]+1}" ]]; then
    DUMP_FILENAME="${WARDEN_PARAMS[0]}"
fi

# Default filename based on environment
if [[ -z "${DUMP_FILENAME}" ]]; then
    if [[ "${ENV_SOURCE}" == "local" ]] || [[ "${LOCAL_DOWNLOAD}" -eq 1 ]]; then
        DUMP_FILENAME="var/${WARDEN_ENV_NAME}_${ENV_SOURCE}-$(date +%Y%m%dT%H%M%S).sql.gz"
    else
        DUMP_FILENAME="~/backup/${WARDEN_ENV_NAME}_${ENV_SOURCE}-$(date +%Y%m%dT%H%M%S).sql.gz"
    fi
fi

function get_local_db_info() {
    local db_info=$(get_db_info)
    [[ -z "${db_info}" ]] && return 1
    
    DB_HOST=$(echo "${db_info}" | grep "^DB_HOST=" | cut -d= -f2-)
    DB_USER=$(echo "${db_info}" | grep "^DB_USERNAME=" | cut -d= -f2-)
    DB_PASS=$(echo "${db_info}" | grep "^DB_PASSWORD=" | cut -d= -f2-)
    DB_NAME=$(echo "${db_info}" | grep "^DB_DATABASE=" | cut -d= -f2-)
}

function dump_local () {
    get_local_db_info
    
    local current_ignored=()
    if [[ "${NO_NOISE:-0}" -eq "1" ]]; then
        current_ignored+=("${IGNORED_TABLES[@]}")
    fi
    if [[ "${NO_PII:-0}" -eq "1" ]]; then
        current_ignored+=("${SENSITIVE_TABLES[@]}")
    fi

    local ignored_opts=()
    for table in "${current_ignored[@]}"; do
        ignored_opts+=( --ignore-table="${DB_NAME}.${DB_PREFIX:-}${table}" )
    done

    printf "⌛ \033[1;32mDumping local database (\033[33m%s\033[1;32m)...\033[0m\n" "${DB_NAME}"
    
    mkdir -p "$(dirname "${DUMP_FILENAME}")"

    local sed_filters="sed -e '/999999.*sandbox/d' -e 's/DEFINER=[^*]*\*/\*/g' -e 's/ROW_FORMAT=FIXED//g'"
    
    local db_dump_metadata="export MYSQL_PWD='${DB_PASS}'; \$(command -v mariadb-dump || echo mysqldump) --max-allowed-packet=512M --force --single-transaction --no-tablespaces --no-data --routines -h${DB_HOST} -u${DB_USER} ${DB_NAME} 2>/dev/null | ${sed_filters} | gzip -1"
    warden env exec -T db bash -c "${db_dump_metadata}" > "${DUMP_FILENAME}"
    
    local db_dump_data="export MYSQL_PWD='${DB_PASS}'; \$(command -v mariadb-dump || echo mysqldump) --max-allowed-packet=512M --force --single-transaction --no-tablespaces --skip-triggers --no-create-info ${ignored_opts[*]} -h${DB_HOST} -u${DB_USER} ${DB_NAME} 2>/dev/null | ${sed_filters} | gzip -1"
    warden env exec -T db bash -c "${db_dump_data}" >> "${DUMP_FILENAME}"

    printf "✅ \033[32mDatabase dump complete! File: %s\033[0m\n" "${DUMP_FILENAME}"
}

function dump_premise () {
    local src_db_info=$(get_remote_db_info "${ENV_SOURCE_DIR}")
    local db_host=$(echo "${src_db_info}" | grep "^DB_HOST=" | cut -d= -f2-)
    local db_port=$(echo "${src_db_info}" | grep "^DB_PORT=" | cut -d= -f2-)
    local db_user=$(echo "${src_db_info}" | grep "^DB_USERNAME=" | cut -d= -f2-)
    local db_pass=$(echo "${src_db_info}" | grep "^DB_PASSWORD=" | cut -d= -f2-)
    local db_name=$(echo "${src_db_info}" | grep "^DB_DATABASE=" | cut -d= -f2-)

    local current_ignored=()
    if [[ "${NO_NOISE:-0}" -eq "1" ]]; then
        current_ignored+=("${IGNORED_TABLES[@]}")
    fi
    if [[ "${NO_PII:-0}" -eq "1" ]]; then
        current_ignored+=("${SENSITIVE_TABLES[@]}")
    fi

    local ignored_opts=""
    for table in "${current_ignored[@]}"; do
        ignored_opts+=" --ignore-table=\"${db_name}.${DB_PREFIX:-}${table}\""
    done

    local sed_filters="sed -e '/999999.*sandbox/d' -e 's/DEFINER=[^*]*\\*/\\*/g' -e 's/ROW_FORMAT=FIXED//g'"

    if [[ "${LOCAL_DOWNLOAD}" -eq 1 ]]; then
        printf "⌛ \033[1;32mDumping \033[33m%s\033[1;32m database from \033[33m%s\033[1;32m to local...\033[0m\n" "${db_name}" "${ENV_SOURCE_HOST}"

        local db_dump_metadata="export MYSQL_PWD='${db_pass}'; \$(command -v mariadb-dump || echo mysqldump) --max-allowed-packet=512M --force --single-transaction --no-tablespaces --no-data --routines -h${db_host} -P${db_port} -u${db_user} ${db_name} 2>/dev/null | ${sed_filters} | gzip -1"
        warden remote-exec -e "${ENV_SOURCE}" -- bash -c "set -o pipefail; ${db_dump_metadata}" > "${DUMP_FILENAME}"

        local db_dump_data="export MYSQL_PWD='${db_pass}'; \$(command -v mariadb-dump || echo mysqldump) --max-allowed-packet=512M --force --single-transaction --no-tablespaces --skip-triggers --no-create-info ${ignored_opts} -h${db_host} -P${db_port} -u${db_user} ${db_name} 2>/dev/null | ${sed_filters} | gzip -1"
        warden remote-exec -e "${ENV_SOURCE}" -- bash -c "set -o pipefail; ${db_dump_data}" >> "${DUMP_FILENAME}"
        
        printf "✅ \033[32mDatabase dump complete! File: %s\033[0m\n" "${DUMP_FILENAME}"
    else
        printf "⌛ \033[1;32mDumping \033[33m%s\033[1;32m database on \033[33m%s\033[1;32m...\033[0m\n" "${db_name}" "${ENV_SOURCE_HOST}"

        local remote_cmd_file="${DUMP_FILENAME}"
        if [[ "${remote_cmd_file}" != /* ]]; then
            remote_cmd_file="${ENV_SOURCE_DIR}/${remote_cmd_file}"
        fi

        local dump_cmd="
            mkdir -p \"\$(dirname \"${remote_cmd_file}\")\" && 
            export MYSQL_PWD='${db_pass}'; 
            { 
               \$(command -v mariadb-dump || echo mysqldump) --max-allowed-packet=512M --force --single-transaction --no-tablespaces --no-data --routines -h${db_host} -P${db_port} -u${db_user} ${db_name} 2>/dev/null | ${sed_filters};
               \$(command -v mariadb-dump || echo mysqldump) --max-allowed-packet=512M --force --single-transaction --no-tablespaces --skip-triggers --no-create-info ${ignored_opts} -h${db_host} -P${db_port} -u${db_user} ${db_name} 2>/dev/null | ${sed_filters};
            } | gzip -1 > \"${remote_cmd_file}\"
        "
        
        if ! warden remote-exec -e "${ENV_SOURCE}" -- bash -c "${dump_cmd}"; then
            printf "\033[31mError: Database dump failed on remote.\033[0m\n" >&2
            return 1
        fi
        
        printf "✅ \033[32mDatabase dump complete! File: %s:%s\033[0m\n" "${ENV_SOURCE_HOST}" "${DUMP_FILENAME}"
    fi
}

# Logic moved to top


if [[ "${ENV_SOURCE}" = "local" ]]; then
    dump_local
else
    dump_premise
fi
