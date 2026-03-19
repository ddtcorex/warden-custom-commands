#!/usr/bin/env bash
set -euo pipefail

[[ ! "${WARDEN_DIR:-}" ]] && >&2 printf "\033[31mNot intended to run directly!\033[0m\n" && exit 1

# Note: Standard SYNC_* variables are already parsed and exported by the root env-sync.cmd
# DIRECTION, SYNC_SOURCE, SYNC_DESTINATION, SYNC_TYPE_FILE, SYNC_TYPE_MEDIA, SYNC_TYPE_DB, SYNC_TYPE_FULL, etc.

# Determine RSYNC options
RSYNC_OPTS="-azvPLk --force --timeout=60"
if [[ "${SYNC_DRY_RUN:-0}" -eq 1 ]]; then
    RSYNC_OPTS="${RSYNC_OPTS} --dry-run"
fi
if [[ "${SYNC_DELETE:-0}" -eq 1 ]]; then
    RSYNC_OPTS="${RSYNC_OPTS} --delete"
fi

# Define paths and exclusions for M1
MEDIA_PATH="media"
CODE_EXCLUDE=('/var' '/media' '/includes/src' '*.gz' '*.zip' '*.tar' '*.7z' '*.sql' '.git' '.idea' 'node_modules' '/catalog')
MEDIA_EXCLUDE=('*.gz' '*.zip' '*.tar' '*.7z' '*.sql' 'tmp' 'itm' 'import' 'export' 'importexport' 'captcha' 'analytics' 'opti_image' 'webp_image' 'webp_cache')

# Exclude product images by default unless --include-product is passed
if [[ "${SYNC_INCLUDE_PRODUCT:-0}" -eq 0 ]]; then
    MEDIA_EXCLUDE+=('catalog/product')
else
    # Exclude the cache even if including products
    MEDIA_EXCLUDE+=('catalog/product/cache')
fi

_ADAPTER_DIR=$(dirname "${BASH_SOURCE[0]}")
source "${_ADAPTER_DIR}/utils.sh"
source "${SUBCOMMAND_DIR}/lib/error-handling.sh"

# Function for file transfer (uses rsync)
function transfer_files() {
    local direction="${1}"
    local source_path="${2%/}"
    local dest_path="${3%/}"
    local excludes=("${@:4}")

    # Path-aware local.xml exclusion
    local target_file="app/etc/local.xml"
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
        local norm_target="/${target_file}"
        local norm_src=$(echo "/${source_path}" | sed -e 's|/\./|/|g' -e 's|/\.$|/|' -e 's|/\{2,\}|/|g')
        
        if [[ "${norm_src}" == */ ]]; then
            local src_dir="${norm_src%/}"
            [[ "${norm_target}" == "${src_dir}"/* ]] && rel_exclude="${norm_target#$src_dir}"
        else
            local src_parent=$(dirname "${norm_src}")
            [[ "${src_parent}" == "/" ]] && src_parent=""
            [[ "${norm_target}" == "${src_parent}"/* ]] && rel_exclude="${norm_target#$src_parent}"
        fi
    fi

    [[ -n "${rel_exclude}" ]] && excludes+=( "${rel_exclude}" )
    
    local exclude_args=()
    for item in "${excludes[@]}"; do
        exclude_args+=( --exclude="${item}" )
    done

    if [[ "${direction}" == "download" ]]; then
        printf "⌛ \033[1;32mDownloading from %s:%s to %s ...\033[0m\n" "${ENV_SOURCE_HOST}" "${source_path}" "${dest_path}"
        rsync ${RSYNC_OPTS} -e "ssh ${SSH_OPTS:-} -p ${ENV_SOURCE_PORT}" \
            "${exclude_args[@]}" \
            "${ENV_SOURCE_USER}@${ENV_SOURCE_HOST}:${ENV_SOURCE_DIR}/${source_path}" \
            "$(dirname "${dest_path}")/"
    fi
}

# Function for database sync
function sync_database() {
    if [[ "${SYNC_DRY_RUN:-0}" -eq 1 ]]; then
        printf "\033[33m[Dry Run] Database sync would stream from source ...\033[0m\n"
        return 0
    fi

    # Backup local DB
    if [[ "${SYNC_BACKUP:-1}" -eq 1 ]]; then
        warden db-dump -e local || warning "Local database backup failed, continuing anyway..."
    fi

    # Download sync is now offloaded to db-import --stream-db which handles everything robustly
    if [[ "${DIRECTION:-download}" == "download" ]]; then
        local import_flags=""
        [[ "${SYNC_DB_NO_NOISE:-0}" -eq 1 ]] && import_flags="${import_flags} --no-noise"
        [[ "${SYNC_DB_NO_PII:-0}" -eq 1 ]] && import_flags="${import_flags} --no-pii"

        if ! warden db-import --stream-db ${import_flags}; then
            error "Database sync failed."
            return 1
        fi
    else
        error "Upload/Remote-to-Remote database sync is not yet implemented for M1."
        return 1
    fi
    
    return 0
}

# 1. Sync Files/Code
if [[ -z "${SYNC_PATH:-}" ]] && [[ "${SYNC_TYPE_FILE:-0}" -eq 1 || "${SYNC_TYPE_FULL:-0}" -eq 1 ]]; then
    transfer_files "${DIRECTION:-download}" "./" "./" "${CODE_EXCLUDE[@]}"
fi

# 2. Sync Media
if [[ -z "${SYNC_PATH:-}" ]] && [[ "${SYNC_TYPE_MEDIA:-0}" -eq 1 || "${SYNC_TYPE_FULL:-0}" -eq 1 ]]; then
    transfer_files "${DIRECTION:-download}" "${MEDIA_PATH}" "${MEDIA_PATH}" "${MEDIA_EXCLUDE[@]}"
fi

# 3. Sync Custom Path
if [[ -n "${SYNC_PATH:-}" ]]; then
    transfer_files "${DIRECTION:-download}" "${SYNC_PATH}" "${SYNC_PATH}"
fi

# 4. Sync Database
if [[ "${SYNC_TYPE_DB:-0}" -eq 1 || "${SYNC_TYPE_FULL:-0}" -eq 1 ]]; then
    sync_database
fi

printf "✅ \033[32mSync operation complete!\033[0m\n"
