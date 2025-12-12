#!/usr/bin/env bash
[[ ! ${WARDEN_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

source "${WARDEN_HOME_DIR:-~/.warden}/commands/env-variables"

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
        --jobs=*|-j=*)
            DEPLOY_JOBS="${1#*=}"
            shift
            ;;
        --jobs|-j)
            if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
                DEPLOY_JOBS="$2"
                shift 2
            else
                echo "Error: Argument for $1 is missing" >&2
                exit 1
            fi
            ;;
        --static-only|-s)
            STATIC_ONLY=1
            shift
            ;;
        *)
            shift
            ;;
    esac
done

function deploy_static() {
    echo ""
    echo -e "⌛ \033[1;32mClearing static assets...\033[0m"
    warden env exec -T php-fpm rm -rf pub/static/* var/view_preprocessed/*

    echo ""
    echo -e "⌛ \033[1;32mDeploying static content...\033[0m"
    
    # Check Magento version for --jobs support (2.2+)
    MAGENTO_VERSION=$(warden env exec -T php-fpm bin/magento --version 2>/dev/null | grep -oP '\d+\.\d+' | head -n1 || echo "2.4")
    MAJOR_MINOR=$(echo "$MAGENTO_VERSION" | awk -F. '{print $1"."$2}')
    
    if (( $(echo "$MAJOR_MINOR >= 2.2" | bc -l) )); then
        warden env exec -T php-fpm bin/magento setup:static-content:deploy -f --jobs=${DEPLOY_JOBS}
    else
        echo "Note: --jobs not supported on Magento < 2.2, using sequential deployment"
        warden env exec -T php-fpm bin/magento setup:static-content:deploy -f
    fi
    
    after_deploy_static

    echo ""
    echo -e "✅ \033[32mStatic deploy complete!\033[0m"
}

function deploy_full() {
    echo ""
    echo -e "⌛ \033[1;32mInstalling dependencies...\033[0m"
    warden env exec -T php-fpm composer install
    
    # Apply patches if ece-tools is installed
    if warden env exec -T php-fpm test -f vendor/bin/ece-patches; then
        echo ""
        echo -e "⌛ \033[1;32mApplying patches...\033[0m"
        warden env exec -T php-fpm php vendor/bin/ece-patches apply || true
    fi

    echo ""
    echo -e "⌛ \033[1;32mRunning setup:upgrade...\033[0m"
    warden env exec -T php-fpm bin/magento setup:upgrade

    echo ""
    echo -e "⌛ \033[1;32mRunning setup:di:compile...\033[0m"
    warden env exec -T php-fpm bin/magento setup:di:compile
    
    deploy_static

    echo ""
    echo -e "⌛ \033[1;32mFlushing cache...\033[0m"
    warden env exec -T php-fpm bin/magento cache:flush

    echo ""
    echo -e "✅ \033[32mFull deploy complete!\033[0m"
}

# Dispatch based on flag
if [[ "$STATIC_ONLY" -eq "1" ]]; then
    deploy_static
else
    deploy_full
fi
