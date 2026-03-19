#!/usr/bin/env bash
[[ ! "${WARDEN_DIR:-}" ]] && >&2 printf "\033[31mThis script is not intended to be run directly!\033[0m\n" && exit 1

SUBCOMMAND_DIR=$(dirname "${BASH_SOURCE[0]}")
source "${SUBCOMMAND_DIR}"/env-variables

# Default values
STREAM_DB=0
SYNC_DB_NO_NOISE=0
SYNC_DB_NO_PII=0

# Parse remaining arguments
while (( "$#" )); do
    case "$1" in
        --stream-db)
            STREAM_DB=1
            shift
            ;;
        --no-noise)
            SYNC_DB_NO_NOISE=1
            shift
            ;;
        --no-pii)
            SYNC_DB_NO_PII=1
            shift
            ;;
        --) # End of all options
            shift
            WARDEN_PARAMS+=("$@")
            break
            ;;
        *)
            WARDEN_PARAMS+=("$1")
            shift
            ;;
    esac
done

export STREAM_DB SYNC_DB_NO_NOISE SYNC_DB_NO_PII

# Load environment-specific db-import command
ENV_DB_IMPORT="${SUBCOMMAND_DIR}/env-adapters/${WARDEN_ENV_TYPE}/db-import.cmd"

if [[ -f "${ENV_DB_IMPORT}" ]]; then
    source "${ENV_DB_IMPORT}"
else
    >&2 printf "Error: No db-import command found for environment type '%s'\n" "${WARDEN_ENV_TYPE}"
    >&2 printf "Expected: %s\n" "${ENV_DB_IMPORT}"
    exit 1
fi
