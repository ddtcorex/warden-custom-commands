#!/usr/bin/env bash
[[ ! ${WARDEN_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

SUBCOMMAND_DIR=$(dirname "${BASH_SOURCE[0]}")
source "${SUBCOMMAND_DIR}"/env-variables

# Dispatcher: delegate to environment-specific implementation
if [[ -f "${SUBCOMMAND_DIR}/env-adapters/${WARDEN_ENV_TYPE}/download-source.cmd" ]]; then
    source "${SUBCOMMAND_DIR}/env-adapters/${WARDEN_ENV_TYPE}/download-source.cmd"
else
    >&2 echo -e "\033[31mCommand 'download-source' is not supported for environment type '${WARDEN_ENV_TYPE}'\033[0m"
    exit 1
fi
