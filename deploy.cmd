#!/usr/bin/env bash
[[ ! "${WARDEN_DIR:-}" ]] && >&2 printf "\033[31mThis script is not intended to be run directly!\033[0m\n" && exit 1

SUBCOMMAND_DIR=$(dirname "${BASH_SOURCE[0]}")
source "${SUBCOMMAND_DIR}"/env-variables

# Default values for deployer strategy
DEPLOY_STRATEGY="native"
DEPLOYER_CONFIG=""

# Parse deployer-related arguments (before passing to adapter)
REMAINING_ARGS=()
while (( "$#" )); do
    case "$1" in
        --deployer)
            DEPLOY_STRATEGY="deployer"
            shift
            ;;
        --strategy=*)
            DEPLOY_STRATEGY="${1#*=}"
            shift
            ;;
        --strategy)
            DEPLOY_STRATEGY="$2"
            shift 2
            ;;
        --deployer-config=*)
            DEPLOYER_CONFIG="${1#*=}"
            shift
            ;;
        --deployer-config)
            DEPLOYER_CONFIG="$2"
            shift 2
            ;;
        *)
            REMAINING_ARGS+=("$1")
            shift
            ;;
    esac
done

# Restore remaining arguments for adapter scripts
set -- "${REMAINING_ARGS[@]+"${REMAINING_ARGS[@]}"}"

# Export for adapter scripts
export DEPLOY_STRATEGY DEPLOYER_CONFIG

# Load environment-specific deploy command
ENV_CMD="${SUBCOMMAND_DIR}/env-adapters/${WARDEN_ENV_TYPE}/deploy.cmd"

if [[ -f "${ENV_CMD}" ]]; then
    source "${ENV_CMD}"
else
    >&2 printf "Error: No deploy command found for environment type '%s'\n" "${WARDEN_ENV_TYPE}"
    >&2 printf "Expected: %s\n" "${ENV_CMD}"
    exit 1
fi
