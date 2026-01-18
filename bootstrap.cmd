#!/usr/bin/env bash
[[ ! "${WARDEN_DIR:-}" ]] && >&2 printf "\033[31mThis script is not intended to be run directly!\033[0m\n" && exit 1

SUBCOMMAND_DIR=$(dirname "${BASH_SOURCE[0]}")

# Source clone utilities for environment detection
source "${SUBCOMMAND_DIR}/lib/clone-utils.sh"

# Parse arguments for bootstrap wrapper
INIT_ENV_NAME=""
INIT_ENV_TYPE=""
CLONE_MODE=""
CLONE_SOURCE=""
declare -a ARGS_REST

while (( "$#" )); do
    case "$1" in
        # Clone mode (new)
        -c|--clone)
            CLONE_MODE=1
            shift
            ;;
        # Environment name/type for init
        --env-name=*)
            INIT_ENV_NAME="${1#*=}"
            shift
            ;;
        --env-name)
            INIT_ENV_NAME="$2"
            shift 2
            ;;
        --env-type=*)
            INIT_ENV_TYPE="${1#*=}"
            shift
            ;;
        --env-type)
            INIT_ENV_TYPE="$2"
            shift 2
            ;;
        # Capture source environment for clone auto-detection
        -e|-s|--source|--environment)
            CLONE_SOURCE="$2"
            ARGS_REST+=("$1" "$2")
            shift 2
            ;;
        -e=*|-s=*|--source=*|--environment=*)
            CLONE_SOURCE="${1#*=}"
            ARGS_REST+=("$1")
            shift
            ;;
        *)
            ARGS_REST+=("$1")
            shift
            ;;
    esac
done

# Default CLONE_SOURCE to 'staging' if not provided
if [[ -n "${CLONE_MODE}" ]] && [[ -z "${CLONE_SOURCE}" ]]; then
    CLONE_SOURCE="staging"
    ARGS_REST+=("--source=${CLONE_SOURCE}")
    printf "ℹ️  No source environment specified. Defaulting to '${CLONE_SOURCE}'.\n"
fi

# Reset positional parameters to the filtered list for downstream scripts
set -- "${ARGS_REST[@]}"

# Track if we created .env (to trigger fix-deps)
FIX_DEPS_FLAG=""

# For bootstrap, if .env doesn't exist, run env-init first
if [[ ! -f .env ]]; then
    printf "No .env found. Running env-init...\n"
    
    # If clone mode and source provided, try to auto-detect environment type
    if [[ -n "${CLONE_MODE}" ]] && [[ -n "${CLONE_SOURCE}" ]] && [[ -z "${INIT_ENV_TYPE}" ]]; then
        # If no .env, we need to configure the remote first to allow detection
        if [[ ! -f .env ]]; then
            REMOTE_CONFIG=$(configure_clone_source_remote "${CLONE_SOURCE}")
            if [[ -n "${REMOTE_CONFIG}" ]]; then
                # Create temporary .env for detection to work
                # We assume warden remote-exec loads .env from current dir
                echo "${REMOTE_CONFIG}" > .env
            fi
        fi
    
        printf "Attempting to detect environment type from remote '%s'...\n" "${CLONE_SOURCE}"
        
        # Try to detect (this may fail if no SSH config exists yet/anymore)
        DETECTED_TYPE=$(detect_env_type_from_remote "${CLONE_SOURCE}" 2>/dev/null) || DETECTED_TYPE=""
        
        if [[ -n "${DETECTED_TYPE}" ]]; then
            printf "\033[32mDetected environment type: %s\033[0m\n" "${DETECTED_TYPE}"
            INIT_ENV_TYPE="${DETECTED_TYPE}"
        else
            printf "\033[33mCould not auto-detect environment type.\033[0m\n"
            INIT_ENV_TYPE=$(prompt_env_type)
        fi
        
        # Remove temporary .env so env-init can run clean
        if [[ -n "${REMOTE_CONFIG}" ]] && [[ -f .env ]]; then
            rm .env
        fi
    fi
    
    # Run env-init
    HOST_ARGS=()
    if [[ -n "${INIT_ENV_NAME:-}" ]]; then
        HOST_ARGS+=("${INIT_ENV_NAME}")
    fi
    if [[ -n "${INIT_ENV_TYPE:-}" ]]; then
        # If only type provided without name, use directory name
        if [[ ${#HOST_ARGS[@]} -eq 0 ]]; then
            HOST_ARGS+=("$(get_project_name)")
        fi
        HOST_ARGS+=("${INIT_ENV_TYPE}")
    fi
    
    warden env-init "${HOST_ARGS[@]}"
    
    if [[ ! -f .env ]]; then
        >&2 printf "\033[31mFailed to initialize environment\033[0m\n"
        exit 1
    fi
    
    # Restore pre-configured remote if available
    if [[ -n "${REMOTE_CONFIG:-}" ]]; then
        echo "${REMOTE_CONFIG}" >> .env
    fi
    
    # Prompt for remote setup
    source "${SUBCOMMAND_DIR}/setup-remotes.cmd"
    
    # Set flag to automatically fix dependencies since we just created .env
    FIX_DEPS_FLAG="--fix-deps"
fi

# Now source env-variables (after ensuring .env exists)
source "${SUBCOMMAND_DIR}/env-variables"

# Build flags to pass to adapter
ADAPTER_FLAGS=""
[[ -n "${CLONE_MODE}" ]] && ADAPTER_FLAGS="${ADAPTER_FLAGS} --clone"
[[ -n "${FIX_DEPS_FLAG}" ]] && ADAPTER_FLAGS="${ADAPTER_FLAGS} ${FIX_DEPS_FLAG}"

# Dispatch to environment-specific bootstrap
if [[ -f "${SUBCOMMAND_DIR}/env-adapters/${WARDEN_ENV_TYPE}/bootstrap.cmd" ]]; then
    source "${SUBCOMMAND_DIR}/env-adapters/${WARDEN_ENV_TYPE}/bootstrap.cmd" ${ADAPTER_FLAGS} "$@"
else
    error "Bootstrap is not supported for environment type '${WARDEN_ENV_TYPE}'"
    exit 1
fi
