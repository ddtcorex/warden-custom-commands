#!/usr/bin/env bash
# Strict mode inherited from env-variables

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
MEDIA_PATH="pub/media"
CODE_EXCLUDE=('/generated' '/var' '/pub/media' '/pub/static' '*.gz' '*.zip' '*.tar' '*.7z' '*.sql' '.git' '.idea' 'node_modules')
MEDIA_EXCLUDE=('*.gz' '*.zip' '*.tar' '*.7z' '*.sql' 'tmp' 'itm' 'import' 'export' 'importexport' 'captcha' 'analytics' 'catalog/product.rm' 'catalog/product/product' 'opti_image' 'webp_image' 'webp_cache' 'shoppingfeed' 'amasty/blog/cache')
# Exclude product images by default unless --include-product is passed
if [[ "${SYNC_INCLUDE_PRODUCT:-0}" -eq 0 ]]; then
    MEDIA_EXCLUDE+=('catalog/product')
else
    # Even if we include product images, we always want to exclude the cache
    MEDIA_EXCLUDE+=('catalog/product/cache')
fi

SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
source "${SCRIPT_DIR}/utils.sh"

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
        if warden remote-exec -e "${SYNC_DESTINATION}" -- bash -c "[ -e \"${DEST_REMOTE_DIR}/${target_file}\" ]" ; then
            exists_on_dest=1
        fi
    elif [[ "${direction}" == "download" ]]; then
        if [[ -e "${WARDEN_ENV_PATH}/${target_file}" ]]; then
            exists_on_dest=1
        fi
    else
        # upload
        if warden remote-exec -e "${ENV_SOURCE}" -- bash -c "[ -e \"${ENV_SOURCE_DIR}/${target_file}\" ]" ; then
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
        # Skip this in dry-run mode or if it's just a check
        if [[ "${SYNC_DRY_RUN:-0}" -ne 1 ]]; then
            warden remote-exec -e "${SYNC_DESTINATION}" -- bash -c "mkdir -p \"${DEST_REMOTE_DIR}/$(dirname "${dest_path}")\""
        fi

        # 2. Run Rsync on Source (Source -> Dest) using Agent Forwarding (via SSH_OPTS)
        # In dry-run mode, RSYNC_OPTS contains --dry-run, so we SHOULD execute it to see the file list.
        # Added BatchMode=yes and ConnectTimeout=10 to fail fast if auth/net is broken.
        warden remote-exec -e "${SYNC_SOURCE}" -- bash -c \
            "rsync ${RSYNC_OPTS} ${rsync_excludes_str} \
            -e 'ssh ${SSH_OPTS} -o BatchMode=yes -o ConnectTimeout=10 -p ${DEST_REMOTE_PORT}' \
            \"${SOURCE_REMOTE_DIR}/${source_path}\" \
            \"${DEST_REMOTE_USER}@${DEST_REMOTE_HOST}:${DEST_REMOTE_DIR}/$(dirname "${dest_path}")/\""
    elif [[ "${direction}" == "download" ]]; then
        printf "⌛ \033[1;32mDownloading from %s:%s to %s ...\033[0m\n" "${ENV_SOURCE_HOST}" "${source_path}" "${dest_path}"
        rsync ${RSYNC_OPTS} -e "ssh ${SSH_OPTS} -p ${ENV_SOURCE_PORT}" \
            "${exclude_args[@]}" \
            "${ENV_SOURCE_USER}@${ENV_SOURCE_HOST}:${ENV_SOURCE_DIR}/${source_path}" \
            "$(dirname "${dest_path}")/"
    else
        printf "⌛ \033[1;32mUploading from %s to %s:%s ...\033[0m\n" "${source_path}" "${ENV_SOURCE_HOST}" "${dest_path}"
        rsync ${RSYNC_OPTS} -e "ssh ${SSH_OPTS} -p ${ENV_SOURCE_PORT}" \
            "${exclude_args[@]}" \
            "${source_path}" "${ENV_SOURCE_USER}@${ENV_SOURCE_HOST}:${ENV_SOURCE_DIR}/$(dirname "${dest_path}")/"
    fi
}

