#!/usr/bin/env bash
# Strict mode inherited from env-variables

# Determine execution prefix based on target environment
if [[ "${ENV_SOURCE_DEFAULT:-0}" -eq "1" ]] || [[ "${ENV_SOURCE:-local}" == "local" ]]; then
    EXEC_PREFIX="warden env exec -T php-fpm"
else
    EXEC_PREFIX="warden remote-exec -e ${ENV_SOURCE} --"
fi

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
    ${EXEC_PREFIX} rm -rf pub/static/* var/view_preprocessed/*

    printf "\n"
    printf "⌛ \033[1;32mDeploying static content...\033[0m\n"
    
    # Check Magento version for --jobs support (2.2+)
    # Capture version. If empty, default to 2.4.
    MAGENTO_VERSION=$(${EXEC_PREFIX} bin/magento --version 2>/dev/null | tr -d '\r' | grep -oP '\d+\.\d+' | head -n1)
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
        ${EXEC_PREFIX} bin/magento setup:static-content:deploy -f --jobs=${DEPLOY_JOBS:-4}
    else
        printf "Note: --jobs not supported on Magento < 2.2, using sequential deployment\n"
        ${EXEC_PREFIX} bin/magento setup:static-content:deploy -f
    fi
    
    after_deploy_static

    printf "\n"
    printf "✅ \033[32mStatic deploy complete!\033[0m\n"
}

function deploy_full() {
    printf "\n"
    printf "⌛ \033[1;32mEnabling maintenance mode...\033[0m\n"
    ${EXEC_PREFIX} bin/magento maintenance:enable || true

    printf "\n"
    printf "⌛ \033[1;32mInstalling dependencies...\033[0m\n"
    ${EXEC_PREFIX} composer install --no-dev --no-interaction
    
    # Apply patches if ece-tools is installed
    if ${EXEC_PREFIX} test -f vendor/bin/ece-patches; then
        printf "\n"
        printf "⌛ \033[1;32mApplying patches...\033[0m\n"
        ${EXEC_PREFIX} php vendor/bin/ece-patches apply || true
    fi

    printf "\n"
    printf "⌛ \033[1;32mClearing generated code...\033[0m\n"
    ${EXEC_PREFIX} rm -rf generated/code/* generated/metadata/* || true

    printf "\n"
    printf "⌛ \033[1;32mRunning setup:upgrade...\033[0m\n"
    ${EXEC_PREFIX} bin/magento setup:upgrade

    printf "\n"
    printf "⌛ \033[1;32mRunning setup:di:compile...\033[0m\n"
    ${EXEC_PREFIX} bin/magento setup:di:compile
    
    deploy_static

    printf "\n"
    printf "⌛ \033[1;32mFlushing cache...\033[0m\n"
    ${EXEC_PREFIX} bin/magento cache:flush

    printf "\n"
    printf "⌛ \033[1;32mDisabling maintenance mode...\033[0m\n"
    ${EXEC_PREFIX} bin/magento maintenance:disable

    printf "\n"
    printf "✅ \033[32mFull deploy complete!\033[0m\n"
}

# Deployer strategy functions (Run always in local container)
function detect_deployer_config() {
    # If explicitly provided, use that
    if [[ -n "${DEPLOYER_CONFIG:-}" ]]; then
        if [[ -f "${DEPLOYER_CONFIG}" ]]; then
            echo "${DEPLOYER_CONFIG}"
            return 0
        else
            printf "\033[31mError: Specified deployer config not found: %s\033[0m\n" "${DEPLOYER_CONFIG}" >&2
            return 1
        fi
    fi
    
    # Check common locations
    local config_paths=(
        ".deployer/deploy.php"
        ".deployer/deploy.yaml"
        "deploy.php"
        "deploy.yaml"
    )
    
    for config in "${config_paths[@]}"; do
        if [[ -f "${config}" ]]; then
            echo "${config}"
            return 0
        fi
    done
    
    printf "\033[31mError: No deployer config found. Checked: %s\033[0m\n" "${config_paths[*]}" >&2
    return 1
}

function ensure_deployer_installed() {
    # 1. Check for local project-level deployer (inside container)
    if warden env exec -T php-fpm test -f vendor/bin/dep; then
        echo "vendor/bin/dep"
        return 0
    fi
    
    # 2. Check if dep is already in the container's PATH
    if warden env exec -T php-fpm command -v dep &>/dev/null; then
        echo "dep"
        return 0
    fi
    
    # 3. Try to locate global composer bin directory in container
    local global_bin
    global_bin=$(warden env exec -T php-fpm composer global config bin-dir --absolute 2>/dev/null | tail -n 1 | tr -d '\r')
    if [[ -n "${global_bin}" ]] && warden env exec -T php-fpm test -f "${global_bin}/dep"; then
        echo "${global_bin}/dep"
        return 0
    fi
    
    # Not found - install globally in container
    printf "⌛ \033[1;33mDeployer not found in container. Installing globally...\033[0m\n" >&2
    if ! warden env exec -T php-fpm composer global require deployer/deployer --no-interaction; then
        printf "\033[31mError: composer global require failed in container.\033[0m\n" >&2
        return 1
    fi
    
    # Check again after installation
    global_bin=$(warden env exec -T php-fpm composer global config bin-dir --absolute 2>/dev/null | tail -n 1 | tr -d '\r')
    if [[ -n "${global_bin}" ]] && warden env exec -T php-fpm test -f "${global_bin}/dep"; then
        echo "${global_bin}/dep"
        return 0
    fi
    
    # Last ditch effort
    if warden env exec -T php-fpm command -v dep &>/dev/null; then
        echo "dep"
        return 0
    fi
    
    printf "\033[31mError: Failed to find or install Deployer in container.\033[0m\n" >&2
    return 1
}

function deploy_with_deployer() {
    local config
    config=$(detect_deployer_config) || exit 1
    
    local dep_bin
    dep_bin=$(ensure_deployer_installed) || exit 1
    
    # Determine stage name (use original environment name or default to 'staging')
    local stage="${ENV_SOURCE_ORIG:-staging}"
    if [[ "${ENV_SOURCE_DEFAULT:-0}" -eq "1" ]] || [[ "${stage}" == "local" ]]; then
        stage="localhost"
    fi
    
    printf "\n"
    printf "🚀 \033[1;32mDeploying with Deployer (stage: %s)...\033[0m\n" "${stage}"
    printf "   Config: %s\n" "${config}"
    printf "   Binary: %s (in container)\n" "${dep_bin}"
    printf "\n"
    
    # Ensure SSH host key verification is disabled inside the container
    warden env exec -T php-fpm bash -c "mkdir -p ~/.ssh; grep -q 'StrictHostKeyChecking no' ~/.ssh/config 2>/dev/null || printf 'Host *\n    StrictHostKeyChecking no\n    UserKnownHostsFile /dev/null\n' >> ~/.ssh/config; chmod 600 ~/.ssh/config"
    
    # Execute deployer inside the warden container
    warden env exec -T php-fpm "${dep_bin}" deploy "${stage}" -f "${config}"
    
    printf "\n"
    printf "✅ \033[32mDeployer deploy complete!\033[0m\n"
}

# Dispatch based on strategy and flags
if [[ "${DEPLOY_STRATEGY:-native}" == "deployer" ]]; then
    deploy_with_deployer
elif [[ "${STATIC_ONLY:-0}" -eq "1" ]]; then
    deploy_static
else
    deploy_full
fi
