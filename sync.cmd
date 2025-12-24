#!/usr/bin/env bash
set -u
[[ ! "${WARDEN_DIR:-}" ]] && >&2 printf "\033[31mThis script is not intended to be run directly!\033[0m\n" && exit 1

SUBCOMMAND_DIR=$(dirname "${BASH_SOURCE[0]}")
source "${SUBCOMMAND_DIR}"/env-variables

# Default values - use centralized ENV_SOURCE and ENV_DESTINATION from env-variables
SYNC_SOURCE="${ENV_SOURCE:-staging}"
SYNC_DESTINATION="${ENV_DESTINATION:-local}"
SYNC_TYPE_FILE=0
SYNC_TYPE_MEDIA=0
SYNC_TYPE_DB=0
SYNC_TYPE_FULL=0
SYNC_PATH=""
SYNC_DRY_RUN=0
SYNC_DELETE=0
SYNC_REMOTE_TO_REMOTE=0
SYNC_INCLUDE_PRODUCT=0
SYNC_REDEPLOY=0

# Parse remaining arguments (source/destination already handled by env-variables)
while (( "$#" )); do
    case "$1" in
        -f|--file)
            SYNC_TYPE_FILE=1
            shift
            ;;
        -f=*|--file=*)
            if [[ "${1#*=}" =~ ^(true|1)$ ]]; then SYNC_TYPE_FILE=1; fi
            shift
            ;;
        -m|--media)
            SYNC_TYPE_MEDIA=1
            shift
            ;;
        -m=*|--media=*)
            if [[ "${1#*=}" =~ ^(true|1)$ ]]; then SYNC_TYPE_MEDIA=1; fi
            shift
            ;;
        --db)
            SYNC_TYPE_DB=1
            shift
            ;;
        --db=*)
            if [[ "${1#*=}" =~ ^(true|1)$ ]]; then SYNC_TYPE_DB=1; fi
            shift
            ;;
        --full)
            SYNC_TYPE_FULL=1
            shift
            ;;
        --full=*)
            if [[ "${1#*=}" =~ ^(true|1)$ ]]; then SYNC_TYPE_FULL=1; fi
            shift
            ;;
        -p=*|--path=*)
            SYNC_PATH="${1#*=}"
            shift
            ;;
        -p|--path)
            SYNC_PATH="$2"
            shift 2
            ;;
        --dry-run)
            SYNC_DRY_RUN=1
            shift
            ;;
        --delete)
            SYNC_DELETE=1
            shift
            ;;
        --include-product)
            SYNC_INCLUDE_PRODUCT=1
            shift
            ;;
        --redeploy)
            SYNC_REDEPLOY=1
            shift
            ;;
        --) # End of all options
            shift
            WARDEN_PARAMS+=("$@")
            break
            ;;
        -*)
            printf "Error: Unknown option %s\n" "$1" >&2
            exit 1
            ;;
        *)
            WARDEN_PARAMS+=("$1")
            shift
            ;;
    esac
done

# Remove all trailing slashes from path to ensure consistent behavior
while [[ "${SYNC_PATH}" == */ ]]; do SYNC_PATH="${SYNC_PATH%/}"; done

# If no type is specified, default to file
if [[ "${SYNC_TYPE_FILE}" -eq 0 && "${SYNC_TYPE_MEDIA}" -eq 0 && "${SYNC_TYPE_DB}" -eq 0 && "${SYNC_TYPE_FULL}" -eq 0 ]]; then
    SYNC_TYPE_FILE=1
fi

# Set direction and remote environment logic
if [[ "${SYNC_DESTINATION}" != "local" && "${SYNC_SOURCE}" != "local" ]]; then
    SYNC_REMOTE_TO_REMOTE=1
    DIRECTION="remote-to-remote"
    
    # Load Source details
    SOURCE_DETAILS=$(get_remote_details "${SYNC_SOURCE}")
    if [[ -z "${SOURCE_DETAILS}" ]]; then
        printf "\033[31mError: Source environment details not found for '%s'.\033[0m\n" "${SYNC_SOURCE}" >&2
        exit 1
    fi
    export SOURCE_REMOTE_HOST=$(printf "%s" "${SOURCE_DETAILS}" | cut -d'|' -f1)
    export SOURCE_REMOTE_USER=$(printf "%s" "${SOURCE_DETAILS}" | cut -d'|' -f2)
    export SOURCE_REMOTE_PORT=$(printf "%s" "${SOURCE_DETAILS}" | cut -d'|' -f3)
    export SOURCE_REMOTE_DIR=$(printf "%s" "${SOURCE_DETAILS}" | cut -d'|' -f4)

    # Load Destination details
    DEST_DETAILS=$(get_remote_details "${SYNC_DESTINATION}")
    if [[ -z "${DEST_DETAILS}" ]]; then
        printf "\033[31mError: Destination environment details not found for '%s'.\033[0m\n" "${SYNC_DESTINATION}" >&2
        exit 1
    fi
    export DEST_REMOTE_HOST=$(printf "%s" "${DEST_DETAILS}" | cut -d'|' -f1)
    export DEST_REMOTE_USER=$(printf "%s" "${DEST_DETAILS}" | cut -d'|' -f2)
    export DEST_REMOTE_PORT=$(printf "%s" "${DEST_DETAILS}" | cut -d'|' -f3)
    export DEST_REMOTE_DIR=$(printf "%s" "${DEST_DETAILS}" | cut -d'|' -f4)

    REMOTE_ENV="${SYNC_DESTINATION}" # Used for Warden's global context (destination is usually where we flush cache)
