#!/usr/bin/env bash
set -euo pipefail
[[ ! "${WARDEN_DIR:-}" ]] && >&2 printf "\033[31mThis script is not intended to be run directly!\033[0m\n" && exit 1

SUBCOMMAND_DIR=$(dirname "${BASH_SOURCE[0]}")

# Source error handling utilities
source "${SUBCOMMAND_DIR}/lib/error-handling.sh"

# Check if .env exists
if [[ ! -f .env ]]; then
    >&2 echo "Error: .env file not found. Please run 'warden env-init' first."
    exit 1
fi

setup_remote_env() {
    local env_name="$1"
    local env_prefix="$2"
    
    # Check if variables already exist in .env to prevent duplicates
    if grep -q "^${env_prefix}_HOST" .env; then
        return
    fi
    
    printf "\nConfiguring %s Environment:\n" "${env_name}"
    
    printf "  Host (e.g. ssh.example.com): "
    read -r input_host
    if [[ -z "${input_host}" ]]; then
        return
    fi
    
    printf "  User (e.g. deploy): "
    read -r input_user
    
    printf "  Port (default: 22): "
    read -r input_port
    input_port=${input_port:-22}
    
    printf "  Path (e.g. /var/www/html): "
    read -r input_path
    
    if [[ -z "${input_path}" ]] && [[ -n "${input_host}" ]] && [[ -n "${input_user}" ]]; then
        printf "    - Auto-detecting path... "
        local home_path
        home_path=$(ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=no -p "${input_port}" "${input_user}@${input_host}" "echo ~" 2>/dev/null || true)
        
        if [[ -n "${home_path}" ]]; then
             input_path="${home_path}/public_html"
             printf "Found HOME: %s -> Defaulting to %s\n" "${home_path}" "${input_path}"
        else
             input_path="/var/www/html"
             printf "Defaulting to %s\n" "${input_path}"
        fi
    fi
    
    printf "  URL (e.g. https://example.com/): "
    read -r input_url
    if [[ -z "${input_url}" ]]; then
        input_url="https://${input_host}/"
        printf "    - Defaulting to %s\n" "${input_url}"
    fi

    # Store in .env
    {
        echo ""
        echo "# ${env_name}"
        echo "${env_prefix}_HOST=${input_host}"
        echo "${env_prefix}_USER=${input_user}"
        echo "${env_prefix}_PORT=${input_port}"
        echo "${env_prefix}_PATH=${input_path}"
        echo "${env_prefix}_URL=${input_url}"
    } >> .env
}

if [[ "${CLONE_MODE:-}" == "1" ]]; then
    printf "\n\033[33mRemote configuration is required for cloning.\033[0m\n"
    response="y"
else
    if [[ -t 0 ]]; then
        printf "\nDo you want to configure remote environments (Staging, Production, Dev)? [y/N] "
    fi
    read -r response || response="n"
fi

if [[ "${response}" =~ ^[yY] ]]; then
    setup_remote_env "Staging" "REMOTE_STAGING"
    setup_remote_env "Production" "REMOTE_PROD"
    setup_remote_env "Development" "REMOTE_DEV"
    printf "\nRemote environments configured.\n"
fi
