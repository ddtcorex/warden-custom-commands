#!/usr/bin/env bash
# Strict mode inherited from env-variables

# Ensure SSH_OPTS is set (fallback to WARDEN_SSH_OPTS)
SSH_OPTS=${SSH_OPTS:-${WARDEN_SSH_OPTS:-}}

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

# Use shared tables list from utils.sh.
# IGNORED_TABLES is already defined in utils.sh.

function get_db_info() {
    # Single Docker exec call instead of 3 separate calls
    local db_info=$(warden env exec -T db bash -c 'echo "MYSQL_USER=$MYSQL_USER"; echo "MYSQL_PASSWORD=$MYSQL_PASSWORD"; echo "MYSQL_DATABASE=$MYSQL_DATABASE"')
    DB_USER=$(echo "${db_info}" | grep "^MYSQL_USER=" | cut -d= -f2-)
    DB_PASS=$(echo "${db_info}" | grep "^MYSQL_PASSWORD=" | cut -d= -f2-)
    DB_NAME=$(echo "${db_info}" | grep "^MYSQL_DATABASE=" | cut -d= -f2-)

    DUMP_BIN="mysqldump"
    if [[ "${MYSQL_DISTRIBUTION:-}" == *"mariadb"* ]]; then
        DUMP_BIN="mariadb-dump"
    fi
}

function dump_local () {
    get_db_info
    
    local ignored_opts=()
    if [[ "${NO_NOISE:-0}" -eq "0" ]]; then
        for table in "${IGNORED_TABLES[@]}"; do
            ignored_opts+=( --ignore-table="${DB_NAME}.${DB_PREFIX:-}${table}" )
        done
    fi

    printf "⌛ \033[1;32mDumping local database (\033[33m%s\033[1;32m)...\033[0m\n" "${DB_NAME}"
    
    mkdir -p "$(dirname "${DUMP_FILENAME}")"

    local db_dump_metadata="export MYSQL_PWD='${DB_PASS}'; ${DUMP_BIN} --max-allowed-packet=512M --force --single-transaction --no-tablespaces --no-data --routines -hdb -u${DB_USER} ${DB_NAME} 2> >(grep -v 'Deprecated program name' >&2) | sed -e '/999999.*enable the sandbox mode/d' -e 's/DEFINER=[^*]*\*/\*/g' -e 's/ROW_FORMAT=FIXED//g' | gzip"
    warden env exec -T db bash -c "${db_dump_metadata}" > "${DUMP_FILENAME}"
    
    local db_dump_data="export MYSQL_PWD='${DB_PASS}'; ${DUMP_BIN} --max-allowed-packet=512M --force --single-transaction --no-tablespaces --skip-triggers --no-create-info ${ignored_opts[*]} -hdb -u${DB_USER} ${DB_NAME} 2> >(grep -v 'Deprecated program name' >&2) | sed -e '/999999.*enable the sandbox mode/d' -e 's/DEFINER=[^*]*\*/\*/g' -e 's/ROW_FORMAT=FIXED//g' | gzip"
    warden env exec -T db bash -c "${db_dump_data}" >> "${DUMP_FILENAME}"

    printf "✅ \033[32mDatabase dump complete! File: %s\033[0m\n" "${DUMP_FILENAME}"
}

function dump_cloud () {
    # Determine relationship
    local RELATIONSHIP="database"
    if [[ -n "${MAGENTO_CLOUD_RELATIONSHIP:-}" ]]; then
        RELATIONSHIP="${MAGENTO_CLOUD_RELATIONSHIP}"
    fi

    local ignored_opts=()
    if [[ "${NO_NOISE:-0}" -eq "0" ]]; then
        for table in "${IGNORED_TABLES[@]}"; do
            ignored_opts+=( --ignore-table="${table}" )
        done
    fi

    printf "⌛ \033[1;32mDumping database from Cloud (\033[33m%s\033[1;32m)...\033[0m\n" "${ENV_SOURCE_HOST}"

    # Use magento-cloud CLI to dump metadata first (no data, routines)
    magento-cloud db:dump -p "${CLOUD_PROJECT}" -e "${ENV_SOURCE_HOST}" --relationship="${RELATIONSHIP}" --schema-only --stdout --gzip > "${DUMP_FILENAME}"

    # Use magento-cloud CLI to dump data (excluding ignored tables)
    magento-cloud db:dump -p "${CLOUD_PROJECT}" -e "${ENV_SOURCE_HOST}" --relationship="${RELATIONSHIP}" "${ignored_opts[@]}" --stdout --gzip >> "${DUMP_FILENAME}"

    printf "✅ \033[32mDatabase dump complete! File: %s\033[0m\n" "${DUMP_FILENAME}"
}