elif [[ "${SYNC_DESTINATION}" != "local" ]]; then
    REMOTE_ENV="${SYNC_DESTINATION}"
    DIRECTION="upload"
else
    REMOTE_ENV="${SYNC_SOURCE}"
    DIRECTION="download"
fi

if [[ "${SYNC_SOURCE}" == "${SYNC_DESTINATION}" ]]; then
    printf "\033[31mError: Source and destination environments cannot be the same (%s).\033[0m\n" "${SYNC_SOURCE}" >&2
    exit 1
fi

# Re-source env-variables with the primary remote environment (usually destination or source)
export ENV_SOURCE="${REMOTE_ENV}"
source "${SUBCOMMAND_DIR}"/env-variables

# Build sync description for better messaging
SYNC_DESC=""
if [[ -n "${SYNC_PATH}" ]]; then
    SYNC_DESC="Path: ${SYNC_PATH}"
elif [[ "${SYNC_TYPE_FULL}" -eq 1 ]]; then
    SYNC_DESC="FULL (Files + Media + DB)"
else
    [[ "${SYNC_TYPE_FILE}" -eq 1 ]] && SYNC_DESC="${SYNC_DESC}Files "
    [[ "${SYNC_TYPE_MEDIA}" -eq 1 ]] && SYNC_DESC="${SYNC_DESC}Media "
    [[ "${SYNC_TYPE_DB}" -eq 1 ]] && SYNC_DESC="${SYNC_DESC}Database "
fi
SYNC_DESC=$(printf "%s" "${SYNC_DESC}" | xargs) # trim trailing space
[[ "${SYNC_DELETE}" -eq 1 ]] && SYNC_DESC="${SYNC_DESC} (with delete)"
[[ "${SYNC_DRY_RUN}" -eq 1 ]] && SYNC_DESC="${SYNC_DESC} [DRY RUN]"

# Confirmation prompt
if [[ "${SYNC_REMOTE_TO_REMOTE}" -eq 1 ]]; then
    printf "\033[33mCAUTION: You are about to sync \033[1;35m%s\033[0m\033[33m from REMOTE (\033[1;36m%s\033[0m\033[33m) to REMOTE (\033[1;31m%s\033[0m\033[33m).\033[0m\n" "${SYNC_DESC}" "${SYNC_SOURCE}" "${SYNC_DESTINATION}"
    printf "Are you sure you want to continue? [y/N] "
    read -n 1 -r REPLY_CHOICE
    printf "\n"
    if [[ ! "${REPLY_CHOICE}" =~ ^[Yy]$ ]]; then
        printf "Operation cancelled.\n"
        exit 1
    fi
elif [[ "${SYNC_DESTINATION}" != "local" ]]; then
    printf "\033[33mCAUTION: You are about to sync \033[1;35m%s\033[0m\033[33m TO a remote environment (\033[1;31m%s\033[0m\033[33m).\033[0m\n" "${SYNC_DESC}" "${SYNC_DESTINATION}"
    printf "Are you sure you want to continue? [y/N] "
    read -n 1 -r REPLY_CHOICE
    printf "\n"
    if [[ ! "${REPLY_CHOICE}" =~ ^[Yy]$ ]]; then
        printf "Operation cancelled.\n"
        exit 1
    fi
else
    # Simple notice for downloads to local
    printf "\033[33mSyncing \033[1;35m%s\033[0m\033[33m from \033[1;36m%s\033[0m to \033[1;32mlocal\033[0m.\033[0m\n" "${SYNC_DESC}" "${SYNC_SOURCE}"
fi

# Export variables for adapter scripts
export SYNC_SOURCE SYNC_DESTINATION SYNC_TYPE_FILE SYNC_TYPE_MEDIA SYNC_TYPE_DB SYNC_TYPE_FULL SYNC_PATH SYNC_DRY_RUN SYNC_DELETE SYNC_REMOTE_TO_REMOTE SYNC_INCLUDE_PRODUCT SYNC_REDEPLOY DIRECTION

# Dispatch to environment-specific implementation
ENV_CMD="${SUBCOMMAND_DIR}/env-adapters/${WARDEN_ENV_TYPE}/sync.cmd"
if [[ -f "${ENV_CMD}" ]]; then
    source "${ENV_CMD}"
else
    printf "\033[31mCommand 'sync' is not supported for environment type '%s'\033[0m\n" "${WARDEN_ENV_TYPE}" >&2
    exit 1
fi
