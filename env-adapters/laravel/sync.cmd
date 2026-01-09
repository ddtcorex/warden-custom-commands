#!/usr/bin/env bash
set -u

# Variable checks
if [ -z "${ENV_SOURCE_HOST_VAR+x}" ]; then
    printf "Invalid environment '%s'\n" "${ENV_SOURCE}" >&2
    exit 2
fi
# Ensure SSH_OPTS is set (fallback to WARDEN_SSH_OPTS)
SSH_OPTS=${SSH_OPTS:-${WARDEN_SSH_OPTS:-}}

# Determine RSYNC options
RSYNC_OPTS="-azvPLk --force"
if [[ "${SYNC_DRY_RUN:-0}" -eq 1 ]]; then
    RSYNC_OPTS="${RSYNC_OPTS} --dry-run"
fi
if [[ "${SYNC_DELETE:-0}" -eq 1 ]]; then
    RSYNC_OPTS="${RSYNC_OPTS} --delete"
fi

# Define paths and exclusions
MEDIA_PATH="storage/app/public"
CODE_EXCLUDE=('vendor' 'node_modules' 'storage/logs/*' 'storage/framework/cache/*' 'storage/framework/sessions/*' 'storage/framework/views/*' '.git' '.idea' '*.gz' '*.zip' '*.tar' '*.7z' '*.sql' '.env')

# Helper function to get remote DB credentials (supports .env and .env.php)
function get_remote_db_info() {
    local remote_host="$1"
    local remote_port="$2"
    local remote_user="$3"
    local remote_dir="$4"
    
    # Try .env first
    local db_info=$(ssh ${SSH_OPTS} -p "${remote_port}" "${remote_user}@${remote_host}" "grep -h -E '^(DB_HOST|DB_PORT|DB_DATABASE|DB_USERNAME|DB_PASSWORD)=' \"${remote_dir}/.env\"" 2>/dev/null)
    
    local db_name=$(printf "%s" "${db_info}" | grep "^DB_DATABASE=" | tail -n 1 | cut -d= -f2- | tr -d '"'"'")
    
    # Fallback to .env.php for Laravel 4+ legacy projects
    if [[ -z "${db_name}" ]]; then
        local php_code="\$f=\"${remote_dir}/.env.php\"; if(file_exists(\$f)) { \$c=include \$f; if(is_array(\$c)) { echo \"DB_HOST=\" . (\$c[\"DB_HOST\"]??\$c[\"DATABASE_HOST\"]??\"127.0.0.1\") . PHP_EOL; echo \"DB_PORT=\" . (\$c[\"DB_PORT\"]??\$c[\"DATABASE_PORT\"]??\"3306\") . PHP_EOL; echo \"DB_DATABASE=\" . (\$c[\"DB_DATABASE\"]??\$c[\"DATABASE_NAME\"]??\"\") . PHP_EOL; echo \"DB_USERNAME=\" . (\$c[\"DB_USERNAME\"]??\$c[\"DATABASE_USER\"]??\"\") . PHP_EOL; echo \"DB_PASSWORD=\" . (\$c[\"DB_PASSWORD\"]??\$c[\"DATABASE_PASSWORD\"]??\"\") . PHP_EOL; } }"
        
        db_info=$(ssh ${SSH_OPTS} -p "${remote_port}" "${remote_user}@${remote_host}" "php -r '${php_code}'")
    fi
    
    printf "%s" "${db_info}"
}

# Function for file transfer (uses rsync)
function transfer_files() {
    local direction="${1}"
    local source_path="${2%/}"
    local dest_path="${3%/}"
    local excludes=("${@:4}")

    # Path-aware .env exclusion (only if it exists on destination)
    local target_file=".env"
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
        
        # Ensure destination parent directory exists
        if [[ "${SYNC_DRY_RUN:-0}" -ne 1 ]]; then
             warden env exec php-fpm ssh ${SSH_OPTS} -p "${ENV_SOURCE_PORT}" "${ENV_SOURCE_USER}@${ENV_SOURCE_HOST}" "mkdir -p \"${ENV_SOURCE_DIR}/$(dirname "${dest_path}")\""
        fi

        warden env exec php-fpm rsync ${RSYNC_OPTS} -e "ssh ${SSH_OPTS} -p ${ENV_SOURCE_PORT}" \
            "${exclude_args[@]}" \
            "${source_path}" "${ENV_SOURCE_USER}@${ENV_SOURCE_HOST}:${ENV_SOURCE_DIR}/$(dirname "${dest_path}")/"
    fi
}

