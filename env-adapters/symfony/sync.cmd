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
MEDIA_PATH="public/uploads"
CODE_EXCLUDE=('vendor' 'node_modules' 'var/cache/*' 'var/log/*' '.git' '.idea' '*.gz' '*.zip' '*.tar' '*.7z' '*.sql' '.env' '.env.local')

SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
source "${SCRIPT_DIR}/utils.sh"

# Function for file transfer (uses rsync)
function transfer_files() {
    local direction="${1}"
    local source_path="${2%/}"
    local dest_path="${3%/}"
    local excludes=("${@:4}")

    # Path-aware .env exclusion (only if it exists on destination)
    local target_file=".env.local"
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
    local PV="pv"
    if ! command -v pv &>/dev/null; then
        PV="cat"
    fi
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
        
        # Source DB info
        local src_db_info=$(get_remote_db_info "${SOURCE_REMOTE_HOST}" "${SOURCE_REMOTE_PORT}" "${SOURCE_REMOTE_USER}" "${SOURCE_REMOTE_DIR}")
        
        local src_db_host=$(printf "%s" "${src_db_info}" | grep "^DB_HOST=" | tail -n 1 | cut -d= -f2-)
        local src_db_port=$(printf "%s" "${src_db_info}" | grep "^DB_PORT=" | tail -n 1 | cut -d= -f2-)
        local src_db_user=$(printf "%s" "${src_db_info}" | grep "^DB_USERNAME=" | tail -n 1 | cut -d= -f2-)
        local src_db_pass=$(printf "%s" "${src_db_info}" | grep "^DB_PASSWORD=" | tail -n 1 | cut -d= -f2-)
        local src_db_name=$(printf "%s" "${src_db_info}" | grep "^DB_DATABASE=" | tail -n 1 | cut -d= -f2-)

        # Destination DB info
        local dest_db_info=$(get_remote_db_info "${DEST_REMOTE_HOST}" "${DEST_REMOTE_PORT}" "${DEST_REMOTE_USER}" "${DEST_REMOTE_DIR}")
        
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

        printf "  Streaming sync: %s -> %s (through local)...\n" "${SYNC_SOURCE}" "${SYNC_DESTINATION}"
        
        local dump_cmd="export MYSQL_PWD='${src_db_pass}'; \$(command -v mariadb-dump || echo mysqldump) --single-transaction --no-tablespaces --routines -h${src_db_host} -P${src_db_port} -u${src_db_user} ${src_db_name}"
        local import_cmd="export MYSQL_PWD='${dest_db_pass}'; { echo \"SET FOREIGN_KEY_CHECKS=0; SET UNIQUE_CHECKS=0;\"; cat; } | \$(command -v mariadb || echo mysql) -h${dest_db_host} -P${dest_db_port} -u${dest_db_user} ${dest_db_name} -f"

        local pv_cmd="cat"
        if [[ "${PV}" == "pv" ]]; then pv_cmd="pv -N Syncing"; fi

        # 1. Reset destination database
        printf "  Resetting destination database ...\n"
        if ! ssh ${SSH_OPTS} -p "${DEST_REMOTE_PORT}" "${DEST_REMOTE_USER}@${DEST_REMOTE_HOST}" "export MYSQL_PWD='${dest_db_pass}'; \$(command -v mariadb || echo mysql) -h${dest_db_host} -P${dest_db_port} -u${dest_db_user} -e 'DROP DATABASE IF EXISTS \`${dest_db_name}\`; CREATE DATABASE \`${dest_db_name}\`;'"; then
            printf "\033[31mError: Failed to reset destination database.\033[0m\n" >&2
            return 1
        fi

        # 2. Stream dump from source to destination
        if ! ssh ${SSH_OPTS} -p "${SOURCE_REMOTE_PORT}" "${SOURCE_REMOTE_USER}@${SOURCE_REMOTE_HOST}" "${dump_cmd}" \
            | sed "${SED_FILTERS[@]}" \
            | ${pv_cmd} \
            | ssh ${SSH_OPTS} -p "${DEST_REMOTE_PORT}" "${DEST_REMOTE_USER}@${DEST_REMOTE_HOST}" "${import_cmd}"; then
            printf "\033[31mError: Remote-to-Remote sync failed.\033[0m\n" >&2
            return 1
        fi
        
        return 0
    fi

    if [[ "${DIRECTION}" == "upload" ]]; then
        printf "⌛ \033[1;32mSyncing DB from local to %s ...\033[0m\n" "${SYNC_DESTINATION}"

        # 1. Get Destination (Remote) DB Credentials
        local dest_db_info=$(get_remote_db_info "${ENV_SOURCE_HOST}" "${ENV_SOURCE_PORT}" "${ENV_SOURCE_USER}" "${ENV_SOURCE_DIR}")
        
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

        # 2. Get Local (Source) DB Credentials
        local src_db_user=$(warden env exec -T db printenv MYSQL_USER)
        local src_db_pass=$(warden env exec -T db printenv MYSQL_PASSWORD)
        local src_db_name=$(warden env exec -T db printenv MYSQL_DATABASE)
        
        src_db_user=${src_db_user:-symfony}
        src_db_pass=${src_db_pass:-symfony}
        src_db_name=${src_db_name:-symfony}
        local src_db_host="db"
        local src_db_port=3306

        printf "Streaming mysqldump from local to %s ...\n" "${SYNC_DESTINATION}"

        DUMP_BIN="mysqldump"
        if [[ "${MYSQL_DISTRIBUTION:-}" == *"mariadb"* ]]; then
            DUMP_BIN="mariadb-dump"
        fi

        local mysql_import_cmd="{ echo \"SET FOREIGN_KEY_CHECKS=0; SET UNIQUE_CHECKS=0; SET AUTOCOMMIT=0;\"; cat; echo \"COMMIT; SET FOREIGN_KEY_CHECKS=1; SET UNIQUE_CHECKS=1; SET AUTOCOMMIT=1;\"; } | \$(command -v mariadb || echo mysql) -h${dest_db_host} -P${dest_db_port} -u${dest_db_user} ${dest_db_name} -f"

        # 1. Reset destination database
        printf "  Resetting remote database ...\n"
        if ! ssh ${SSH_OPTS} -p "${ENV_SOURCE_PORT}" "${ENV_SOURCE_USER}@${ENV_SOURCE_HOST}" "export MYSQL_PWD='${dest_db_pass}'; \$(command -v mariadb || echo mysql) -h${dest_db_host} -P${dest_db_port} -u${dest_db_user} -e 'DROP DATABASE IF EXISTS \`${dest_db_name}\`; CREATE DATABASE \`${dest_db_name}\`;'"; then
            printf "\033[31mError: Failed to reset remote database.\033[0m\n" >&2
            return 1
        fi

        # 2. Stream import
        if ! warden env exec -T db bash -c "export MYSQL_PWD='${src_db_pass}'; ${DUMP_BIN} --single-transaction --no-tablespaces --routines -h${src_db_host} -P${src_db_port} -u${src_db_user} ${src_db_name}" \
            | sed "${SED_FILTERS[@]}" \
            | ssh ${SSH_OPTS} -p "${ENV_SOURCE_PORT}" "${ENV_SOURCE_USER}@${ENV_SOURCE_HOST}" \
            "export MYSQL_PWD='${dest_db_pass}'; ${mysql_import_cmd}"; then
            
            printf "\033[31mError: Database upload from local failed.\033[0m\n" >&2
            return 1
        fi

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

    # Fetch DB creds via SSH
    local db_info=$(get_remote_db_info "${ENV_SOURCE_HOST}" "${ENV_SOURCE_PORT}" "${ENV_SOURCE_USER}" "${ENV_SOURCE_DIR}")
    
    local db_host=$(echo "${db_info}" | grep "^DB_HOST=" | cut -d= -f2-)
    local db_port=$(echo "${db_info}" | grep "^DB_PORT=" | cut -d= -f2-)
    local db_user=$(echo "${db_info}" | grep "^DB_USERNAME=" | cut -d= -f2-)
    local db_pass=$(echo "${db_info}" | grep "^DB_PASSWORD=" | cut -d= -f2-)
    local db_name=$(echo "${db_info}" | grep "^DB_DATABASE=" | cut -d= -f2-)
    
    printf "Streaming gzipped mysqldump from %s:%s ...\n" "${ENV_SOURCE_HOST}" "${db_name}"
    
    local pv_cmd="cat"
    if [[ "${PV}" == "pv" ]]; then pv_cmd="pv -N Downloading"; fi

    if ! ssh ${SSH_OPTS} -p "${ENV_SOURCE_PORT}" "${ENV_SOURCE_USER}@${ENV_SOURCE_HOST}" \
        "export MYSQL_PWD='${db_pass}'; \$(command -v mariadb-dump || echo mysqldump) --single-transaction --no-tablespaces --routines -h${db_host} -P${db_port} -u${db_user} ${db_name} | gzip" \
        | ${pv_cmd} \
        | zcat \
        | sed "${SED_FILTERS[@]}" \
        | warden env exec -T db bash -c 'export MYSQL_PWD="$MYSQL_PASSWORD"; { echo "SET FOREIGN_KEY_CHECKS=0; SET UNIQUE_CHECKS=0;"; cat; } | $(command -v mariadb || echo mysql) -hdb -u"$MYSQL_USER" "$MYSQL_DATABASE" -f'; then
        printf "\033[31mError: Database download to local failed.\033[0m\n" >&2
        return 1
    fi
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
    transfer_files "${DIRECTION}" "${SYNC_PATH}" "${SYNC_PATH}" "${CODE_EXCLUDE[@]}"
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
            ssh ${SSH_OPTS} -p "${DEST_REMOTE_PORT}" "${DEST_REMOTE_USER}@${DEST_REMOTE_HOST}" "cd \"${DEST_REMOTE_DIR}\" && if [ -f bin/console ]; then php bin/console cache:clear; fi" || true
        else
            warden env exec -T php-fpm bash -c "[[ -f bin/console ]] && bin/console cache:clear || true"
        fi
    fi
fi

printf "✅ \033[32mSync operation complete!\033[0m\n"
