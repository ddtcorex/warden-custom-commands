#!/usr/bin/env bash
set -u
[[ ! "${WARDEN_DIR:-}" ]] && >&2 printf "\033[31mThis script is not intended to be run directly!\033[0m\n" && exit 1

SUBCOMMAND_DIR=$(dirname "${BASH_SOURCE[0]}")
source "${SUBCOMMAND_DIR}"/env-variables

# Load environment-specific db-import command
ENV_DB_IMPORT="${SUBCOMMAND_DIR}/env-adapters/${WARDEN_ENV_TYPE}/db-import.cmd"

if [[ -f "${ENV_DB_IMPORT}" ]]; then
    source "${ENV_DB_IMPORT}"
else
    >&2 printf "Error: No db-import command found for environment type '%s'\n" "${WARDEN_ENV_TYPE}"
    >&2 printf "Expected: %s\n" "${ENV_DB_IMPORT}"
    exit 1
fi
