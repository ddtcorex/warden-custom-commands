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

IGNORED_TABLES=(
)

function dump_local () {
    # Single Docker exec call instead of 3 separate calls
    local db_info=$(warden env exec -T db bash -c 'echo "MYSQL_USER=$MYSQL_USER"; echo "MYSQL_PASSWORD=$MYSQL_PASSWORD"; echo "MYSQL_DATABASE=$MYSQL_DATABASE"')
    local DB_USER=$(echo "${db_info}" | grep "^MYSQL_USER=" | cut -d= -f2-)
    local DB_PASS=$(echo "${db_info}" | grep "^MYSQL_PASSWORD=" | cut -d= -f2-)
    local DB_NAME=$(echo "${db_info}" | grep "^MYSQL_DATABASE=" | cut -d= -f2-)

    # Get local DB prefix
    local DB_PREFIX=$(warden env exec -T php-fpm grep -E "^\s*\\\$table_prefix\s*=" wp-config.php 2>/dev/null | sed -E "s/.*['\"](.*)['\"].*/\1/")
    DB_PREFIX=${DB_PREFIX:-wp_}

    printf "⌛ \033[1;32mDumping local database (\033[33m%s\033[1;32m)...\033[0m\n" "${DB_NAME}"
    
    mkdir -p "$(dirname "${DUMP_FILENAME}")"

    local current_ignored=()
    if [[ "${NO_NOISE:-0}" -eq 1 ]]; then
        current_ignored+=("${IGNORED_TABLES[@]}")
    fi
    if [[ "${NO_PII:-0}" -eq "1" ]]; then
        current_ignored+=("${SENSITIVE_TABLES[@]}")
    fi

    local ignored_opts=""
    for table in "${current_ignored[@]}"; do
        ignored_opts+=" --ignore-table=${DB_NAME}.${DB_PREFIX}${table}"
    done

    local db_dump="export MYSQL_PWD='${DB_PASS}'; \$(command -v mariadb-dump || echo mysqldump) --max-allowed-packet=512M --no-tablespaces --single-transaction --routines ${ignored_opts} -hdb -u${DB_USER} ${DB_NAME} 2> >(grep -v 'Deprecated program name' >&2) | gzip"
    warden env exec -T db bash -c "${db_dump}" > "${DUMP_FILENAME}"

    printf "✅ \033[32mDatabase dump complete! File: %s\033[0m\n" "${DUMP_FILENAME}"
}

function dump_premise () {
    # Fetch DB creds via SSH using helper
    local db_info=$(get_remote_db_info "${ENV_SOURCE_DIR}")
    
    local db_host=$(echo "${db_info}" | grep "^DB_HOST=" | cut -d= -f2-)
    local db_port=$(echo "${db_info}" | grep "^DB_PORT=" | cut -d= -f2-)
    local db_user=$(echo "${db_info}" | grep "^DB_USERNAME=" | cut -d= -f2-)
    local db_pass=$(echo "${db_info}" | grep "^DB_PASSWORD=" | cut -d= -f2-)
    local db_name=$(echo "${db_info}" | grep "^DB_DATABASE=" | cut -d= -f2-)
    local DB_PREFIX=$(echo "${db_info}" | grep "^DB_PREFIX=" | cut -d= -f2-)

    local sed_filters="sed -e 's/DEFINER=[^*]*\\*/\\*/g'"

    local current_ignored=()
    if [[ "${NO_NOISE:-0}" -eq 1 ]]; then
        current_ignored+=("${IGNORED_TABLES[@]}")
    fi
    if [[ "${NO_PII:-0}" -eq "1" ]]; then
        current_ignored+=("${SENSITIVE_TABLES[@]}")
    fi

    local ignored_opts=""
    for table in "${current_ignored[@]}"; do
        ignored_opts+=" --ignore-table=${db_name}.${DB_PREFIX}${table}"
    done

    if [[ "${LOCAL_DOWNLOAD}" -eq 1 ]]; then
        # Download to local
        printf "⌛ \033[1;32mDumping \033[33m%s\033[1;32m database from \033[33m%s\033[1;32m to local...\033[0m\n" "${db_name}" "${ENV_SOURCE_HOST}"

        local db_dump="export MYSQL_PWD='${db_pass}'; \$(command -v mariadb-dump || echo mysqldump) --max-allowed-packet=512M --no-tablespaces --single-transaction --routines ${ignored_opts} -h${db_host} -P${db_port} -u${db_user} ${db_name} 2> >(grep -v 'Deprecated program name' >&2) | ${sed_filters} | gzip -1"
        warden remote-exec -e "${ENV_SOURCE}" -- bash -c "set -o pipefail; ${db_dump}" > "${DUMP_FILENAME}"

        printf "✅ \033[32mDatabase dump complete! File: %s\033[0m\n" "${DUMP_FILENAME}"
    else
        # Store on remote (default)
        printf "⌛ \033[1;32mDumping \033[33m%s\033[1;32m database on \033[33m%s\033[1;32m...\033[0m\n" "${db_name}" "${ENV_SOURCE_HOST}"

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

        local dump_cmd="
            mkdir -p \"\$(dirname \"${remote_cmd_file}\")\" && 
            export MYSQL_PWD='${db_pass}'; 
            \$(command -v mariadb-dump || echo mysqldump) --max-allowed-packet=512M --no-tablespaces --single-transaction --routines ${ignored_opts} -h${db_host} -P${db_port} -u${db_user} ${db_name} 2> >(grep -v 'Deprecated program name' >&2) | ${sed_filters} | gzip > \"${remote_cmd_file}\"
        "
        
        if ! warden remote-exec -e "${ENV_SOURCE}" -- bash -c "${dump_cmd}"; then
            printf "\033[31mError: Database dump failed on remote.\033[0m\n" >&2
            return 1
        fi
        
        printf "✅ \033[32mDatabase dump complete! File: %s:%s\033[0m\n" "${ENV_SOURCE_HOST}" "${remote_file}"
    fi
}

DUMP_FILENAME=""
LOCAL_DOWNLOAD=${LOCAL_DOWNLOAD:-0}
NO_PII=${NO_PII:-0}
NO_NOISE=${NO_NOISE:-0}

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
        --local)
            LOCAL_DOWNLOAD=1
            shift
            ;;
        -N|--no-noise)
            NO_NOISE=1
            shift
            ;;
        -S|--no-pii)
            NO_PII=1
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
        DUMP_FILENAME="~/backup/${WARDEN_ENV_NAME}_${ENV_SOURCE}-$(date +%Y%m%dT%H%M%S).sql.gz"
    fi
fi

if [[ "${ENV_SOURCE}" = "local" ]]; then
    dump_local
else
    dump_premise
fi
