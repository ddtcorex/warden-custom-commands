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

# Define paths and exclusions
MEDIA_PATH="storage/app/public/"
CODE_EXCLUDE=('vendor' 'node_modules' 'storage/logs/*' 'storage/framework/cache/*' 'storage/framework/sessions/*' 'storage/framework/views/*' '.git' '.idea' '*.gz' '*.zip' '*.tar' '*.7z' '*.sql')

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
        printf "⌛ \033[1;32mSyncing from %s to %s (piped tar) ...\033[0m\n" "${SYNC_SOURCE}" "${SYNC_DESTINATION}"
        local tar_excludes=()
        for item in "${excludes[@]}"; do
            tar_excludes+=( --exclude="${item}" )
        done

        local cmd="${SSH_COMMAND} -p \"${SOURCE_REMOTE_PORT}\" \"${SOURCE_REMOTE_USER}@${SOURCE_REMOTE_HOST}\" \
            \"tar -C \\\"${SOURCE_REMOTE_DIR}/${source_path}\\\" -cf - . \\\"${tar_excludes[@]}\\\"\" \
            | ${SSH_COMMAND} -p \"${DEST_REMOTE_PORT}\" \"${DEST_REMOTE_USER}@${DEST_REMOTE_HOST}\" \
            \"tar -C \\\"${DEST_REMOTE_DIR}/${dest_path}\\\" -xf -\""

        if [[ "${SYNC_DRY_RUN}" -eq 1 ]]; then
            printf "\033[33m[Dry Run] Command: %s\033[0m\n" "${cmd}"
        else
            eval "${cmd}"
        fi
    elif [[ "${direction}" == "download" ]]; then
        printf "⌛ \033[1;32mDownloading from %s:%s to %s ...\033[0m\n" "${ENV_SOURCE_HOST}" "${source_path}" "${dest_path}"
        warden env exec php-fpm rsync ${RSYNC_OPTS} -e "${SSH_COMMAND} -p ${ENV_SOURCE_PORT}" \
            "${exclude_args[@]}" \
            "${ENV_SOURCE_USER}@${ENV_SOURCE_HOST}:${ENV_SOURCE_DIR}/${source_path}" "${dest_path}"
    else
        printf "⌛ \033[1;32mUploading from %s to %s:%s ...\033[0m\n" "${source_path}" "${ENV_SOURCE_HOST}" "${dest_path}"
        warden env exec php-fpm rsync ${RSYNC_OPTS} -e "${SSH_COMMAND} -p ${ENV_SOURCE_PORT}" \
            "${exclude_args[@]}" \
            "${source_path}" "${ENV_SOURCE_USER}@${ENV_SOURCE_HOST}:${ENV_SOURCE_DIR}/${dest_path}"
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
        local src_db_info=$(${SSH_COMMAND} -p "${SOURCE_REMOTE_PORT}" "${SOURCE_REMOTE_USER}@${SOURCE_REMOTE_HOST}" "grep -E '^DB_(HOST|PORT|DATABASE|USERNAME|PASSWORD)=' \"${SOURCE_REMOTE_DIR}/.env\"")
        local src_db_host=$(printf "%s" "${src_db_info}" | grep DB_HOST | cut -d= -f2 | tr -d '"'"'")
        local src_db_port=$(printf "%s" "${src_db_info}" | grep DB_PORT | cut -d= -f2 | tr -d '"'"'")
        local src_db_name=$(printf "%s" "${src_db_info}" | grep DB_DATABASE | cut -d= -f2 | tr -d '"'"'")
        local src_db_user=$(printf "%s" "${src_db_info}" | grep DB_USERNAME | cut -d= -f2 | tr -d '"'"'")
        local src_db_pass=$(printf "%s" "${src_db_info}" | grep DB_PASSWORD | cut -d= -f2 | tr -d '"'"'")
        src_db_host=${src_db_host:-127.0.0.1}
        src_db_port=${src_db_port:-3306}

        # Destination DB info
        local dest_db_info=$(${SSH_COMMAND} -p "${DEST_REMOTE_PORT}" "${DEST_REMOTE_USER}@${DEST_REMOTE_HOST}" "grep -E '^DB_(HOST|PORT|DATABASE|USERNAME|PASSWORD)=' \"${DEST_REMOTE_DIR}/.env\"")
        local dest_db_host=$(printf "%s" "${dest_db_info}" | grep DB_HOST | cut -d= -f2 | tr -d '"'"'")
        local dest_db_port=$(printf "%s" "${dest_db_info}" | grep DB_PORT | cut -d= -f2 | tr -d '"'"'")
        local dest_db_name=$(printf "%s" "${dest_db_info}" | grep DB_DATABASE | cut -d= -f2 | tr -d '"'"'")
        local dest_db_user=$(printf "%s" "${dest_db_info}" | grep DB_USERNAME | cut -d= -f2 | tr -d '"'"'")
        local dest_db_pass=$(printf "%s" "${dest_db_info}" | grep DB_PASSWORD | cut -d= -f2 | tr -d '"'"'")
        dest_db_host=${dest_db_host:-127.0.0.1}
        dest_db_port=${dest_db_port:-3306}

        printf "Streaming mysqldump from %s to %s ...\n" "${SYNC_SOURCE}" "${SYNC_DESTINATION}"
        ${SSH_COMMAND} -p "${SOURCE_REMOTE_PORT}" "${SOURCE_REMOTE_USER}@${SOURCE_REMOTE_HOST}" \
            "export MYSQL_PWD='${src_db_pass}'; mysqldump --single-transaction --no-tablespaces --routines -h${src_db_host} -P${src_db_port} -u${src_db_user} ${src_db_name}" \
            | sed "${SED_FILTERS[@]}" \
            | ${SSH_COMMAND} -p "${DEST_REMOTE_PORT}" "${DEST_REMOTE_USER}@${DEST_REMOTE_HOST}" \
            "export MYSQL_PWD='${dest_db_pass}'; mysql -h${dest_db_host} -P${dest_db_port} -u${dest_db_user} ${dest_db_name}"
        return
    fi

    if [[ "${DIRECTION}" == "upload" ]]; then
        printf "\033[31mError: Database upload is not supported via streaming yet.\033[0m\n"
        return
    fi

    # Fetch DB creds via SSH
    local db_info=$(${SSH_COMMAND} -p "${ENV_SOURCE_PORT}" "${ENV_SOURCE_USER}@${ENV_SOURCE_HOST}" "grep -E '^DB_(HOST|PORT|DATABASE|USERNAME|PASSWORD)=' \"${ENV_SOURCE_DIR}/.env\"")
    local db_host=$(printf "%s" "${db_info}" | grep DB_HOST | cut -d= -f2 | tr -d '"'"'")
    local db_port=$(printf "%s" "${db_info}" | grep DB_PORT | cut -d= -f2 | tr -d '"'"'")
    local db_name=$(printf "%s" "${db_info}" | grep DB_DATABASE | cut -d= -f2 | tr -d '"'"'")
    local db_user=$(printf "%s" "${db_info}" | grep DB_USERNAME | cut -d= -f2 | tr -d '"'"'")
    local db_pass=$(printf "%s" "${db_info}" | grep DB_PASSWORD | cut -d= -f2 | tr -d '"'"'")

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
    printf "🧹 \033[1;32mClearing Cache ...\033[0m\n"
    if [[ "${SYNC_REMOTE_TO_REMOTE:-0}" -eq 1 ]]; then
        ${SSH_COMMAND} -p "${DEST_REMOTE_PORT}" "${DEST_REMOTE_USER}@${DEST_REMOTE_HOST}" "cd \"${DEST_REMOTE_DIR}\" && warden env exec -T php-fpm php artisan cache:clear" || true
    else
        warden env exec -T php-fpm php artisan cache:clear || true
    fi
fi

printf "✅ \033[32mSync operation complete!\033[0m\n"