# Function for database sync
function sync_database() {
    local PV="pv"
    if ! command -v pv &>/dev/null; then
        PV="cat"
    fi
    set -o pipefail
    
    if [[ "${SYNC_DRY_RUN}" -eq 1 ]]; then
        printf "\033[33m[Dry Run] Database sync would stream from source ...\033[0m\n"
        return 0
    fi

    local SED_FILTERS=(
        -e '/999999.*sandbox/d'
        -e 's/DEFINER=[^*]*\*/\*/g'
        -e 's/ROW_FORMAT=FIXED//g'
        -e 's/utf8mb4_0900_ai_ci/utf8mb4_general_ci/g'
        -e 's/utf8mb4_unicode_520_ci/utf8mb4_general_ci/g'
        -e 's/utf8_unicode_520_ci/utf8_general_ci/g'
    )

    # Logic for remote-to-remote DB sync
    if [[ "${SYNC_REMOTE_TO_REMOTE:-0}" -eq 1 ]]; then
        printf "⌛ \033[1;32mSyncing DB from %s to %s ...\033[0m\n" "${SYNC_SOURCE}" "${SYNC_DESTINATION}"
        
        # Source DB info
        local src_db_info=$(get_remote_db_info "${SOURCE_REMOTE_DIR}" "${SYNC_SOURCE}")
        if [[ $? -ne 0 ]]; then
            printf "\033[31mError: Failed to retrieve source database credentials from %s.\033[0m\n" "${SOURCE_REMOTE_HOST}" >&2
            return 1
        fi

        local src_db_host=$(echo "${src_db_info}" | grep "^DB_HOST=" | cut -d= -f2-)
        local src_db_port=$(echo "${src_db_info}" | grep "^DB_PORT=" | cut -d= -f2-)
        local src_db_user=$(echo "${src_db_info}" | grep "^DB_USERNAME=" | cut -d= -f2-)
        local src_db_pass=$(echo "${src_db_info}" | grep "^DB_PASSWORD=" | cut -d= -f2-)
        local src_db_name=$(echo "${src_db_info}" | grep "^DB_DATABASE=" | cut -d= -f2-)

        # Destination DB info
        local dest_db_info=$(get_remote_db_info "${DEST_REMOTE_DIR}" "${SYNC_DESTINATION}")
        if [[ $? -ne 0 ]]; then
            printf "\033[31mError: Failed to retrieve destination database credentials from %s.\033[0m\n" "${DEST_REMOTE_HOST}" >&2
            return 1
        fi

        local dest_db_host=$(printf "%s" "${dest_db_info}" | grep "^DB_HOST=" | tail -n 1 | cut -d= -f2-)
        local dest_db_port=$(printf "%s" "${dest_db_info}" | grep "^DB_PORT=" | tail -n 1 | cut -d= -f2-)
        local dest_db_user=$(printf "%s" "${dest_db_info}" | grep "^DB_USERNAME=" | tail -n 1 | cut -d= -f2-)
        local dest_db_pass=$(printf "%s" "${dest_db_info}" | grep "^DB_PASSWORD=" | tail -n 1 | cut -d= -f2-)
        local dest_db_name=$(printf "%s" "${dest_db_info}" | grep "^DB_DATABASE=" | tail -n 1 | cut -d= -f2-)

        # Backup Destination DB (Remote) using standard db-dump
        if [[ "${SYNC_BACKUP}" -eq 1 ]]; then
             if ! warden db-dump -e "${SYNC_DESTINATION}"; then
                 return 1
             fi
        fi

        # Use standard db-dump to create a gzipped, filtered file
        local local_tmp_file="var/${WARDEN_ENV_NAME}_${SYNC_SOURCE}-to-local-$(date +%Y%m%dT%H%M%S).sql.gz"
        printf "  Streaming sync: %s -> %s (through local)...\n" "${SYNC_SOURCE}" "${SYNC_DESTINATION}"
        
        local dump_cmd="export MYSQL_PWD='${src_db_pass}'; { \$(command -v mariadb-dump || echo mysqldump) --force --single-transaction --no-tablespaces --no-data --routines -h${src_db_host} -P${src_db_port} -u${src_db_user} ${src_db_name} 2>/dev/null; \$(command -v mariadb-dump || echo mysqldump) --force --single-transaction --no-tablespaces --skip-triggers --no-create-info -h${src_db_host} -P${src_db_port} -u${src_db_user} ${src_db_name} 2>/dev/null; } | gzip"
        local import_cmd="export MYSQL_PWD='${dest_db_pass}'; { echo \"SET FOREIGN_KEY_CHECKS=0; SET UNIQUE_CHECKS=0; SET SQL_MODE='NO_AUTO_VALUE_ON_ZERO';\"; gunzip -c; } | \$(command -v mariadb || echo mysql) -h${dest_db_host} -P${dest_db_port} -u${dest_db_user} ${dest_db_name} -f"
        local pv_cmd="cat"
        if [[ "${PV}" == "pv" ]]; then pv_cmd="pv -N Syncing"; fi

        # 1. Reset destination database
        printf "  Resetting destination database ...\n"
        if ! warden remote-exec -e "${SYNC_DESTINATION}" -- bash -c "export MYSQL_PWD='${dest_db_pass}'; \$(command -v mariadb || echo mysql) -h${dest_db_host} -P${dest_db_port} -u${dest_db_user} -e 'DROP DATABASE IF EXISTS \`${dest_db_name}\`; CREATE DATABASE \`${dest_db_name}\`;'"; then
            printf "\033[31mError: Failed to reset destination database.\033[0m\n" >&2
            return 1
        fi

        # 2. Stream dump from source to destination
        if ! warden remote-exec -e "${SYNC_SOURCE}" -- bash -c "${dump_cmd}" \
            | sed "${SED_FILTERS[@]}" \
            | ${pv_cmd} \
            | warden remote-exec -e "${SYNC_DESTINATION}" -- bash -c "${import_cmd}"; then
            printf "\033[31mError: Remote-to-Remote sync failed.\033[0m\n" >&2
            return 1
        fi
        
        return 0
    fi

    if [[ "${DIRECTION}" == "upload" ]]; then
        printf "⌛ \033[1;32mSyncing DB from local to %s ...\033[0m\n" "${SYNC_DESTINATION}"

        # 1. Get Remote (Destination) DB Credentials
        local dest_db_info=$(get_remote_db_info "${ENV_SOURCE_DIR}")
        if [[ $? -ne 0 ]]; then
            printf "\033[31mError: Failed to retrieve database credentials from %s.\033[0m\n" "${ENV_SOURCE_HOST}" >&2
            return 1
        fi

        local dest_db_host=$(printf "%s" "${dest_db_info}" | grep "^DB_HOST=" | tail -n 1 | cut -d= -f2-)
        local dest_db_port=$(printf "%s" "${dest_db_info}" | grep "^DB_PORT=" | tail -n 1 | cut -d= -f2-)
        local dest_db_user=$(printf "%s" "${dest_db_info}" | grep "^DB_USERNAME=" | tail -n 1 | cut -d= -f2-)
        local dest_db_pass=$(printf "%s" "${dest_db_info}" | grep "^DB_PASSWORD=" | tail -n 1 | cut -d= -f2-)
        local dest_db_name=$(printf "%s" "${dest_db_info}" | grep "^DB_DATABASE=" | tail -n 1 | cut -d= -f2-)

        # Backup Destination DB (Remote) using standard db-dump
        if [[ "${SYNC_BACKUP}" -eq 1 ]]; then
             if ! warden db-dump -e "${SYNC_DESTINATION}"; then
                 return 1
             fi
        fi

        # Use host-side warden db-dump to avoid container DNS issues
        local local_dump="var/${WARDEN_ENV_NAME}_local-to-${SYNC_DESTINATION}-$(date +%Y%m%dT%H%M%S).sql.gz"
        mkdir -p var
        
        printf "  Dumping local database to %s ...\n" "${local_dump}"
        warden db-dump -s local -f "${local_dump}"

        if [[ ! -f "${local_dump}" ]]; then
            printf "\033[31mError: Local database dump failed.\033[0m\n" >&2
            return 1
        fi

        # 1. Drop and Recreate Database on Remote
        printf "  Resetting remote database ...\n"
        if ! warden remote-exec -e "${ENV_SOURCE}" -- bash -c "export MYSQL_PWD='${dest_db_pass}'; \$(command -v mariadb || echo mysql) -h${dest_db_host} -P${dest_db_port} -u${dest_db_user} -e 'DROP DATABASE IF EXISTS \`${dest_db_name}\`; CREATE DATABASE \`${dest_db_name}\`;'"; then
            printf "\033[31mError: Failed to reset remote database.\033[0m\n" >&2
            rm -f "${local_dump}"
            return 1
        fi

        # 2. Import Dump
        local import_cmd="export MYSQL_PWD='${dest_db_pass}'; { echo \"SET FOREIGN_KEY_CHECKS=0; SET UNIQUE_CHECKS=0; SET SQL_MODE='NO_AUTO_VALUE_ON_ZERO';\"; gunzip -c; } | \$(command -v mariadb || echo mysql) -h${dest_db_host} -P${dest_db_port} -u${dest_db_user} ${dest_db_name} -f"
        
        local pv_cmd="cat"
        if [[ "${PV}" == "pv" ]]; then pv_cmd="pv -N Importing"; fi

        printf "  Importing to remote ...\n"
        if ! cat "${local_dump}" | ${pv_cmd} | warden remote-exec -e "${ENV_SOURCE}" -- bash -c "${import_cmd}"; then
            printf "\033[31mError: Database upload/import failed.\033[0m\n" >&2
            rm -f "${local_dump}"
            return 1
        fi

        rm -f "${local_dump}"
        return 0
    fi

    # Download logic
    if [[ "${SYNC_BACKUP}" -eq 1 ]]; then
        # Let db-dump handle the filename and location (defaults to var/ locally)
        if ! warden db-dump -e local; then
             printf "\033[31mError: Local database backup failed.\033[0m\n" >&2
             return 1
        fi
    fi

    local db_info=$(get_remote_db_info "${ENV_SOURCE_DIR}")
    if [[ $? -ne 0 ]]; then
        printf "\033[31mError: Failed to retrieve database credentials from %s.\033[0m\n" "${ENV_SOURCE_HOST}" >&2
        return 1
    fi

    local db_host=$(echo "${db_info}" | grep "^DB_HOST=" | cut -d= -f2-)
    local db_port=$(echo "${db_info}" | grep "^DB_PORT=" | cut -d= -f2-)
    local db_user=$(echo "${db_info}" | grep "^DB_USERNAME=" | cut -d= -f2-)
    local db_pass=$(echo "${db_info}" | grep "^DB_PASSWORD=" | cut -d= -f2-)
    local db_name=$(echo "${db_info}" | grep "^DB_DATABASE=" | cut -d= -f2-)
    
    if [[ -z "${db_user}" || -z "${db_name}" ]]; then
        printf "\033[31mError: Incomplete database credentials retrieved from %s.\033[0m\n" "${ENV_SOURCE_HOST}" >&2
        return 1
    fi

    local sed_filters="sed -e '/999999.*enable the sandbox mode/d' -e 's/DEFINER=[^*]*\\*/\\*/g' -e 's/ROW_FORMAT=FIXED//g'"
    local dump_cmd="export MYSQL_PWD='${db_pass}'; { \$(command -v mariadb-dump || echo mysqldump) --force --single-transaction --no-tablespaces --no-data --routines -h${db_host} -P${db_port} -u${db_user} ${db_name} 2>/dev/null | ${sed_filters}; \$(command -v mariadb-dump || echo mysqldump) --force --single-transaction --no-tablespaces --skip-triggers --no-create-info -h${db_host} -P${db_port} -u${db_user} ${db_name} 2>/dev/null | ${sed_filters}; } | gzip"

    PV=$(command -v pv || echo cat)
    printf "Streaming gzipped mysqldump from %s:%s ...\n" "${ENV_SOURCE_HOST}" "${db_name}"
    if ! warden remote-exec -e "${ENV_SOURCE}" -- bash -c "${dump_cmd}" \
        | ${PV} -N "Downloading" \
        | zcat | warden env exec -T db bash -c 'export MYSQL_PWD="$MYSQL_PASSWORD"; { echo "SET FOREIGN_KEY_CHECKS=0; SET UNIQUE_CHECKS=0; SET SQL_MODE='\''NO_AUTO_VALUE_ON_ZERO'\'';"; cat; } | $(command -v mariadb || echo mysql) -hdb -u"$MYSQL_USER" "$MYSQL_DATABASE" -f'; then
        printf "\033[31mError: Database sync failed during streaming.\033[0m\n" >&2
        return 1
    fi
    
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
