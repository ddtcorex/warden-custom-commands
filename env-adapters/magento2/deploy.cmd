#!/usr/bin/env bash
set -u

# env-variables is already sourced by the root dispatcher

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
    warden env exec -T php-fpm rm -rf pub/static/* var/view_preprocessed/*

    printf "\n"
    printf "⌛ \033[1;32mDeploying static content...\033[0m\n"
    
    # Check Magento version for --jobs support (2.2+)
    MAGENTO_VERSION=$(warden env exec -T php-fpm bin/magento --version 2>/dev/null | grep -oP '\d+\.\d+' | head -n1 || printf "2.4")
    MAJOR_MINOR=$(printf "%s" "$MAGENTO_VERSION" | awk -F. '{print $1"."$2}')
    
    if (( $(printf "%s >= 2.2" "${MAJOR_MINOR:-2.4}" | bc -l) )); then
        warden env exec -T php-fpm bin/magento setup:static-content:deploy -f --jobs=${DEPLOY_JOBS:-4}
    else
        printf "Note: --jobs not supported on Magento < 2.2, using sequential deployment\n"
        warden env exec -T php-fpm bin/magento setup:static-content:deploy -f
    fi
    
    after_deploy_static

    printf "\n"
    printf "✅ \033[32mStatic deploy complete!\033[0m\n"
}

function deploy_full() {
    printf "\n"
    printf "⌛ \033[1;32mInstalling dependencies...\033[0m\n"
    warden env exec -T php-fpm composer install
    
    # Apply patches if ece-tools is installed
    if warden env exec -T php-fpm test -f vendor/bin/ece-patches; then
        printf "\n"
        printf "⌛ \033[1;32mApplying patches...\033[0m\n"
        warden env exec -T php-fpm php vendor/bin/ece-patches apply || true
    fi

    printf "\n"
    printf "⌛ \033[1;32mRunning setup:upgrade...\033[0m\n"
    warden env exec -T php-fpm bin/magento setup:upgrade

    printf "\n"
    printf "⌛ \033[1;32mRunning setup:di:compile...\033[0m\n"
    warden env exec -T php-fpm bin/magento setup:di:compile
    
    deploy_static

    printf "\n"
    printf "⌛ \033[1;32mFlushing cache...\033[0m\n"
    warden env exec -T php-fpm bin/magento cache:flush

    printf "\n"
    printf "✅ \033[32mFull deploy complete!\033[0m\n"
}

# Dispatch based on flag
if [[ "${STATIC_ONLY:-0}" -eq "1" ]]; then
    deploy_static
else
    deploy_full
fi
