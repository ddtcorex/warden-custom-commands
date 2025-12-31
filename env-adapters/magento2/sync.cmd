#!/usr/bin/env bash
set -u

# Variable checks
if [ -z "${ENV_SOURCE_HOST_VAR+x}" ]; then
    printf "Invalid environment '%s'\n" "${ENV_SOURCE}" >&2
    exit 2
fi

# Determine RSYNC options
RSYNC_OPTS="-azvPLk"
if [[ "${SYNC_DRY_RUN:-0}" -eq 1 ]]; then
    RSYNC_OPTS="${RSYNC_OPTS} --dry-run"
fi
if [[ "${SYNC_DELETE:-0}" -eq 1 ]]; then
    RSYNC_OPTS="${RSYNC_OPTS} --delete"
fi

# Define paths and exclusions
MEDIA_PATH="pub/media"
CODE_EXCLUDE=('/generated' '/var' '/pub/media' '/pub/static' '*.gz' '*.zip' '*.tar' '*.7z' '*.sql' '.git' '.idea' 'node_modules')
MEDIA_EXCLUDE=('*.gz' '*.zip' '*.tar' '*.7z' '*.sql' 'tmp' 'itm' 'import' 'export' 'importexport' 'captcha' 'analytics' 'catalog/product/cache' 'catalog/product.rm' 'catalog/product/product' 'opti_image' 'webp_image' 'webp_cache' 'shoppingfeed' 'amasty/blog/cache')
# Exclude product images by default unless --include-product is passed
if [[ "${SYNC_INCLUDE_PRODUCT:-0}" -eq 0 ]]; then
    MEDIA_EXCLUDE+=('catalog/product')
fi

# Function for file transfer (uses rsync)
function transfer_files() {
    local direction="${1}"
    local source_path="${2%/}"
    local dest_path="${3%/}"
    local excludes=("${@:4}")

    # Path-aware env.php exclusion (only if it exists on destination)
    local target_file="app/etc/env.php"
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
        local norm_src=$(echo "/${source_path}" | sed -e 's|/\./|/|g' -e 's|/\.$||' -e 's|/\{2,\}|/|g')
        
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
        # Skip this in dry-run mode or if it's just a check
        if [[ "${SYNC_DRY_RUN:-0}" -ne 1 ]]; then
            ssh ${SSH_OPTS} -p "${DEST_REMOTE_PORT}" "${DEST_REMOTE_USER}@${DEST_REMOTE_HOST}" \
                "mkdir -p \"${DEST_REMOTE_DIR}/$(dirname "${dest_path}")\""
        fi

        # 2. Run Rsync on Source (Source -> Dest) using Agent Forwarding (-A)
        # We use strict RSH options to suppress warnings on the remote side too
        # In dry-run mode, RSYNC_OPTS contains --dry-run, so we SHOULD execute it to see the file list.
        # Added BatchMode=yes and ConnectTimeout=10 to fail fast if auth/net is broken.
        local cmd="ssh -A ${SSH_OPTS} -p \"${SOURCE_REMOTE_PORT}\" \"${SOURCE_REMOTE_USER}@${SOURCE_REMOTE_HOST}\" \
            \"rsync ${RSYNC_OPTS} ${rsync_excludes_str} \
            -e 'ssh ${SSH_OPTS} -o BatchMode=yes -o ConnectTimeout=10 -p ${DEST_REMOTE_PORT}' \
            \\\"${SOURCE_REMOTE_DIR}/${source_path}\\\" \
            \\\"${DEST_REMOTE_USER}@${DEST_REMOTE_HOST}:${DEST_REMOTE_DIR}/$(dirname "${dest_path}")/\\\"\""

        # Execute the command (RSYNC_OPTS handles safety for existing files, but we blocked mkdir above)
        # If dry-run, this will safely list files.
        # printf "DEBUG: Executing remote command: %s\n" "${cmd}"
        eval "${cmd}"
    elif [[ "${direction}" == "download" ]]; then
        printf "⌛ \033[1;32mDownloading from %s:%s to %s ...\033[0m\n" "${ENV_SOURCE_HOST}" "${source_path}" "${dest_path}"
        warden env exec -T php-fpm rsync ${RSYNC_OPTS} -e "ssh ${SSH_OPTS} -p ${ENV_SOURCE_PORT}" \
            "${exclude_args[@]}" \
            "${ENV_SOURCE_USER}@${ENV_SOURCE_HOST}:${ENV_SOURCE_DIR}/${source_path}" \
            "$(dirname "${dest_path}")/"
    else
        printf "⌛ \033[1;32mUploading from %s to %s:%s ...\033[0m\n" "${source_path}" "${ENV_SOURCE_HOST}" "${dest_path}"
        warden env exec -T php-fpm rsync ${RSYNC_OPTS} -e "ssh ${SSH_OPTS} -p ${ENV_SOURCE_PORT}" \
            "${exclude_args[@]}" \
            "${source_path}" "${ENV_SOURCE_USER}@${ENV_SOURCE_HOST}:${ENV_SOURCE_DIR}/$(dirname "${dest_path}")/"
    fi
}

