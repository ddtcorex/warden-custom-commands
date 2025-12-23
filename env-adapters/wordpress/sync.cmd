#!/usr/bin/env bash
set -u

# Variable checks
if [ -z "${ENV_SOURCE_HOST_VAR+x}" ]; then
    printf "Invalid environment '%s'\n" "${ENV_SOURCE}" >&2
    exit 2
fi

# Determine RSYNC options
RSYNC_OPTS="-azvP"
if [[ "${SYNC_DRY_RUN:-0}" -eq 1 ]]; then
    RSYNC_OPTS="${RSYNC_OPTS} --dry-run"
fi
if [[ "${SYNC_DELETE:-0}" -eq 1 ]]; then
    RSYNC_OPTS="${RSYNC_OPTS} --delete"
fi

# Define paths and exclusions
MEDIA_PATH="wp-content/uploads/"
CODE_EXCLUDE=('wp-content/uploads/*' 'wp-content/cache/*' '.git' '.idea' '*.gz' '*.zip' '*.tar' '*.7z' '*.sql')

# Function for file transfer (uses rsync)
function transfer_files() {
    local direction="${1}"
    local source_path="${2}"
    local dest_path="${3}"
    local excludes=("${@:4}")
    
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
            ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -p "${DEST_REMOTE_PORT}" "${DEST_REMOTE_USER}@${DEST_REMOTE_HOST}" \
                "mkdir -p \"${DEST_REMOTE_DIR}/$(dirname "${dest_path}")\""
        fi

        # 2. Run Rsync on Source (Source -> Dest) using Agent Forwarding (-A)
        # In dry-run mode, RSYNC_OPTS contains --dry-run, so we SHOULD execute it.
        local cmd="ssh -A -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -p \"${SOURCE_REMOTE_PORT}\" \"${SOURCE_REMOTE_USER}@${SOURCE_REMOTE_HOST}\" \
            \"rsync ${RSYNC_OPTS} ${rsync_excludes_str} \
            -e 'ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes -o ConnectTimeout=10 -p ${DEST_REMOTE_PORT}' \
            \\\"${SOURCE_REMOTE_DIR}/${source_path}\\\" \
            \\\"${DEST_REMOTE_USER}@${DEST_REMOTE_HOST}:${DEST_REMOTE_DIR}/$(dirname "${dest_path}")/\\\"\""

        eval "${cmd}"
    elif [[ "${direction}" == "download" ]]; then
        printf "⌛ \033[1;32mDownloading from %s:%s to %s ...\033[0m\n" "${ENV_SOURCE_HOST}" "${source_path}" "${dest_path}"
        warden env exec php-fpm rsync ${RSYNC_OPTS} -e "${SSH_COMMAND} -p ${ENV_SOURCE_PORT}" \
            "${exclude_args[@]}" \
            "${ENV_SOURCE_USER}@${ENV_SOURCE_HOST}:${ENV_SOURCE_DIR}/${source_path}" \
            "$(dirname "${dest_path}")/"
    else
        printf "⌛ \033[1;32mUploading from %s to %s:%s ...\033[0m\n" "${source_path}" "${ENV_SOURCE_HOST}" "${dest_path}"
        warden env exec php-fpm rsync ${RSYNC_OPTS} -e "${SSH_COMMAND} -p ${ENV_SOURCE_PORT}" \
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
        local src_db_config=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -p "${SOURCE_REMOTE_PORT}" "${SOURCE_REMOTE_USER}@${SOURCE_REMOTE_HOST}" "grep -E \"define\\s*\\(.*DB_(NAME|USER|PASSWORD|HOST)\" \"${SOURCE_REMOTE_DIR}/wp-config.php\"")
        local src_db_name=$(printf "%s" "${src_db_config}" | grep "DB_NAME" | sed -E "s/.*['\"]DB_NAME['\"]\s*,\s*['\"](.*)['\"].*/\1/")
        local src_db_user=$(printf "%s" "${src_db_config}" | grep "DB_USER" | sed -E "s/.*['\"]DB_USER['\"]\s*,\s*['\"](.*)['\"].*/\1/")
        local src_db_pass=$(printf "%s" "${src_db_config}" | grep "DB_PASSWORD" | sed -E "s/.*['\"]DB_PASSWORD['\"]\s*,\s*['\"](.*)['\"].*/\1/")
        local src_db_host_raw=$(printf "%s" "${src_db_config}" | grep "DB_HOST" | sed -E "s/.*['\"]DB_HOST['\"]\s*,\s*['\"](.*)['\"].*/\1/")
        local src_db_host=${src_db_host_raw%%:*}
        local src_db_port=${src_db_host_raw#*:}
        if [[ "${src_db_host}" == "${src_db_port}" ]]; then src_db_port=3306; fi
        if [[ "${src_db_host}" == "localhost" ]]; then src_db_host="127.0.0.1"; fi
        src_db_host=${src_db_host:-127.0.0.1}
        src_db_port=${src_db_port:-3306}

        # Destination DB info
        local dest_db_config=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -p "${DEST_REMOTE_PORT}" "${DEST_REMOTE_USER}@${DEST_REMOTE_HOST}" "grep -E \"define\\s*\\(.*DB_(NAME|USER|PASSWORD|HOST)\" \"${DEST_REMOTE_DIR}/wp-config.php\"")
        local dest_db_name=$(printf "%s" "${dest_db_config}" | grep "DB_NAME" | sed -E "s/.*['\"]DB_NAME['\"]\s*,\s*['\"](.*)['\"].*/\1/")
        local dest_db_user=$(printf "%s" "${dest_db_config}" | grep "DB_USER" | sed -E "s/.*['\"]DB_USER['\"]\s*,\s*['\"](.*)['\"].*/\1/")
        local dest_db_pass=$(printf "%s" "${dest_db_config}" | grep "DB_PASSWORD" | sed -E "s/.*['\"]DB_PASSWORD['\"]\s*,\s*['\"](.*)['\"].*/\1/")
        local dest_db_host_raw=$(printf "%s" "${dest_db_config}" | grep "DB_HOST" | sed -E "s/.*['\"]DB_HOST['\"]\s*,\s*['\"](.*)['\"].*/\1/")
        local dest_db_host=${dest_db_host_raw%%:*}
        local dest_db_port=${dest_db_host_raw#*:}
        if [[ "${dest_db_host}" == "${dest_db_port}" ]]; then dest_db_port=3306; fi
        if [[ "${dest_db_host}" == "localhost" ]]; then dest_db_host="127.0.0.1"; fi
        dest_db_host=${dest_db_host:-127.0.0.1}
        dest_db_port=${dest_db_port:-3306}

        printf "Streaming mysqldump from %s to %s ...\n" "${SYNC_SOURCE}" "${SYNC_DESTINATION}"
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -p "${SOURCE_REMOTE_PORT}" "${SOURCE_REMOTE_USER}@${SOURCE_REMOTE_HOST}" \
            "export MYSQL_PWD='${src_db_pass}'; mysqldump --single-transaction --no-tablespaces --routines -h${src_db_host} -P${src_db_port} -u${src_db_user} ${src_db_name}" \
            | sed "${SED_FILTERS[@]}" \
            | ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -p "${DEST_REMOTE_PORT}" "${DEST_REMOTE_USER}@${DEST_REMOTE_HOST}" \
            "export MYSQL_PWD='${dest_db_pass}'; mysql -h${dest_db_host} -P${dest_db_port} -u${dest_db_user} ${dest_db_name}"
        return
    fi

    if [[ "${DIRECTION}" == "upload" ]]; then
        printf "\033[31mError: Database upload is not supported via streaming yet.\033[0m\n"
        return
    fi

    # Fetch DB config via SSH
    local db_config=$(${SSH_COMMAND} -p "${ENV_SOURCE_PORT}" "${ENV_SOURCE_USER}@${ENV_SOURCE_HOST}" "grep -E \"define\s*\(.*DB_(NAME|USER|PASSWORD|HOST)\" \"${ENV_SOURCE_DIR}/wp-config.php\"")
    
    # Parse values
    local db_name=$(printf "%s" "${db_config}" | grep "DB_NAME" | sed -E "s/.*['\"]DB_NAME['\"]\s*,\s*['\"](.*)['\"].*/\1/")
    local db_user=$(printf "%s" "${db_config}" | grep "DB_USER" | sed -E "s/.*['\"]DB_USER['\"]\s*,\s*['\"](.*)['\"].*/\1/")
    local db_pass=$(printf "%s" "${db_config}" | grep "DB_PASSWORD" | sed -E "s/.*['\"]DB_PASSWORD['\"]\s*,\s*['\"](.*)['\"].*/\1/")
    local db_host_raw=$(printf "%s" "${db_config}" | grep "DB_HOST" | sed -E "s/.*['\"]DB_HOST['\"]\s*,\s*['\"](.*)['\"].*/\1/")

    local db_host=${db_host_raw%%:*}
    local db_port=${db_host_raw#*:}
    if [[ "${db_host}" == "${db_port}" ]]; then db_port=3306; fi
    if [[ "${db_host}" == "localhost" ]]; then db_host="127.0.0.1"; fi

    db_host=${db_host:-127.0.0.1}
    db_port=${db_port:-3306}
    
    printf "Streaming mysqldump from %s:%s ...\n" "${ENV_SOURCE_HOST}" "${db_name}"
    ${SSH_COMMAND} -p "${ENV_SOURCE_PORT}" "${ENV_SOURCE_USER}@${ENV_SOURCE_HOST}" \
        "export MYSQL_PWD='${db_pass}'; mysqldump --single-transaction --no-tablespaces --routines -h${db_host} -P${db_port} -u${db_user} ${db_name}" \
        | sed "${SED_FILTERS[@]}" \
        | warden db import --force
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
        if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -p "${DEST_REMOTE_PORT}" "${DEST_REMOTE_USER}@${DEST_REMOTE_HOST}" "cd \"${DEST_REMOTE_DIR}\" && wp --info &>/dev/null"; then
            printf "🧹 \033[1;32mFlushing Cache via WP-CLI on %s ...\033[0m\n" "${SYNC_DESTINATION}"
            ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -p "${DEST_REMOTE_PORT}" "${DEST_REMOTE_USER}@${DEST_REMOTE_HOST}" "cd \"${DEST_REMOTE_DIR}\" && wp cache flush" || true
        fi
    else
        if warden env exec php-fpm wp --info &>/dev/null; then
            printf "🧹 \033[1;32mFlushing Cache via WP-CLI ...\033[0m\n"
            warden env exec -T php-fpm wp cache flush || true
        fi
    fi
fi

printf "✅ \033[32mSync operation complete!\033[0m\n"
