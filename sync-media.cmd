#!/usr/bin/env bash
[[ ! ${WARDEN_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

SUBCOMMAND_DIR=$(dirname "${BASH_SOURCE[0]}")
source "${SUBCOMMAND_DIR}"/env-variables

# Load environment-specific sync-media command
ENV_CMD="${SUBCOMMAND_DIR}/env-adapters/${WARDEN_ENV_TYPE}/sync-media.cmd"

if [[ -f "${ENV_CMD}" ]]; then
    source "${ENV_CMD}"
else
    echo "Error: No sync-media command found for environment type '${WARDEN_ENV_TYPE}'"
    echo "Expected: ${ENV_CMD}"
    exit 1
fi