# Function for database sync (streaming)
function sync_database() {
    set -o pipefail
    
    if [[ "${SYNC_DRY_RUN}" -eq 1 ]]; then
        printf "\033[33m[Dry Run] Database sync would stream from source ...\033[0m\n"
        return 0
    fi

    # Logic for remote-to-remote DB sync
    if [[ "${SYNC_REMOTE_TO_REMOTE:-0}" -eq 1 ]]; then
        printf "⌛ \033[1;32mSyncing DB from %s to %s ...\033[0m\n" "${SYNC_SOURCE}" "${SYNC_DESTINATION}"
        
        # Source DB info via base64 JSON
        local src_db_info=$(ssh ${SSH_OPTS} -o IdentityAgent=none -p "${SOURCE_REMOTE_PORT}" "${SOURCE_REMOTE_USER}@${SOURCE_REMOTE_HOST}" "php -r \"\\\$a=@include \\\"${SOURCE_REMOTE_DIR}/app/etc/env.php\\\"; echo base64_encode(json_encode(\\\$a['db']['connection']['default']));\"" 2>/dev/null)
        
        if [[ -z "${src_db_info}" ]]; then
            printf "\033[31mError: Failed to retrieve source database credentials from %s.\033[0m\n" "${SOURCE_REMOTE_HOST}" >&2
            return 1
        fi

        local src_db_host=$(php -r "\$a = json_decode(base64_decode(\$argv[1]), true); echo strpos(\$a['host'] ?? 'db', ':') === false ? (\$a['host'] ?? 'db') : explode(':', \$a['host'])[0];" -- "${src_db_info}")
        local src_db_port=$(php -r "\$a = json_decode(base64_decode(\$argv[1]), true); echo strpos(\$a['host'] ?? '', ':') === false ? '3306' : explode(':', \$a['host'])[1];" -- "${src_db_info}")
        local src_db_user=$(php -r "\$a = json_decode(base64_decode(\$argv[1]), true); echo \$a['username'] ?? '';" -- "${src_db_info}")
        local src_db_pass=$(php -r "\$a = json_decode(base64_decode(\$argv[1]), true); echo \$a['password'] ?? '';" -- "${src_db_info}")
        local src_db_name=$(php -r "\$a = json_decode(base64_decode(\$argv[1]), true); echo \$a['dbname'] ?? '';" -- "${src_db_info}")

        # Destination DB info via base64 JSON
        local dest_db_info=$(ssh ${SSH_OPTS} -o IdentityAgent=none -p "${DEST_REMOTE_PORT}" "${DEST_REMOTE_USER}@${DEST_REMOTE_HOST}" "php -r \"\\\$a=@include \\\"${DEST_REMOTE_DIR}/app/etc/env.php\\\"; echo base64_encode(json_encode(\\\$a['db']['connection']['default']));\"" 2>/dev/null)
        
        if [[ -z "${dest_db_info}" ]]; then
            printf "\033[31mError: Failed to retrieve destination database credentials from %s.\033[0m\n" "${DEST_REMOTE_HOST}" >&2
            return 1
        fi

        local dest_db_host=$(php -r "\$a = json_decode(base64_decode(\$argv[1]), true); echo strpos(\$a['host'] ?? 'db', ':') === false ? (\$a['host'] ?? 'db') : explode(':', \$a['host'])[0];" -- "${dest_db_info}")
        local dest_db_port=$(php -r "\$a = json_decode(base64_decode(\$argv[1]), true); echo strpos(\$a['host'] ?? '', ':') === false ? '3306' : explode(':', \$a['host'])[1];" -- "${dest_db_info}")
        local dest_db_user=$(php -r "\$a = json_decode(base64_decode(\$argv[1]), true); echo \$a['username'] ?? '';" -- "${dest_db_info}")
        local dest_db_pass=$(php -r "\$a = json_decode(base64_decode(\$argv[1]), true); echo \$a['password'] ?? '';" -- "${dest_db_info}")
        local dest_db_name=$(php -r "\$a = json_decode(base64_decode(\$argv[1]), true); echo \$a['dbname'] ?? '';" -- "${dest_db_info}")

        # Centralized SQL cleanup filters
        local SED_FILTERS=(
            -e '/999999.*sandbox/d'
            -e 's/DEFINER=[^*]*\*/\*/g'
            -e 's/ROW_FORMAT=FIXED//g'
            -e 's/utf8mb4_0900_ai_ci/utf8mb4_general_ci/g'
            -e 's/utf8mb4_unicode_520_ci/utf8mb4_general_ci/g'
            -e 's/utf8_unicode_520_ci/utf8_general_ci/g'
        )

        local tmp_dump=$(mktemp)
        printf "Extracting database from %s to %s ...\n" "${SYNC_SOURCE}" "${tmp_dump}"
        if ! ssh ${SSH_OPTS} -o IdentityAgent=none -p "${SOURCE_REMOTE_PORT}" "${SOURCE_REMOTE_USER}@${SOURCE_REMOTE_HOST}" \
            "export MYSQL_PWD='${src_db_pass}'; mysqldump --single-transaction --no-tablespaces --routines -h${src_db_host} -P${src_db_port} -u${src_db_user} ${src_db_name}" \
            | sed "${SED_FILTERS[@]}" > "${tmp_dump}"; then
            printf "\033[31mError: Failed to extract database from %s.\033[0m\n" "${SYNC_SOURCE}" >&2
            rm -f "${tmp_dump}"
            return 1
        fi

        local dump_size=$(stat -c%s "${tmp_dump}")
        if [[ ${dump_size} -lt 100 ]]; then
            printf "\033[31mError: Extracted database dump is suspicious small (%s bytes). Check remote database.\033[0m\n" "${dump_size}" >&2
            rm -f "${tmp_dump}"
            return 1
        fi

        printf "Importing database to %s ...\n" "${SYNC_DESTINATION}"
        if ! ssh ${SSH_OPTS} -o IdentityAgent=none -p "${DEST_REMOTE_PORT}" "${DEST_REMOTE_USER}@${DEST_REMOTE_HOST}" \
            "export MYSQL_PWD='${dest_db_pass}'; mysql -h${dest_db_host} -P${dest_db_port} -u${dest_db_user} ${dest_db_name}" < "${tmp_dump}"; then
            printf "\033[31mError: Failed to import database to %s.\033[0m\n" "${SYNC_DESTINATION}" >&2
            rm -f "${tmp_dump}"
            return 1
        fi

        rm -f "${tmp_dump}"
        return 0
    fi

    if [[ "${DIRECTION}" == "upload" ]]; then
        printf "\033[31mError: Database upload is not supported via streaming yet. Use warden db-dump and manual import instead for safety.\033[0m\n"
        return
    fi

    # Logic borrowed from db-import.cmd
    # Get remote DB credentials from env.php via base64 encoded JSON for maximum reliability
    local db_info=$(ssh ${SSH_OPTS} -o IdentityAgent=none -p "${ENV_SOURCE_PORT}" "${ENV_SOURCE_USER}@${ENV_SOURCE_HOST}" "php -r \"\\\$a=@include \\\"${ENV_SOURCE_DIR}/app/etc/env.php\\\"; echo base64_encode(json_encode(\\\$a['db']['connection']['default']));\"" 2>/dev/null)
    
    if [[ -z "${db_info}" ]]; then
        printf "\033[31mError: Failed to retrieve database credentials from %s. Check SSH connectivity and app/etc/env.php.\033[0m\n" "${ENV_SOURCE_HOST}" >&2
        return 1
    fi

    local db_host=$(warden env exec -T php-fpm php -r "\$a = json_decode(base64_decode(\$argv[1]), true); echo strpos(\$a['host'] ?? 'db', ':') === false ? (\$a['host'] ?? 'db') : explode(':', \$a['host'])[0];" -- "${db_info}")
    local db_port=$(warden env exec -T php-fpm php -r "\$a = json_decode(base64_decode(\$argv[1]), true); echo strpos(\$a['host'] ?? '', ':') === false ? '3306' : explode(':', \$a['host'])[1];" -- "${db_info}")
    local db_user=$(warden env exec -T php-fpm php -r "\$a = json_decode(base64_decode(\$argv[1]), true); echo \$a['username'] ?? '';" -- "${db_info}")
    local db_pass=$(warden env exec -T php-fpm php -r "\$a = json_decode(base64_decode(\$argv[1]), true); echo \$a['password'] ?? '';" -- "${db_info}")
    local db_name=$(warden env exec -T php-fpm php -r "\$a = json_decode(base64_decode(\$argv[1]), true); echo \$a['dbname'] ?? '';" -- "${db_info}")
    
    if [[ -z "${db_user}" || -z "${db_name}" ]]; then
        printf "\033[31mError: Incomplete database credentials retrieved from %s.\033[0m\n" "${ENV_SOURCE_HOST}" >&2
        return 1
    fi
    
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
    local dump_cmd="export MYSQL_PWD='${db_pass}'; mysqldump --single-transaction --no-tablespaces --routines -h${db_host} -P${db_port} -u${db_user} ${db_name}"
    
    local tmp_dump=$(mktemp)
    
    if ! ssh ${SSH_OPTS} -o IdentityAgent=none -p "${ENV_SOURCE_PORT}" "${ENV_SOURCE_USER}@${ENV_SOURCE_HOST}" "${dump_cmd}" | sed "${SED_FILTERS[@]}" > "${tmp_dump}"; then
        printf "\033[31mError: Failed to extract database from %s.\033[0m\n" "${ENV_SOURCE_HOST}" >&2
        rm -f "${tmp_dump}"
        return 1
    fi
    
    local dump_size=$(stat -c%s "${tmp_dump}")
    if [[ ${dump_size} -lt 100 ]]; then
        printf "\033[31mError: Extracted database dump is suspicious small (%s bytes). Check remote database.\033[0m\n" "${dump_size}" >&2
        rm -f "${tmp_dump}"
        return 1
    fi
    
    if ! warden db import --force < "${tmp_dump}"; then
        printf "\033[31mError: Failed to import database locally.\033[0m\n" >&2
        rm -f "${tmp_dump}"
        return 1
    fi
    
    rm -f "${tmp_dump}"
    return 0
}