function dump_premise () {
    local src_db_info=$(get_remote_db_info "${ENV_SOURCE_DIR}")
    local db_host=$(printf "%s" "${src_db_info}" | grep "^DB_HOST=" | tail -n 1 | cut -d= -f2-)
    local db_port=$(printf "%s" "${src_db_info}" | grep "^DB_PORT=" | tail -n 1 | cut -d= -f2-)
    local db_user=$(printf "%s" "${src_db_info}" | grep "^DB_USERNAME=" | tail -n 1 | cut -d= -f2-)
    local db_pass=$(printf "%s" "${src_db_info}" | grep "^DB_PASSWORD=" | tail -n 1 | cut -d= -f2-)
    local db_name=$(printf "%s" "${src_db_info}" | grep "^DB_DATABASE=" | tail -n 1 | cut -d= -f2-)

    local ignored_opts=""
    if [[ "${NO_NOISE:-0}" -eq "0" ]]; then
        for table in "${IGNORED_TABLES[@]}"; do
            ignored_opts+=" --ignore-table=\"${db_name}.${DB_PREFIX:-}${table}\""
        done
    fi

    local sed_filters="sed -e '/999999.*enable the sandbox mode/d' -e 's/DEFINER=[^*]*\\*/\\*/g' -e 's/ROW_FORMAT=FIXED//g'"

    if [[ "${LOCAL_DOWNLOAD}" -eq 1 ]]; then
        # Download to local (current behavior - 2 SSH calls)
        printf "⌛ \033[1;32mDumping \033[33m%s\033[1;32m database from \033[33m%s\033[1;32m to local...\033[0m\n" "${db_name}" "${ENV_SOURCE_HOST}"

        local db_dump_metadata="export MYSQL_PWD='${db_pass}'; \$(command -v mariadb-dump || echo mysqldump) --max-allowed-packet=512M --force --single-transaction --no-tablespaces --no-data --routines -h${db_host} -P${db_port} -u${db_user} ${db_name} 2> >(grep -v 'Deprecated program name' >&2) | ${sed_filters} | gzip -1"
        warden remote-exec -e "${ENV_SOURCE}" -- bash -c "set -o pipefail; ${db_dump_metadata}" > "${DUMP_FILENAME}"

        local db_dump_data="export MYSQL_PWD='${db_pass}'; \$(command -v mariadb-dump || echo mysqldump) --max-allowed-packet=512M --force --single-transaction --no-tablespaces --skip-triggers --no-create-info ${ignored_opts} -h${db_host} -P${db_port} -u${db_user} ${db_name} 2> >(grep -v 'Deprecated program name' >&2) | ${sed_filters} | gzip -1"
        warden remote-exec -e "${ENV_SOURCE}" -- bash -c "set -o pipefail; ${db_dump_data}" >> "${DUMP_FILENAME}"
        
        printf "✅ \033[32mDatabase dump complete! File: %s\033[0m\n" "${DUMP_FILENAME}"
    else
        # Store on remote (default - single SSH call, faster)
        printf "⌛ \033[1;32mDumping \033[33m%s\033[1;32m database on \033[33m%s\033[1;32m...\033[0m\n" "${db_name}" "${ENV_SOURCE_HOST}"

        # Resolve path for remote
        local remote_backup_dir="${BACKUP_DIR:-~/backup}"
        # Resolve path for remote
        local remote_file="${DUMP_FILENAME}"
        local remote_cmd_file="${DUMP_FILENAME}"
        
        # Replace ~ with $HOME for proper remote shell expansion
        if [[ "${remote_cmd_file:0:2}" == "~/" ]]; then
            remote_cmd_file="\$HOME${remote_cmd_file:1}"
        elif [[ "${remote_cmd_file}" != /* ]]; then
            # Relative path: prepend remote project directory
            remote_cmd_file="${ENV_SOURCE_DIR}/${remote_cmd_file}"
        fi

        # Create directory and dump in single SSH call
        local dump_cmd="
            mkdir -p \"\$(dirname \"${remote_cmd_file}\")\" && 
            export MYSQL_PWD='${db_pass}'; 
            { 
                \$(command -v mariadb-dump || echo mysqldump) --max-allowed-packet=512M --force --single-transaction --no-tablespaces --no-data --routines -h${db_host} -P${db_port} -u${db_user} ${db_name} 2>/dev/null | ${sed_filters};
                \$(command -v mariadb-dump || echo mysqldump) --max-allowed-packet=512M --force --single-transaction --no-tablespaces --skip-triggers --no-create-info ${ignored_opts} -h${db_host} -P${db_port} -u${db_user} ${db_name} 2>/dev/null | ${sed_filters};
            } | gzip > \"${remote_cmd_file}\"
        "
        
        if ! warden remote-exec -e "${ENV_SOURCE}" -- bash -c "${dump_cmd}"; then
            printf "\033[31mError: Database dump failed on remote.\033[0m\n" >&2
            return 1
        fi
        
        printf "✅ \033[32mDatabase dump complete! File: %s:%s\033[0m\n" "${ENV_SOURCE_HOST}" "${remote_file}"
    fi
}

DUMP_FILENAME=
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
        # Remote: default to ~/backup/ on the remote server
        DUMP_FILENAME="~/backup/${WARDEN_ENV_NAME}_${ENV_SOURCE}-$(date +%Y%m%dT%H%M%S).sql.gz"
    fi
fi

if [[ "${NO_NOISE}" -eq "0" && "${NO_PII}" -eq "1" ]]; then
    IGNORED_TABLES+=("${SENSITIVE_TABLES[@]}")
fi

if [[ "${ENV_SOURCE}" = "local" ]]; then
    dump_local
elif [[ -z "${CLOUD_PROJECT+x}" ]]; then
    dump_premise
else
    dump_cloud
fi
