#!/usr/bin/env bash
set -u
[[ ! "${WARDEN_DIR:-}" ]] && >&2 printf "\033[31mThis script is not intended to be run directly!\033[0m\n" && exit 1

# Reconstruct arguments from WARDEN_PARAMS (consumed by warden) and preserved "$@"
# This is necessary because warden consumes non-flag arguments into WARDEN_PARAMS
if [[ -n "${WARDEN_PARAMS[@]+_}" ]]; then
    set -- "${WARDEN_PARAMS[@]}" "$@"
fi

SUBCOMMAND_DIR=$(dirname "${BASH_SOURCE[0]}")
source "${SUBCOMMAND_DIR}"/env-variables

if [[ "${1:-}" == "--" ]]; then
    shift
fi

if [[ -z "${ENV_SOURCE_HOST:-}" ]]; then
    >&2 printf "\033[31mError: Host not configured for environment '%s'.\033[0m\n" "${ENV_SOURCE}"
    exit 1
fi

if [[ $# -eq 0 ]]; then
    >&2 printf "\033[31mError: No command specified.\033[0m\n"
    exit 1
fi

# Escape arguments for safe usage in SSH command
printf -v CMD "%q " "$@"

printf "\033[33mRunning command on %s (%s)...\033[0m\n" "${ENV_SOURCE}" "${ENV_SOURCE_HOST}" >&2

run_remote() {
    # Try to load user profile to ensure correct PHP version/PATH
    local LOAD_PROFILE="source ~/.bash_profile >/dev/null 2>&1 || source ~/.bashrc >/dev/null 2>&1 || source ~/.profile >/dev/null 2>&1 || true"
    
    local SSH_TTY_OPT=""
    if [ -t 1 ]; then
        SSH_TTY_OPT="-t"
    fi

    ssh ${SSH_OPTS} ${SSH_TTY_OPT} -p "${ENV_SOURCE_PORT}" "${ENV_SOURCE_USER}@${ENV_SOURCE_HOST}" "${LOAD_PROFILE}; cd ${ENV_SOURCE_DIR} && ${CMD}"
}

run_remote
