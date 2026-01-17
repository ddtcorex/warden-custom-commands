#!/usr/bin/env bash
[[ ! "${WARDEN_DIR:-}" ]] && >&2 printf "\033[31mThis script is not intended to be run directly!\033[0m\n" && exit 1

SUBCOMMAND_DIR=$(dirname "${BASH_SOURCE[0]}")
source "${SUBCOMMAND_DIR}"/env-variables

# Load environment-specific set-config command
ENV_SET_CONFIG="${SUBCOMMAND_DIR}/env-adapters/${WARDEN_ENV_TYPE}/set-config.cmd"

if [[ -f "${ENV_SET_CONFIG}" ]]; then
    source "${ENV_SET_CONFIG}"
else
    >&2 printf "Error: No set-config command found for environment type '%s'\n" "${WARDEN_ENV_TYPE}"
    >&2 printf "Expected: %s\n" "${ENV_SET_CONFIG}"
    exit 1
fi
