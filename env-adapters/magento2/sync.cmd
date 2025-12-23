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
MEDIA_PATH="pub/media/"
CODE_EXCLUDE=('/generated' '/var' '/pub/media' '/pub/static' '*.gz' '*.zip' '*.tar' '*.7z' '*.sql' '.git' '.idea' 'node_modules')
MEDIA_EXCLUDE=('*.gz' '*.zip' '*.tar' '*.7z' '*.sql' 'tmp' 'itm' 'import' 'export' 'importexport' 'captcha' 'analytics' 'catalog/product/cache' 'catalog/product.rm' 'catalog/product/product' 'opti_image' 'webp_image' 'webp_cache' 'shoppingfeed' 'amasty/blog/cache')

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
        # Skip this in dry-run mode or if it's just a check
        if [[ "${SYNC_DRY_RUN:-0}" -ne 1 ]]; then
            ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -p "${DEST_REMOTE_PORT}" "${DEST_REMOTE_USER}@${DEST_REMOTE_HOST}" \
                "mkdir -p \"${DEST_REMOTE_DIR}/$(dirname "${dest_path}")\""
        fi

        # 2. Run Rsync on Source (Source -> Dest) using Agent Forwarding (-A)
        # We use strict RSH options to suppress warnings on the remote side too
        # In dry-run mode, RSYNC_OPTS contains --dry-run, so we SHOULD execute it to see the file list.
        # Added BatchMode=yes and ConnectTimeout=10 to fail fast if auth/net is broken.
        local cmd="ssh -A -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -p \"${SOURCE_REMOTE_PORT}\" \"${SOURCE_REMOTE_USER}@${SOURCE_REMOTE_HOST}\" \
            \"rsync ${RSYNC_OPTS} ${rsync_excludes_str} \
            -e 'ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes -o ConnectTimeout=10 -p ${DEST_REMOTE_PORT}' \
            \\\"${SOURCE_REMOTE_DIR}/${source_path}\\\" \
            \\\"${DEST_REMOTE_USER}@${DEST_REMOTE_HOST}:${DEST_REMOTE_DIR}/$(dirname "${dest_path}")/\\\"\""

        # Execute the command (RSYNC_OPTS handles safety for existing files, but we blocked mkdir above)
        # If dry-run, this will safely list files.
        # printf "DEBUG: Executing remote command: %s\n" "${cmd}"
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

    # Logic for remote-to-remote DB sync
    if [[ "${SYNC_REMOTE_TO_REMOTE:-0}" -eq 1 ]]; then
        printf "⌛ \033[1;32mSyncing DB from %s to %s ...\033[0m\n" "${SYNC_SOURCE}" "${SYNC_DESTINATION}"
        
        # Source DB info
        local src_db_info=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -p "${SOURCE_REMOTE_PORT}" "${SOURCE_REMOTE_USER}@${SOURCE_REMOTE_HOST}" "php -r \"\\\$a=include \\\"${SOURCE_REMOTE_DIR}/app/etc/env.php\\\"; var_export(\\\$a['db']['connection']['default']);\"")
        local src_db_host=$(php -r "\$a = ${src_db_info}; echo strpos(\$a['host'], ':') === false ? \$a['host'] : explode(':', \$a['host'])[0];")
        local src_db_port=$(php -r "\$a = ${src_db_info}; echo strpos(\$a['host'], ':') === false ? '3306' : explode(':', \$a['host'])[1];")
        local src_db_user=$(php -r "\$a = ${src_db_info}; echo \$a['username'];")
        local src_db_pass=$(php -r "\$a = ${src_db_info}; echo \$a['password'];")
        local src_db_name=$(php -r "\$a = ${src_db_info}; echo \$a['dbname'];")

        # Destination DB info
        local dest_db_info=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -p "${DEST_REMOTE_PORT}" "${DEST_REMOTE_USER}@${DEST_REMOTE_HOST}" "php -r \"\\\$a=include \\\"${DEST_REMOTE_DIR}/app/etc/env.php\\\"; var_export(\\\$a['db']['connection']['default']);\"")
        local dest_db_host=$(php -r "\$a = ${dest_db_info}; echo strpos(\$a['host'], ':') === false ? \$a['host'] : explode(':', \$a['host'])[0];")
        local dest_db_port=$(php -r "\$a = ${dest_db_info}; echo strpos(\$a['host'], ':') === false ? '3306' : explode(':', \$a['host'])[1];")
        local dest_db_user=$(php -r "\$a = ${dest_db_info}; echo \$a['username'];")
        local dest_db_pass=$(php -r "\$a = ${dest_db_info}; echo \$a['password'];")
        local dest_db_name=$(php -r "\$a = ${dest_db_info}; echo \$a['dbname'];")

        # Centralized SQL cleanup filters
        local SED_FILTERS=(
            -e '/999999.*sandbox/d'
            -e 's/DEFINER=[^*]*\*/\*/g'
            -e 's/ROW_FORMAT=FIXED//g'
            -e 's/utf8mb4_0900_ai_ci/utf8mb4_general_ci/g'
            -e 's/utf8mb4_unicode_520_ci/utf8mb4_general_ci/g'
            -e 's/utf8_unicode_520_ci/utf8_general_ci/g'
        )

        printf "Streaming mysqldump from %s to %s ...\n" "${SYNC_SOURCE}" "${SYNC_DESTINATION}"
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -p "${SOURCE_REMOTE_PORT}" "${SOURCE_REMOTE_USER}@${SOURCE_REMOTE_HOST}" \
            "export MYSQL_PWD='${src_db_pass}'; mysqldump --single-transaction --no-tablespaces --routines -h${src_db_host} -P${src_db_port} -u${src_db_user} ${src_db_name}" \
            | sed "${SED_FILTERS[@]}" \
            | ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -p "${DEST_REMOTE_PORT}" "${DEST_REMOTE_USER}@${DEST_REMOTE_HOST}" \
            "export MYSQL_PWD='${dest_db_pass}'; mysql -h${dest_db_host} -P${dest_db_port} -u${dest_db_user} ${dest_db_name}"
        return
    fi

    if [[ "${DIRECTION}" == "upload" ]]; then
        printf "\033[31mError: Database upload is not supported via streaming yet. Use warden db-dump and manual import instead for safety.\033[0m\n"
        return
    fi

    # Logic borrowed from db-import.cmd
    # Get remote DB credentials from env.php
    local db_info=$(${SSH_COMMAND} -p "${ENV_SOURCE_PORT}" "${ENV_SOURCE_USER}@${ENV_SOURCE_HOST}" 'php -r "\$a=include \"'"${ENV_SOURCE_DIR}"'/app/etc/env.php\"; var_export(\$a[\"db\"][\"connection\"][\"default\"]);"')
    local db_host=$(warden env exec -T php-fpm php -r "\$a = ${db_info}; echo strpos(\$a['host'], ':') === false ? \$a['host'] : explode(':', \$a['host'])[0];")
    local db_port=$(warden env exec -T php-fpm php -r "\$a = ${db_info}; echo strpos(\$a['host'], ':') === false ? '3306' : explode(':', \$a['host'])[1];")
    local db_user=$(warden env exec -T php-fpm php -r "\$a = ${db_info}; echo \$a['username'];")
    local db_pass=$(warden env exec -T php-fpm php -r "\$a = ${db_info}; echo \$a['password'];")
    local db_name=$(warden env exec -T php-fpm php -r "\$a = ${db_info}; echo \$a['dbname'];")
    
    # Centralized SQL cleanup filters
    local SED_FILTERS=(
        -e '/999999.*sandbox/d'
        -e 's/DEFINER=[^*]*\*/\*/g'
        -e 's/ROW_FORMAT=FIXED//g'
        -e 's/utf8mb4_0900_ai_ci/utf8mb4_general_ci/g'
        -e 's/utf8mb4_unicode_520_ci/utf8mb4_general_ci/g'
        -e 's/utf8_unicode_520_ci/utf8_general_ci/g'
    )

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
    transfer_files "${DIRECTION}" "${MEDIA_PATH}" "${MEDIA_PATH}" "${MEDIA_EXCLUDE[@]}"
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
    printf "🧹 \033[1;32mFlushing Cache ...\033[0m\n"
    if [[ "${SYNC_REMOTE_TO_REMOTE:-0}" -eq 1 ]]; then
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -p "${DEST_REMOTE_PORT}" "${DEST_REMOTE_USER}@${DEST_REMOTE_HOST}" "cd \"${DEST_REMOTE_DIR}\" && php bin/magento cache:flush" || true
    else
        warden env exec -T php-fpm bin/magento cache:flush || true
    fi
fi

printf "✅ \033[32mSync operation complete!\033[0m\n"
