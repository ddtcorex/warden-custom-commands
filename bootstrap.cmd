#!/usr/bin/env bash
[[ ! ${WARDEN_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

SUBCOMMAND_DIR=$(dirname "${BASH_SOURCE[0]}")

# Parse arguments for bootstrap wrapper
INIT_ENV_NAME=""
INIT_ENV_TYPE=""
declare -a ARGS_REST

while (( "$#" )); do
    case "$1" in
        --env-name=*)
            INIT_ENV_NAME="${1#*=}"
            shift
            ;;
        --env-type=*)
            INIT_ENV_TYPE="${1#*=}"
            shift
            ;;
        *)
            ARGS_REST+=("$1")
            shift
            ;;
    esac
done

# Reset positional parameters to the filtered list for downstream scripts
set -- "${ARGS_REST[@]}"

# Track if we created .env (to trigger fix-deps)
FIX_DEPS_FLAG=""

# For bootstrap, if .env doesn't exist, run env-init first
if [[ ! -f .env ]]; then
    echo "No .env found. Running env-init..."
    
    # Run env-init
    HOST_ARGS=()
    if [[ -n "${INIT_ENV_NAME}" ]]; then
        HOST_ARGS+=("${INIT_ENV_NAME}")
        if [[ -n "${INIT_ENV_TYPE}" ]]; then
            HOST_ARGS+=("${INIT_ENV_TYPE}")
        fi
    fi
    
    warden env-init "${HOST_ARGS[@]}"
    
    if [[ ! -f .env ]]; then
        fatal "Failed to initialize environment"
    fi
    
    # Set flag to automatically fix dependencies since we just created .env
    FIX_DEPS_FLAG="--fix-deps"
fi

# Now source env-variables (after ensuring .env exists)
source "${SUBCOMMAND_DIR}/env-variables"

# Dispatch to environment-specific bootstrap with fix-deps flag if needed
if [[ -f "${SUBCOMMAND_DIR}/env-adapters/${WARDEN_ENV_TYPE}/bootstrap.cmd" ]]; then
    source "${SUBCOMMAND_DIR}/env-adapters/${WARDEN_ENV_TYPE}/bootstrap.cmd" ${FIX_DEPS_FLAG} "$@"
else
    fatal "Bootstrap is not supported for environment type '${WARDEN_ENV_TYPE}'"
fi