# 1. Sync Files/Code
if [[ -z "${SYNC_PATH}" ]] && [[ "${SYNC_TYPE_FILE}" -eq 1 || "${SYNC_TYPE_FULL}" -eq 1 ]]; then
    if ! transfer_files "${DIRECTION}" "./" "./" "${CODE_EXCLUDE[@]}"; then exit 1; fi
fi

# 2. Sync Media
if [[ -z "${SYNC_PATH}" ]] && [[ "${SYNC_TYPE_MEDIA}" -eq 1 || "${SYNC_TYPE_FULL}" -eq 1 ]]; then
    if ! transfer_files "${DIRECTION}" "${MEDIA_PATH}" "${MEDIA_PATH}" "${MEDIA_EXCLUDE[@]}"; then exit 1; fi
fi

# 3. Sync Custom Path
if [[ -n "${SYNC_PATH}" ]]; then
    if ! transfer_files "${DIRECTION}" "${SYNC_PATH}" "${SYNC_PATH}"; then exit 1; fi
fi

# 4. Sync Database
if [[ "${SYNC_TYPE_DB}" -eq 1 || "${SYNC_TYPE_FULL}" -eq 1 ]]; then
    if ! sync_database; then exit 1; fi
fi

# 5. Post-Sync Redeploy
if [[ "${SYNC_DRY_RUN:-0}" -eq 0 ]]; then
    if [[ "${SYNC_REDEPLOY:-0}" -eq 1 ]]; then
        printf "🚀 \033[1;32mTriggering redeploy on %s ...\033[0m\n" "${SYNC_DESTINATION}"
        if ! warden deploy -e "${SYNC_DESTINATION}"; then exit 1; fi
    fi
fi

printf "✅ \033[32mSync operation complete!\033[0m\n"