# Function for database sync (streaming)
function sync_database() {
    set -o pipefail
    
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

        # Source DB info (supports .env and .env.php)
        local src_db_info=$(get_remote_db_info "${SOURCE_REMOTE_HOST}" "${SOURCE_REMOTE_PORT}" "${SOURCE_REMOTE_USER}" "${SOURCE_REMOTE_DIR}")
        local src_db_host=$(printf "%s" "${src_db_info}" | grep "^DB_HOST=" | tail -n 1 | cut -d= -f2- | tr -d '"'"'")
        local src_db_port=$(printf "%s" "${src_db_info}" | grep "^DB_PORT=" | tail -n 1 | cut -d= -f2- | tr -d '"'"'")
        local src_db_name=$(printf "%s" "${src_db_info}" | grep "^DB_DATABASE=" | tail -n 1 | cut -d= -f2- | tr -d '"'"'")
        local src_db_user=$(printf "%s" "${src_db_info}" | grep "^DB_USERNAME=" | tail -n 1 | cut -d= -f2- | tr -d '"'"'")
        local src_db_pass=$(printf "%s" "${src_db_info}" | grep "^DB_PASSWORD=" | tail -n 1 | cut -d= -f2- | tr -d '"'"'")
        src_db_host=${src_db_host:-127.0.0.1}
        src_db_port=${src_db_port:-3306}

        # Destination DB info (supports .env and .env.php)
        local dest_db_info=$(get_remote_db_info "${DEST_REMOTE_HOST}" "${DEST_REMOTE_PORT}" "${DEST_REMOTE_USER}" "${DEST_REMOTE_DIR}")
        local dest_db_host=$(printf "%s" "${dest_db_info}" | grep "^DB_HOST=" | tail -n 1 | cut -d= -f2- | tr -d '"'"'")
        local dest_db_port=$(printf "%s" "${dest_db_info}" | grep "^DB_PORT=" | tail -n 1 | cut -d= -f2- | tr -d '"'"'")
        local dest_db_name=$(printf "%s" "${dest_db_info}" | grep "^DB_DATABASE=" | tail -n 1 | cut -d= -f2- | tr -d '"'"'")
        local dest_db_user=$(printf "%s" "${dest_db_info}" | grep "^DB_USERNAME=" | tail -n 1 | cut -d= -f2- | tr -d '"'"'")
        local dest_db_pass=$(printf "%s" "${dest_db_info}" | grep "^DB_PASSWORD=" | tail -n 1 | cut -d= -f2- | tr -d '"'"'")
        dest_db_host=${dest_db_host:-127.0.0.1}
        dest_db_port=${dest_db_port:-3306}

        printf "Streaming mysqldump from %s to %s ...\n" "${SYNC_SOURCE}" "${SYNC_DESTINATION}"
        if ! ssh ${SSH_OPTS} -p "${SOURCE_REMOTE_PORT}" "${SOURCE_REMOTE_USER}@${SOURCE_REMOTE_HOST}" \
            "export MYSQL_PWD='${src_db_pass}'; mysqldump --single-transaction --no-tablespaces --routines -h${src_db_host} -P${src_db_port} -u${src_db_user} ${src_db_name}" \
            | sed "${SED_FILTERS[@]}" \
            | ssh ${SSH_OPTS} -p "${DEST_REMOTE_PORT}" "${DEST_REMOTE_USER}@${DEST_REMOTE_HOST}" "cat > /tmp/warden_r2r_db.sql"; then
            printf "\033[31mError: Database dump transfer failed.\033[0m\n" >&2
            return 1
        fi
            
        ssh ${SSH_OPTS} -p "${DEST_REMOTE_PORT}" "${DEST_REMOTE_USER}@${DEST_REMOTE_HOST}" \
        "chmod 666 /tmp/warden_r2r_db.sql"
        
        printf "Importing database on %s ...\n" "${SYNC_DESTINATION}"
        ssh ${SSH_OPTS} -p "${DEST_REMOTE_PORT}" "${DEST_REMOTE_USER}@${DEST_REMOTE_HOST}" \
        "export MYSQL_PWD='${dest_db_pass}'; mysql -h${dest_db_host} -P${dest_db_port} -u${dest_db_user} ${dest_db_name} < /tmp/warden_r2r_db.sql"
        
        local import_status=$?

        ssh ${SSH_OPTS} -p "${DEST_REMOTE_PORT}" "${DEST_REMOTE_USER}@${DEST_REMOTE_HOST}" "rm -f /tmp/warden_r2r_db.sql"
        
        if [[ ${import_status} -ne 0 ]]; then
                printf "\033[31mError: Database import failed on destination.\033[0m\n" >&2
                return 1
        fi
        return 0
    fi

    if [[ "${DIRECTION}" == "upload" ]]; then
        printf "⌛ \033[1;32mSyncing DB from local to %s ...\033[0m\n" "${SYNC_DESTINATION}"

        # 1. Get Destination (Remote) DB Credentials (supports .env and .env.php)
        local dest_db_info=$(get_remote_db_info "${ENV_SOURCE_HOST}" "${ENV_SOURCE_PORT}" "${ENV_SOURCE_USER}" "${ENV_SOURCE_DIR}")
        local dest_db_host=$(printf "%s" "${dest_db_info}" | grep "^DB_HOST=" | tail -n 1 | cut -d= -f2- | tr -d '"'"'")
        local dest_db_port=$(printf "%s" "${dest_db_info}" | grep "^DB_PORT=" | tail -n 1 | cut -d= -f2- | tr -d '"'"'")
        local dest_db_name=$(printf "%s" "${dest_db_info}" | grep "^DB_DATABASE=" | tail -n 1 | cut -d= -f2- | tr -d '"'"'")
        local dest_db_user=$(printf "%s" "${dest_db_info}" | grep "^DB_USERNAME=" | tail -n 1 | cut -d= -f2- | tr -d '"'"'")
        local dest_db_pass=$(printf "%s" "${dest_db_info}" | grep "^DB_PASSWORD=" | tail -n 1 | cut -d= -f2- | tr -d '"'"'")
        
        dest_db_host=${dest_db_host:-127.0.0.1}
        dest_db_port=${dest_db_port:-3306}

        # 2. Get Local (Source) DB Credentials
        local src_db_user=$(warden env exec -T db printenv MYSQL_USER)
        local src_db_pass=$(warden env exec -T db printenv MYSQL_PASSWORD)
        local src_db_name=$(warden env exec -T db printenv MYSQL_DATABASE)
        
        src_db_user=${src_db_user:-laravel}
        src_db_pass=${src_db_pass:-laravel}
        src_db_name=${src_db_name:-laravel}
        local src_db_host="db"
        local src_db_port=3306

        printf "Streaming mysqldump from local to %s ...\n" "${SYNC_DESTINATION}"

        if ! warden env exec -T db bash -c "export MYSQL_PWD='${src_db_pass}'; mysqldump --single-transaction --no-tablespaces --routines -h${src_db_host} -P${src_db_port} -u${src_db_user} ${src_db_name}" \
            | sed "${SED_FILTERS[@]}" \
            | ssh ${SSH_OPTS} -p "${ENV_SOURCE_PORT}" "${ENV_SOURCE_USER}@${ENV_SOURCE_HOST}" \
            "export MYSQL_PWD='${dest_db_pass}'; mysql -h${dest_db_host} -P${dest_db_port} -u${dest_db_user} ${dest_db_name}"; then
            
            printf "\033[31mError: Database upload from local failed.\033[0m\n" >&2
            return 1
        fi

        return 0
    fi

    # Fetch DB creds via SSH (supports .env and .env.php)
    local db_info=$(get_remote_db_info "${ENV_SOURCE_HOST}" "${ENV_SOURCE_PORT}" "${ENV_SOURCE_USER}" "${ENV_SOURCE_DIR}")
    local db_host=$(printf "%s" "${db_info}" | grep "^DB_HOST=" | tail -n 1 | cut -d= -f2- | tr -d '"'"'")
    local db_port=$(printf "%s" "${db_info}" | grep "^DB_PORT=" | tail -n 1 | cut -d= -f2- | tr -d '"'"'")
    local db_name=$(printf "%s" "${db_info}" | grep "^DB_DATABASE=" | tail -n 1 | cut -d= -f2- | tr -d '"'"'")
    local db_user=$(printf "%s" "${db_info}" | grep "^DB_USERNAME=" | tail -n 1 | cut -d= -f2- | tr -d '"'"'")
    local db_pass=$(printf "%s" "${db_info}" | grep "^DB_PASSWORD=" | tail -n 1 | cut -d= -f2- | tr -d '"'"'")

    db_host=${db_host:-127.0.0.1}
    db_port=${db_port:-3306}
    
    printf "Streaming mysqldump from %s:%s ...\n" "${ENV_SOURCE_HOST}" "${db_name}"
    ssh ${SSH_OPTS} -p "${ENV_SOURCE_PORT}" "${ENV_SOURCE_USER}@${ENV_SOURCE_HOST}" \
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

# 5. Post-Sync Redeploy
if [[ "${SYNC_DRY_RUN:-0}" -eq 0 ]]; then
    if [[ "${SYNC_REDEPLOY:-0}" -eq 1 ]]; then
        printf "🚀 \033[1;32mTriggering redeploy on %s ...\033[0m\n" "${SYNC_DESTINATION}"
        if ! warden deploy -e "${SYNC_DESTINATION}"; then exit 1; fi
    else
        printf "🧹 \033[1;32mClearing Cache ...\033[0m\n"
        if [[ "${SYNC_REMOTE_TO_REMOTE:-0}" -eq 1 ]]; then
            ssh ${SSH_OPTS} -p "${DEST_REMOTE_PORT}" "${DEST_REMOTE_USER}@${DEST_REMOTE_HOST}" "cd \"${DEST_REMOTE_DIR}\" && php artisan cache:clear" || true
        else
            warden env exec -T php-fpm php artisan cache:clear || true
        fi
    fi
fi

printf "✅ \033[32mSync operation complete!\033[0m\n"
