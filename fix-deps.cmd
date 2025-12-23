#!/usr/bin/env bash
set -u
[[ ! "${WARDEN_DIR:-}" ]] && >&2 printf "\033[31mThis script is not intended to be run directly!\033[0m\n" && exit 1

SUBCOMMAND_DIR=$(dirname "${BASH_SOURCE[0]}")

# Source env-variables to get WARDEN_ENV_TYPE
source "${WARDEN_HOME_DIR:-~/.warden}/commands/env-variables"

if [[ -f "${SUBCOMMAND_DIR}/env-adapters/${WARDEN_ENV_TYPE}/fix-deps.cmd" ]]; then
    source "${SUBCOMMAND_DIR}/env-adapters/${WARDEN_ENV_TYPE}/fix-deps.cmd" "$@"
else
    >&2 printf "\033[31mThe fix-deps command is not supported for environment type '%s'\033[0m\n" "${WARDEN_ENV_TYPE}"
    exit 1
fi
