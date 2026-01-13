#!/usr/bin/env bash
set -u

# env-variables is already sourced by the root dispatcher

# Helper for remote execution
function remote_exec() {
    # Default to LOCAL if no -e specified or -e local
    local TARGET_ENV="${ENV_SOURCE:-local}"
    if [[ "${ENV_SOURCE_DEFAULT:-0}" -eq "1" ]] || [[ "${TARGET_ENV}" == "local" ]]; then
        warden env exec -T php-fpm "$@"
    elif [[ -n "${ENV_SOURCE_HOST:-}" ]]; then
        ssh ${SSH_OPTS} -p "${ENV_SOURCE_PORT}" "${ENV_SOURCE_USER}@${ENV_SOURCE_HOST}" "cd \"${ENV_SOURCE_DIR}\" && $*"
    else
        printf "Invalid environment '%s'\n" "${TARGET_ENV}" >&2
        exit 2
    fi
}

# Hooks
function after_deploy_static() { :; }

ENV_HOOKS_FILE="${WARDEN_ENV_PATH}/.warden/hooks"
if [ -f "${ENV_HOOKS_FILE}" ]; then
    source "${ENV_HOOKS_FILE}"
fi

# Default values
STATIC_ONLY=0

# Parse arguments
while (( "$#" )); do
    case "$1" in
        --only-static|-o)
            STATIC_ONLY=1
            shift
            ;;
        *)
            shift
            ;;
    esac
done

function deploy_static() {
    printf "\n"
    printf "⌛ \033[1;32mLinking storage...\033[0m\n"
    remote_exec php artisan storage:link --quiet || true

    after_deploy_static

    printf "\n"
    printf "✅ \033[32mStatic deploy complete!\033[0m\n"
}

function deploy_full() {
    printf "\n"
    printf "⌛ \033[1;32mInstalling dependencies...\033[0m\n"
    remote_exec composer install --no-dev --optimize-autoloader

    printf "\n"
    printf "⌛ \033[1;32mRunning migrations...\033[0m\n"
    remote_exec php artisan migrate --force || true

    deploy_static

    printf "\n"
    printf "⌛ \033[1;32mOptimizing configuration and cache...\033[0m\n"
    remote_exec php artisan optimize:clear
    remote_exec php artisan optimize

    printf "\n"
    printf "✅ \033[32mFull deploy complete!\033[0m\n"
}

# Dispatch based on flag
if [[ "${STATIC_ONLY:-0}" -eq "1" ]]; then
    deploy_static
else
    deploy_full
fi
