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
        local cmd_args=""
        for arg in "$@"; do
            cmd_args="${cmd_args} $(printf %q "${arg}")"
        done

        local SSH_TTY_OPT=""
        if [ -t 1 ]; then
            SSH_TTY_OPT="-t"
        fi

        # Try to load user profile to ensure correct PHP version/PATH
        local LOAD_PROFILE="source ~/.bash_profile 2>/dev/null || source ~/.bashrc 2>/dev/null || source ~/.profile 2>/dev/null || true"

        ssh ${SSH_OPTS} ${SSH_TTY_OPT} -p "${ENV_SOURCE_PORT}" "${ENV_SOURCE_USER}@${ENV_SOURCE_HOST}" "${LOAD_PROFILE}; cd \"${ENV_SOURCE_DIR}\" && ${cmd_args}"
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
    printf "⌛ \033[1;32mInstalling assets...\033[0m\n"
    remote_exec php bin/console assets:install public

    after_deploy_static

    printf "\n"
    printf "✅ \033[32mStatic deploy complete!\033[0m\n"
}

function deploy_full() {
    printf "\n"
    printf "⌛ \033[1;32mInstalling dependencies...\033[0m\n"
    remote_exec composer install --no-dev --optimize-autoloader --no-interaction

    printf "\n"
    printf "⌛ \033[1;32mRunning migrations...\033[0m\n"
    remote_exec php bin/console doctrine:migrations:migrate --no-interaction

    deploy_static

    printf "\n"
    printf "⌛ \033[1;32mClearing cache...\033[0m\n"
    remote_exec php bin/console cache:clear

    printf "\n"
    printf "✅ \033[32mFull deploy complete!\033[0m\n"
}

# Deployer strategy functions (Run always in local container)
function detect_deployer_config() {
    if [[ -n "${DEPLOYER_CONFIG:-}" ]]; then
        if [[ -f "${DEPLOYER_CONFIG}" ]]; then
            echo "${DEPLOYER_CONFIG}"
            return 0
        else
            printf "\033[31mError: Specified deployer config not found: %s\033[0m\n" "${DEPLOYER_CONFIG}" >&2
            return 1
        fi
    fi
    
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
    
    local stage="${ENV_SOURCE_ORIG:-staging}"
    if [[ "${ENV_SOURCE_DEFAULT:-0}" -eq "1" ]] || [[ "${stage}" == "local" ]]; then
        stage="local"
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
