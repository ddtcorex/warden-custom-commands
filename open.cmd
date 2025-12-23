#!/usr/bin/env bash
set -u
[[ ! "${WARDEN_DIR:-}" ]] && >&2 printf "\033[31mThis script is not intended to be run directly!\033[0m\n" && exit 1

SUBCOMMAND_DIR=$(dirname "${BASH_SOURCE[0]}")
source "${SUBCOMMAND_DIR}"/env-variables

# Load environment-specific open command
ENV_CMD="${SUBCOMMAND_DIR}/env-adapters/${WARDEN_ENV_TYPE}/open.cmd"

if [[ -f "${ENV_CMD}" ]]; then
    source "${ENV_CMD}"
else
    >&2 printf "Error: No open command found for environment type '%s'\n" "${WARDEN_ENV_TYPE}"
    >&2 printf "Expected: %s\n" "${ENV_CMD}"
    exit 1
fi
