#!/usr/bin/env bash
[[ ! ${WARDEN_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

SUBCOMMAND_DIR=$(dirname "${BASH_SOURCE[0]}")
source "${SUBCOMMAND_DIR}"/env-variables

# Load environment-specific db-import command
ENV_DB_IMPORT="${SUBCOMMAND_DIR}/env-adapters/${WARDEN_ENV_TYPE}/db-import.cmd"

if [[ -f "${ENV_DB_IMPORT}" ]]; then
    source "${ENV_DB_IMPORT}"
else
    echo "Error: No db-import command found for environment type '${WARDEN_ENV_TYPE}'"
    echo "Expected: ${ENV_DB_IMPORT}"
    exit 1
fi
