#!/usr/bin/env bash
[[ ! ${WARDEN_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

SUBCOMMAND_DIR=$(dirname "${BASH_SOURCE[0]}")
source "${SUBCOMMAND_DIR}"/env-variables

# Load environment-specific bootstrap command
ENV_BOOTSTRAP="${SUBCOMMAND_DIR}/env-adapters/${WARDEN_ENV_TYPE}/bootstrap.cmd"

if [[ -f "${ENV_BOOTSTRAP}" ]]; then
    source "${ENV_BOOTSTRAP}"
else
    echo "Error: No bootstrap command found for environment type '${WARDEN_ENV_TYPE}'"
    echo "Expected: ${ENV_BOOTSTRAP}"
    exit 1
fi
