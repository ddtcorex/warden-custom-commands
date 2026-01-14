#!/usr/bin/env bash
set -u

# env-variables is already sourced by the root dispatcher

# Helper for remote execution
function remote_exec() {
    # Default to LOCAL if no -e specified or -e local
    local TARGET_ENV="${ENV_SOURCE:-local}"
    if [[ "${ENV_SOURCE_DEFAULT:-0}" -eq "1" ]] || [[ "${TARGET_ENV}" == "local" ]]; then
        printf "DEBUG: Local exec: %s\n" "$*" >&2
        warden env exec -T php-fpm "$@"
    elif [[ -n "${ENV_SOURCE_HOST:-}" ]]; then
        # Debug remote execution
        printf "DEBUG: Remote exec: %s\n" "$*" >&2
        local cmd_args=""
        for arg in "$@"; do
            cmd_args="${cmd_args} $(printf %q "${arg}")"
        done

        if [[ -n "${ENV_SOURCE_DIR:-}" ]]; then
            printf "DEBUG: SSH Connect: %s@%s:%s\n" "${ENV_SOURCE_USER}" "${ENV_SOURCE_HOST}" "${ENV_SOURCE_PORT}" >&2
            ssh ${SSH_OPTS} -p "${ENV_SOURCE_PORT}" "${ENV_SOURCE_USER}@${ENV_SOURCE_HOST}" "cd $(printf %q "${ENV_SOURCE_DIR}") && ${cmd_args}"
        else
            printf "DEBUG: SSH Connect: %s@%s:%s\n" "${ENV_SOURCE_USER}" "${ENV_SOURCE_HOST}" "${ENV_SOURCE_PORT}" >&2
            ssh ${SSH_OPTS} -p "${ENV_SOURCE_PORT}" "${ENV_SOURCE_USER}@${ENV_SOURCE_HOST}" "${cmd_args}"
        fi
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
DEPLOY_JOBS=4
STATIC_ONLY=0

# Parse arguments
while (( "$#" )); do
    case "$1" in
        -j=*|--jobs=*)
            DEPLOY_JOBS="${1#*=}"
            shift
            ;;
        -j|--jobs)
            DEPLOY_JOBS="$2"
            shift 2
            ;;
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
    printf "⌛ \033[1;32mClearing static assets...\033[0m\n"
    remote_exec rm -rf pub/static/* var/view_preprocessed/*

    printf "\n"
    printf "⌛ \033[1;32mDeploying static content...\033[0m\n"
    
    # Check Magento version for --jobs support (2.2+)
    # Capture version. If empty, default to 2.4.
    MAGENTO_VERSION=$(remote_exec bin/magento --version 2>/dev/null | grep -oP '\d+\.\d+' | head -n1)
    if [[ -z "${MAGENTO_VERSION}" ]]; then
        MAGENTO_VERSION="2.4"
    fi
    
    # Check if version is >= 2.2 using sort -V
    LOWER_VERSION=$(printf "2.2\n%s" "${MAGENTO_VERSION}" | sort -V | head -n1)
    if [[ "${LOWER_VERSION}" == "2.2" ]]; then
        IS_MODERN_MAGENTO=1
    else
        IS_MODERN_MAGENTO=0
    fi
    
    if [[ "${IS_MODERN_MAGENTO}" -eq 1 ]]; then
        remote_exec bin/magento setup:static-content:deploy -f --jobs=${DEPLOY_JOBS:-4}
    else
        printf "Note: --jobs not supported on Magento < 2.2, using sequential deployment\n"
        remote_exec bin/magento setup:static-content:deploy -f
    fi
    
    after_deploy_static

    printf "\n"
    printf "✅ \033[32mStatic deploy complete!\033[0m\n"
}

function deploy_full() {
    printf "\n"
    printf "⌛ \033[1;32mInstalling dependencies...\033[0m\n"
    remote_exec composer install --no-interaction --verbose
    
    # Apply patches if ece-tools is installed
    if remote_exec test -f vendor/bin/ece-patches; then
        printf "\n"
        printf "⌛ \033[1;32mApplying patches...\033[0m\n"
        remote_exec php vendor/bin/ece-patches apply || true
    fi

    printf "\n"
    printf "⌛ \033[1;32mRunning setup:upgrade...\033[0m\n"
    remote_exec bin/magento setup:upgrade --no-interaction

    printf "\n"
    printf "⌛ \033[1;32mRunning setup:di:compile...\033[0m\n"
    remote_exec bin/magento setup:di:compile --no-interaction
    
    deploy_static

    printf "\n"
    printf "⌛ \033[1;32mFlushing cache...\033[0m\n"
    remote_exec bin/magento cache:flush

    printf "\n"
    printf "✅ \033[32mFull deploy complete!\033[0m\n"
}

# Dispatch based on flag
if [[ "${STATIC_ONLY:-0}" -eq "1" ]]; then
    deploy_static
else
    deploy_full
fi
