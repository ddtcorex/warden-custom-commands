#!/usr/bin/env bash
set -u

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
    # Extract local DB info
    local db_info=$(warden env exec -T db bash -c 'echo "MYSQL_USER=$MYSQL_USER"; echo "MYSQL_PASSWORD=$MYSQL_PASSWORD"; echo "MYSQL_DATABASE=$MYSQL_DATABASE"')
    local DB_USER=$(echo "${db_info}" | grep "^MYSQL_USER=" | cut -d= -f2-)
    local DB_PASS=$(echo "${db_info}" | grep "^MYSQL_PASSWORD=" | cut -d= -f2-)
    local DB_NAME=$(echo "${db_info}" | grep "^MYSQL_DATABASE=" | cut -d= -f2-)
    
    printf "⌛ \033[1;32mDumping local database (\033[33m%s\033[1;32m)...\033[0m\n" "${DB_NAME}"
    
    local dump_bin="mysqldump"
    if [[ "${MYSQL_DISTRIBUTION:-}" == *"mariadb"* ]]; then
        dump_bin="mariadb-dump"
    fi
 
    local sed_filters="sed -e 's/DEFINER=[^*]*\\*/\\*/g'"

    # Ensure local directory exists
    # Ensure local directory exists
    mkdir -p "$(dirname "${DUMP_FILENAME}")"

    local ignored_opts=""
    if [[ "${EXCLUDE_SENSITIVE_DATA:-0}" -eq "1" ]]; then
        for table in "${IGNORED_TABLES[@]}"; do
            ignored_opts+=" --ignore-table=${DB_NAME}.${table}"
        done
    fi

    # Execute dump
    warden env exec -T db bash -c "export MYSQL_PWD='${DB_PASS}'; ${dump_bin} --no-tablespaces --single-transaction --routines ${ignored_opts} -hdb -u${DB_USER} ${DB_NAME} 2> >(grep -v 'Deprecated program name' >&2) | ${sed_filters}" | gzip > "${DUMP_FILENAME}"
    
    printf "✅ \033[32mDatabase dump complete! File: %s\033[0m\n" "${DUMP_FILENAME}"
}

function dump_premise () {
    # Remote dump logic
    local db_info=$(get_remote_db_info "${ENV_SOURCE_DIR}")
    local db_host=$(echo "${db_info}" | grep "^DB_HOST=" | cut -d= -f2-)
    local db_port=$(echo "${db_info}" | grep "^DB_PORT=" | cut -d= -f2-)
    local db_user=$(echo "${db_info}" | grep "^DB_USERNAME=" | cut -d= -f2-)
    local db_pass=$(echo "${db_info}" | grep "^DB_PASSWORD=" | cut -d= -f2-)
    local db_name=$(echo "${db_info}" | grep "^DB_DATABASE=" | cut -d= -f2-)
    
    local sed_filters="sed -e 's/DEFINER=[^*]*\\*/\\*/g'"

    local ignored_opts=""
    if [[ "${EXCLUDE_SENSITIVE_DATA:-0}" -eq "1" ]]; then
        for table in "${IGNORED_TABLES[@]}"; do
            ignored_opts+=" --ignore-table=${db_name}.${table}"
        done
    fi

    if [[ "${LOCAL_DOWNLOAD}" -eq 1 ]]; then
         # Download to local
         printf "⌛ \033[1;32mDumping \033[33m%s\033[1;32m database from \033[33m%s\033[1;32m to local...\033[0m\n" "${db_name}" "${ENV_SOURCE_HOST}"
         
         local dump_cmd="export MYSQL_PWD='${db_pass}'; \$(command -v mariadb-dump || echo mysqldump) --no-tablespaces --single-transaction --routines ${ignored_opts} -h${db_host} -P${db_port} -u${db_user} ${db_name} 2> >(grep -v 'Deprecated program name' >&2) | ${sed_filters} | gzip"
         
         warden remote-exec -e "${ENV_SOURCE}" -- bash -c "set -o pipefail; ${dump_cmd}" > "${DUMP_FILENAME}"
         
         printf "✅ \033[32mDatabase dump complete! File: %s\033[0m\n" "${DUMP_FILENAME}"
    else
         # Remote storage (original logic)
         printf "⌛ \033[1;32mDumping \033[33m%s\033[1;32m database on \033[33m%s\033[1;32m...\033[0m\n" "${db_name}" "${ENV_SOURCE_HOST}"
         
         local remote_cmd_file="${DUMP_FILENAME}"
         if [[ "${remote_cmd_file:0:2}" == "~/" ]]; then
            remote_cmd_file="\$HOME${remote_cmd_file:1}"
         elif [[ "${remote_cmd_file}" != /* ]]; then
            remote_cmd_file="${ENV_SOURCE_DIR}/${remote_cmd_file}"
         fi
         
         local dump_cmd="
            mkdir -p \"\$(dirname \"${remote_cmd_file}\")\" && 
            export MYSQL_PWD='${db_pass}'; 
            \$(command -v mariadb-dump || echo mysqldump) --no-tablespaces --single-transaction --routines ${ignored_opts} -h${db_host} -P${db_port} -u${db_user} ${db_name} 2> >(grep -v 'Deprecated program name' >&2) | ${sed_filters} | gzip > \"${remote_cmd_file}\"
         "
         
         if ! warden remote-exec -e "${ENV_SOURCE}" -- bash -c "${dump_cmd}"; then
             printf "\033[31mError: Database dump failed on remote.\033[0m\n" >&2
             return 1
         fi
         
         printf "✅ \033[32mDatabase dump complete! File: %s:%s\033[0m\n" "${ENV_SOURCE_HOST}" "${DUMP_FILENAME}"
    fi
}

DUMP_FILENAME=""
LOCAL_DOWNLOAD=0
EXCLUDE_SENSITIVE_DATA=0

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
        --exclude-sensitive-data)
            EXCLUDE_SENSITIVE_DATA=1
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
