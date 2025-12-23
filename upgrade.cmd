#!/usr/bin/env bash
set -u
[[ ! "${WARDEN_DIR:-}" ]] && >&2 printf "\033[31mThis script is not intended to be run directly!\033[0m\n" && exit 1

SUBCOMMAND_DIR=$(dirname "${BASH_SOURCE[0]}")

# Source env-variables
if [[ ! -f .env ]]; then
    fatal "No .env file found. Please run 'warden bootstrap' first."
fi

source "${SUBCOMMAND_DIR}/env-variables"

# Dispatch to environment-specific upgrade
if [[ -f "${SUBCOMMAND_DIR}/env-adapters/${WARDEN_ENV_TYPE}/upgrade.cmd" ]]; then
    source "${SUBCOMMAND_DIR}/env-adapters/${WARDEN_ENV_TYPE}/upgrade.cmd" "$@"
else
    fatal "Upgrade is not supported for environment type '${WARDEN_ENV_TYPE}'"
fi
