#!/usr/bin/env bash
set -u

# Variable checks
if [ -z "${ENV_SOURCE_HOST_VAR+x}" ]; then
    printf "Invalid environment '%s'\n" "${ENV_SOURCE}" >&2
    exit 2
fi

# Determine RSYNC options
RSYNC_OPTS="-azvPLk --force"
if [[ "${SYNC_DRY_RUN:-0}" -eq 1 ]]; then
    RSYNC_OPTS="${RSYNC_OPTS} --dry-run"
fi
if [[ "${SYNC_DELETE:-0}" -eq 1 ]]; then
    RSYNC_OPTS="${RSYNC_OPTS} --delete"
fi

# Define paths and exclusions
MEDIA_PATH="wp-content/uploads"
CODE_EXCLUDE=('wp-config.php' 'wp-content/uploads/*' 'wp-content/cache/*' '.git' '.idea' '*.gz' '*.zip' '*.tar' '*.7z' '*.sql' '.env')

SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
source "${SCRIPT_DIR}/utils.sh"

# Function for file transfer (uses rsync)
function transfer_files() {
    local direction="${1}"
    local source_path="${2%/}"
    local dest_path="${3%/}"
    local excludes=("${@:4}")

    # Path-aware wp-config.php exclusion (only if it exists on destination)
    local target_file="wp-config.php"
    local rel_exclude=""
    local exists_on_dest=0

    # 1. Check if it exists on destination
    if [[ "${SYNC_REMOTE_TO_REMOTE:-0}" -eq 1 ]]; then
        if ssh ${SSH_OPTS} -p "${DEST_REMOTE_PORT}" "${DEST_REMOTE_USER}@${DEST_REMOTE_HOST}" "[ -e \"${DEST_REMOTE_DIR}/${target_file}\" ]" ; then
            exists_on_dest=1
        fi
    elif [[ "${direction}" == "download" ]]; then
        if [[ -e "${WARDEN_ENV_PATH}/${target_file}" ]]; then
            exists_on_dest=1
        fi
    else
        # upload
        if ssh ${SSH_OPTS} -p "${ENV_SOURCE_PORT}" "${ENV_SOURCE_USER}@${ENV_SOURCE_HOST}" "[ -e \"${ENV_SOURCE_DIR}/${target_file}\" ]" ; then
            exists_on_dest=1
        fi
    fi

    if [[ "${exists_on_dest}" -eq 1 ]]; then
        # Normalize target and source paths for comparison
        local norm_target="/${target_file}"
        local norm_src=$(echo "/${source_path}" | sed -e 's|/\./|/|g' -e 's|/\.$|/|' -e 's|/\{2,\}|/|g')
        
        # If source ends in /, rsync's root is inside that dir
        if [[ "${norm_src}" == */ ]]; then
            local src_dir="${norm_src%/}"
            if [[ "${norm_target}" == "${src_dir}"/* ]]; then
                rel_exclude="${norm_target#$src_dir}"
            fi
        else
            # If source doesn't end in /, rsync's root is its parent
            local src_parent=$(dirname "${norm_src}")
            [[ "${src_parent}" == "/" ]] && src_parent=""
            if [[ "${norm_target}" == "${src_parent}"/* ]]; then
                rel_exclude="${norm_target#$src_parent}"
            fi
        fi
    fi

    if [[ -n "${rel_exclude}" ]]; then
        excludes+=( "${rel_exclude}" )
    fi
    
    local exclude_args=()
    for item in "${excludes[@]}"; do
        exclude_args+=( --exclude="${item}" )
    done

    if [[ "${SYNC_REMOTE_TO_REMOTE:-0}" -eq 1 ]]; then
        printf "⌛ \033[1;32mSyncing from %s to %s (remote rsync) ...\033[0m\n" "${SYNC_SOURCE}" "${SYNC_DESTINATION}"
        
        local rsync_excludes_str=""
        for item in "${excludes[@]}"; do
            rsync_excludes_str+=" --exclude='${item}'"
        done

        # 1. Check/Create Destination Parent Directory (Local -> Dest)
        if [[ "${SYNC_DRY_RUN:-0}" -ne 1 ]]; then
            ssh ${SSH_OPTS} -p "${DEST_REMOTE_PORT}" "${DEST_REMOTE_USER}@${DEST_REMOTE_HOST}" \
                "mkdir -p \"${DEST_REMOTE_DIR}/$(dirname "${dest_path}")\""
        fi

        # 2. Run Rsync on Source (Source -> Dest) using Agent Forwarding (-A)
        # In dry-run mode, RSYNC_OPTS contains --dry-run, so we SHOULD execute it.
        local cmd="ssh -A ${SSH_OPTS} -p \"${SOURCE_REMOTE_PORT}\" \"${SOURCE_REMOTE_USER}@${SOURCE_REMOTE_HOST}\" \
            \"rsync ${RSYNC_OPTS} ${rsync_excludes_str} \
            -e 'ssh ${SSH_OPTS} -o BatchMode=yes -o ConnectTimeout=10 -p ${DEST_REMOTE_PORT}' \
            \\\"${SOURCE_REMOTE_DIR}/${source_path}\\\" \
            \\\"${DEST_REMOTE_USER}@${DEST_REMOTE_HOST}:${DEST_REMOTE_DIR}/$(dirname "${dest_path}")/\\\"\""

        eval "${cmd}"
    elif [[ "${direction}" == "download" ]]; then
        printf "⌛ \033[1;32mDownloading from %s:%s to %s ...\033[0m\n" "${ENV_SOURCE_HOST}" "${source_path}" "${dest_path}"
        warden env exec php-fpm rsync ${RSYNC_OPTS} -e "ssh ${SSH_OPTS} -p ${ENV_SOURCE_PORT}" \
            "${exclude_args[@]}" \
            "${ENV_SOURCE_USER}@${ENV_SOURCE_HOST}:${ENV_SOURCE_DIR}/${source_path}" \
            "$(dirname "${dest_path}")/"
    else
        printf "⌛ \033[1;32mUploading from %s to %s:%s ...\033[0m\n" "${source_path}" "${ENV_SOURCE_HOST}" "${dest_path}"
        warden env exec php-fpm rsync ${RSYNC_OPTS} -e "ssh ${SSH_OPTS} -p ${ENV_SOURCE_PORT}" \
            "${exclude_args[@]}" \
            "${source_path}" "${ENV_SOURCE_USER}@${ENV_SOURCE_HOST}:${ENV_SOURCE_DIR}/$(dirname "${dest_path}")/"
    fi
}

# Function for database sync (streaming)
function sync_database() {
    if [[ "${SYNC_DRY_RUN}" -eq 1 ]]; then
        printf "\033[33m[Dry Run] Database sync would stream from source ...\033[0m\n"
        return
    fi

    local SED_FILTERS=(
        -e '/999999.*sandbox/d'
        -e 's/DEFINER=[^*]*\*/\*/g'
        -e 's/utf8mb4_0900_ai_ci/utf8mb4_general_ci/g'
        -e 's/utf8mb4_unicode_520_ci/utf8mb4_general_ci/g'
        -e 's/utf8_unicode_520_ci/utf8_general_ci/g'
    )

    if [[ "${SYNC_REMOTE_TO_REMOTE:-0}" -eq 1 ]]; then
        printf "⌛ \033[1;32mSyncing DB from %s to %s ...\033[0m\n" "${SYNC_SOURCE}" "${SYNC_DESTINATION}"

        # Source DB info
        local src_db_info=$(get_remote_db_info "${SOURCE_REMOTE_HOST}" "${SOURCE_REMOTE_PORT}" "${SOURCE_REMOTE_USER}" "${SOURCE_REMOTE_DIR}")
        local src_db_host=$(echo "${src_db_info}" | grep "^DB_HOST=" | cut -d= -f2-)
        local src_db_port=$(echo "${src_db_info}" | grep "^DB_PORT=" | cut -d= -f2-)
        local src_db_user=$(echo "${src_db_info}" | grep "^DB_USERNAME=" | cut -d= -f2-)
        local src_db_pass=$(echo "${src_db_info}" | grep "^DB_PASSWORD=" | cut -d= -f2-)
        local src_db_name=$(echo "${src_db_info}" | grep "^DB_DATABASE=" | cut -d= -f2-)

        # Destination DB info
        local dest_db_info=$(get_remote_db_info "${DEST_REMOTE_HOST}" "${DEST_REMOTE_PORT}" "${DEST_REMOTE_USER}" "${DEST_REMOTE_DIR}")
        local dest_db_host=$(echo "${dest_db_info}" | grep "^DB_HOST=" | cut -d= -f2-)
        local dest_db_port=$(echo "${dest_db_info}" | grep "^DB_PORT=" | cut -d= -f2-)
        local dest_db_user=$(echo "${dest_db_info}" | grep "^DB_USERNAME=" | cut -d= -f2-)
        local dest_db_pass=$(echo "${dest_db_info}" | grep "^DB_PASSWORD=" | cut -d= -f2-)
        local dest_db_name=$(echo "${dest_db_info}" | grep "^DB_DATABASE=" | cut -d= -f2-)

        # Backup Destination DB (Remote)
        if [[ "${SYNC_BACKUP}" -eq 1 ]]; then
            printf "  Creating backup of destination database...\n"
            local backup_file="${SYNC_BACKUP_DIR}/${WARDEN_ENV_NAME}_backup_$(date +%Y%m%d_%H%M%S).sql.gz"
            if ! ssh ${SSH_OPTS} -p "${DEST_REMOTE_PORT}" "${DEST_REMOTE_USER}@${DEST_REMOTE_HOST}" \
                "mkdir -p \"${SYNC_BACKUP_DIR}\" && export MYSQL_PWD='${dest_db_pass}'; \$(command -v mariadb-dump || echo mysqldump) --force --single-transaction --no-tablespaces --routines -h${dest_db_host} -P${dest_db_port} -u${dest_db_user} ${dest_db_name} | gzip > \"${backup_file}\""; then
                printf "\033[31mError: Destination database backup failed.\033[0m\n" >&2
                return 1
            fi
            printf "  ✅ Backup saved to: %s:%s\n" "${DEST_REMOTE_HOST}" "${backup_file}"
        fi

        printf "Streaming mysqldump from %s to %s ...\n" "${SYNC_SOURCE}" "${SYNC_DESTINATION}"
        ssh ${SSH_OPTS} -p "${SOURCE_REMOTE_PORT}" "${SOURCE_REMOTE_USER}@${SOURCE_REMOTE_HOST}" \
            "export MYSQL_PWD='${src_db_pass}'; \$(command -v mariadb-dump || echo mysqldump) --single-transaction --no-tablespaces --routines -h${src_db_host} -P${src_db_port} -u${src_db_user} ${src_db_name}" \
            | sed "${SED_FILTERS[@]}" \
            | ssh ${SSH_OPTS} -p "${DEST_REMOTE_PORT}" "${DEST_REMOTE_USER}@${DEST_REMOTE_HOST}" \
            "export MYSQL_PWD='${dest_db_pass}'; \$(command -v mariadb || echo mysql) -h${dest_db_host} -P${dest_db_port} -u${dest_db_user} ${dest_db_name}"
        return
    fi

    if [[ "${DIRECTION}" == "upload" ]]; then
        printf "⌛ \033[1;32mSyncing DB from local to %s ...\033[0m\n" "${SYNC_DESTINATION}"

        # 1. Get Destination (Remote) DB Credentials
        local dest_db_info=$(get_remote_db_info "${ENV_SOURCE_HOST}" "${ENV_SOURCE_PORT}" "${ENV_SOURCE_USER}" "${ENV_SOURCE_DIR}")
        local dest_db_host=$(echo "${dest_db_info}" | grep "^DB_HOST=" | cut -d= -f2-)
        local dest_db_port=$(echo "${dest_db_info}" | grep "^DB_PORT=" | cut -d= -f2-)
        local dest_db_user=$(echo "${dest_db_info}" | grep "^DB_USERNAME=" | cut -d= -f2-)
        local dest_db_pass=$(echo "${dest_db_info}" | grep "^DB_PASSWORD=" | cut -d= -f2-)
        local dest_db_name=$(echo "${dest_db_info}" | grep "^DB_DATABASE=" | cut -d= -f2-)

        # Backup Destination DB (Remote - Upload)
        if [[ "${SYNC_BACKUP}" -eq 1 ]]; then
            printf "  Creating backup of destination database...\n"
            local backup_file="${SYNC_BACKUP_DIR}/${WARDEN_ENV_NAME}_backup_$(date +%Y%m%d_%H%M%S).sql.gz"
            if ! ssh ${SSH_OPTS} -p "${ENV_SOURCE_PORT}" "${ENV_SOURCE_USER}@${ENV_SOURCE_HOST}" \
                "mkdir -p \"${SYNC_BACKUP_DIR}\" && export MYSQL_PWD='${dest_db_pass}'; \$(command -v mariadb-dump || echo mysqldump) --force --single-transaction --no-tablespaces --routines -h${dest_db_host} -P${dest_db_port} -u${dest_db_user} ${dest_db_name} | gzip > \"${backup_file}\""; then
                printf "\033[31mError: Destination database backup failed.\033[0m\n" >&2
                return 1
            fi
            printf "  ✅ Backup saved to: %s:%s\n" "${ENV_SOURCE_HOST}" "${backup_file}"
        fi
        
        # 2. Get Local (Source) DB Credentials
        local src_db_user=$(warden env exec -T db printenv MYSQL_USER)
        local src_db_pass=$(warden env exec -T db printenv MYSQL_PASSWORD)
        local src_db_name=$(warden env exec -T db printenv MYSQL_DATABASE)
        
        src_db_user=${src_db_user:-wordpress}
        src_db_pass=${src_db_pass:-wordpress}
        src_db_name=${src_db_name:-wordpress}
        local src_db_host="db"
        local src_db_port=3306

        DUMP_BIN="mysqldump"
        if [[ "${MYSQL_DISTRIBUTION:-}" == *"mariadb"* ]]; then
            DUMP_BIN="mariadb-dump"
        fi

        printf "Streaming mysqldump from local to %s ...\n" "${SYNC_DESTINATION}"

        if ! warden env exec -T db bash -c "export MYSQL_PWD='${src_db_pass}'; ${DUMP_BIN} --single-transaction --no-tablespaces --routines -h${src_db_host} -P${src_db_port} -u${src_db_user} ${src_db_name}" \
            | sed "${SED_FILTERS[@]}" \
            | ssh ${SSH_OPTS} -p "${ENV_SOURCE_PORT}" "${ENV_SOURCE_USER}@${ENV_SOURCE_HOST}" \
            "export MYSQL_PWD='${dest_db_pass}'; \$(command -v mariadb || echo mysql) -h${dest_db_host} -P${dest_db_port} -u${dest_db_user} ${dest_db_name}"; then
            
            printf "\033[31mError: Database upload from local failed.\033[0m\n" >&2
            return 1
        fi

        return 0
    fi

    # Download logic (Implicit else)
    if [[ "${SYNC_BACKUP}" -eq 1 ]]; then
        local local_backup_dir="${SYNC_BACKUP_DIR/#\~/$HOME}"
        local backup_file="${local_backup_dir}/${WARDEN_ENV_NAME}_backup_$(date +%Y%m%d_%H%M%S).sql.gz"
        mkdir -p "${local_backup_dir}"
        
        if ! warden db-dump --file="${backup_file}"; then
             printf "\033[31mError: Local database backup failed.\033[0m\n" >&2
             return 1
        fi
    fi

    # Fetch DB info
    local db_info=$(get_remote_db_info "${ENV_SOURCE_HOST}" "${ENV_SOURCE_PORT}" "${ENV_SOURCE_USER}" "${ENV_SOURCE_DIR}")
    local db_host=$(echo "${db_info}" | grep "^DB_HOST=" | cut -d= -f2-)
    local db_port=$(echo "${db_info}" | grep "^DB_PORT=" | cut -d= -f2-)
    local db_user=$(echo "${db_info}" | grep "^DB_USERNAME=" | cut -d= -f2-)
    local db_pass=$(echo "${db_info}" | grep "^DB_PASSWORD=" | cut -d= -f2-)
    local db_name=$(echo "${db_info}" | grep "^DB_DATABASE=" | cut -d= -f2-)
    
    printf "Streaming mysqldump from %s:%s ...\n" "${ENV_SOURCE_HOST}" "${db_name}"
    ssh ${SSH_OPTS} -p "${ENV_SOURCE_PORT}" "${ENV_SOURCE_USER}@${ENV_SOURCE_HOST}" \
        "export MYSQL_PWD='${db_pass}'; \$(command -v mariadb-dump || echo mysqldump) --single-transaction --no-tablespaces --routines -h${db_host} -P${db_port} -u${db_user} ${db_name}" \
        | sed "${SED_FILTERS[@]}" \
        | warden env exec -T db bash -c '$(command -v mariadb || echo mysql) -hdb -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" -f'
}

# 1. Sync Files/Code
if [[ -z "${SYNC_PATH}" ]] && [[ "${SYNC_TYPE_FILE}" -eq 1 || "${SYNC_TYPE_FULL}" -eq 1 ]]; then
    transfer_files "${DIRECTION}" "./" "./" "${CODE_EXCLUDE[@]}"
fi

# 2. Sync Media
if [[ -z "${SYNC_PATH}" ]] && [[ "${SYNC_TYPE_MEDIA}" -eq 1 || "${SYNC_TYPE_FULL}" -eq 1 ]]; then
    transfer_files "${DIRECTION}" "${MEDIA_PATH}" "${MEDIA_PATH}"
fi

# 3. Sync Custom Path
if [[ -n "${SYNC_PATH}" ]]; then
    transfer_files "${DIRECTION}" "${SYNC_PATH}" "${SYNC_PATH}"
fi

# 4. Sync Database
if [[ "${SYNC_TYPE_DB}" -eq 1 || "${SYNC_TYPE_FULL}" -eq 1 ]]; then
    sync_database
fi

# 5. Post-Sync Cache Flush
if [[ "${SYNC_NO_FLUSH:-0}" -eq 0 && "${SYNC_DRY_RUN:-0}" -eq 0 ]]; then
    if [[ "${SYNC_REMOTE_TO_REMOTE:-0}" -eq 1 ]]; then
        if ssh ${SSH_OPTS} -p "${DEST_REMOTE_PORT}" "${DEST_REMOTE_USER}@${DEST_REMOTE_HOST}" "cd \"${DEST_REMOTE_DIR}\" && wp --info &>/dev/null"; then
            printf "🧹 \033[1;32mFlushing Cache via WP-CLI on %s ...\033[0m\n" "${SYNC_DESTINATION}"
            ssh ${SSH_OPTS} -p "${DEST_REMOTE_PORT}" "${DEST_REMOTE_USER}@${DEST_REMOTE_HOST}" "cd \"${DEST_REMOTE_DIR}\" && wp cache flush" || true
        fi
    else
        if warden env exec php-fpm wp --info &>/dev/null; then
            printf "🧹 \033[1;32mFlushing Cache via WP-CLI ...\033[0m\n"
            warden env exec -T php-fpm wp cache flush || true
        fi
    fi
fi

printf "✅ \033[32mSync operation complete!\033[0m\n"
