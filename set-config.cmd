#!/usr/bin/env bash
[[ ! ${WARDEN_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

SUBCOMMAND_DIR=$(dirname "${BASH_SOURCE[0]}")
source "${SUBCOMMAND_DIR}"/env-variables

# Load environment-specific set-config command
ENV_SET_CONFIG="${SUBCOMMAND_DIR}/env-adapters/${WARDEN_ENV_TYPE}/set-config.cmd"

if [[ -f "${ENV_SET_CONFIG}" ]]; then
    source "${ENV_SET_CONFIG}"
else
    echo "Error: No set-config command found for environment type '${WARDEN_ENV_TYPE}'"
    echo "Expected: ${ENV_SET_CONFIG}"
    exit 1
fi
