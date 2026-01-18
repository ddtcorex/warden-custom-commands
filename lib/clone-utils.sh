#!/usr/bin/env bash
# Clone utilities for warden bootstrap --clone
# Shared functions for detecting and initializing environments

# Guard against multiple sourcing
[[ -n "${_CLONE_UTILS_LOADED:-}" ]] && return 0
_CLONE_UTILS_LOADED=1

# Detect environment type from a remote server by checking for framework-specific files
# Usage: detect_env_type_from_remote "staging"
# Returns: Environment type (magento2, laravel, symfony, wordpress) or empty string
function detect_env_type_from_remote() {
    local env_name="${1}"
    
    # Magento 2: bin/magento exists
    if warden remote-exec -e "${env_name}" -- test -f "bin/magento" 2>/dev/null; then
        printf "magento2"
        return 0
    fi
    
    # Laravel: artisan file exists
    if warden remote-exec -e "${env_name}" -- test -f "artisan" 2>/dev/null; then
        printf "laravel"
        return 0
    fi
    
    # Symfony: bin/console exists
    if warden remote-exec -e "${env_name}" -- test -f "bin/console" 2>/dev/null; then
        printf "symfony"
        return 0
    fi
    
    # WordPress: wp-config.php or wp-includes exists
    if warden remote-exec -e "${env_name}" -- test -f "wp-config.php" 2>/dev/null || \
       warden remote-exec -e "${env_name}" -- test -d "wp-includes" 2>/dev/null; then
        printf "wordpress"
        return 0
    fi
    
    # Unknown
    return 1
}

# Prompt user to select environment type if auto-detection fails
# Usage: prompt_env_type
# Returns: Selected environment type
function prompt_env_type() {
    local options=("magento2" "laravel" "symfony" "wordpress")
    local descriptions=(
        "Magento 2 Open Source / Adobe Commerce"
        "Laravel PHP Framework"
        "Symfony PHP Framework"
        "WordPress CMS"
    )
    local selected=0
    local key=""
    local escape_char=$(printf "\u1b")

    # Hide cursor
    printf "\033[?25l" >&2

    # Function to print menu
    print_menu() {
        # Move cursor up by number of options + header lines
        if [[ "$1" == "redraw" ]]; then
            printf "\033[%dA" $(( ${#options[@]} + 2 )) >&2
        fi
        
        printf "\n\033[33mSelect environment type (Use arrow keys):\033[0m\n" >&2
        
        for i in "${!options[@]}"; do
            if [[ "$i" -eq "$selected" ]]; then
                printf "  \033[36m> %-10s - %s\033[0m\n" "${options[$i]}" "${descriptions[$i]}" >&2
            else
                printf "    %-10s - %s\n" "${options[$i]}" "${descriptions[$i]}" >&2
            fi
        done
    }

    print_menu "init"

    while true; do
        read -rsn1 key 2>/dev/null
        
        # Catch escape sequencing
        if [[ "$key" == "$escape_char" ]]; then
            read -rsn2 key 2>/dev/null
        fi

        case "$key" in
            '[A'|'k') # Up arrow or k
                ((selected--))
                if [[ $selected -lt 0 ]]; then selected=$((${#options[@]} - 1)); fi
                print_menu "redraw"
                ;;
            '[B'|'j') # Down arrow or j
                ((selected++))
                if [[ $selected -ge ${#options[@]} ]]; then selected=0; fi
                print_menu "redraw"
                ;;
            '') # Enter key (empty input)
                break
                ;;
        esac
    done

    # Show cursor again
    printf "\033[?25h" >&2
    
    printf "%s" "${options[$selected]}"
}

# Initialize Warden environment with env-init
# Usage: init_warden_env "project-name" "magento2"
# Returns: 0 on success, 1 on failure
function init_warden_env() {
    local env_name="${1:-}"
    local env_type="${2:-}"
    
    local init_args=()
    [[ -n "${env_name}" ]] && init_args+=("${env_name}")
    [[ -n "${env_type}" ]] && init_args+=("${env_type}")
    
    if ! warden env-init "${init_args[@]}"; then
        return 1
    fi
    
    return 0
}

# Check if .env file exists and is valid for Warden
# Usage: validate_warden_env
# Returns: 0 if valid, 1 if missing or invalid
function validate_warden_env() {
    if [[ ! -f ".env" ]]; then
        return 1
    fi
    
    # Check for required Warden variables
    if ! grep -q "^WARDEN_ENV_TYPE=" ".env" 2>/dev/null; then
        return 1
    fi
    
    return 0
}

# Get the project name from current directory
# Usage: get_project_name
# Returns: lowercase kebab-case project name
function get_project_name() {
    local dir_name
    dir_name=$(basename "$(pwd)")
    # Convert to lowercase and replace underscores/spaces with hyphens
    printf "%s" "${dir_name}" | tr '[:upper:]' '[:lower:]' | tr '_' '-' | tr ' ' '-'
}

# Prompt for remote details for a specific environment
# Usage: configure_clone_source_remote "dev"
# Output: Returns the .env configuration block
function configure_clone_source_remote() {
    local env_name="$1"
    local env_prefix="REMOTE_$(echo "$env_name" | tr '[:lower:]' '[:upper:]')"
    
    # Mapping for nice display names
    local display_name="${env_name}"
    case "${env_name}" in
        dev) display_name="Development" ;;
        prod) display_name="Production" ;;
        stage|staging) display_name="Staging" ;;
    esac
    
    printf "\n\033[33mTo proceed with cloning, please configure the '${display_name}' remote:\033[0m\n" >&2
    
    local input_host input_user input_port input_path input_url
    
    read -p "  Host (e.g. ssh.example.com): " input_host
    if [[ -z "${input_host}" ]]; then
        return 1
    fi
    
    read -p "  User (e.g. deploy): " input_user
    read -p "  Port (default: 22): " input_port
    input_port=${input_port:-22}
    
    read -p "  Path (e.g. /home/user/public_html): " input_path
    if [[ -z "${input_path}" ]]; then
        printf "    - Auto-detecting path... " >&2
        # Try to resolve remote HOME directory
        home_path=$(ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=no -p "${input_port}" "${input_user}@${input_host}" "echo ~" 2>/dev/null)
        
        if [[ -n "${home_path}" ]]; then
             input_path="${home_path}/public_html"
             printf "Found HOME: %s -> Defaulting to %s\n" "${home_path}" "${input_path}" >&2
        else
             printf "Failed to connect/detect. Defaulting to /var/www/html\n" >&2
             input_path="/var/www/html"
        fi
    fi

    read -p "  URL (e.g. https://example.com/): " input_url
    if [[ -z "${input_url}" ]]; then
         input_url="https://${input_host}/"
         printf "    - Defaulting to %s\n" "${input_url}" >&2
    fi

    # Return config block
    echo ""
    echo "# ${display_name} (Pre-configured)"
    echo "${env_prefix}_HOST=${input_host}"
    echo "${env_prefix}_USER=${input_user}"
    echo "${env_prefix}_PORT=${input_port}"
    echo "${env_prefix}_PATH=${input_path}"
    echo "${env_prefix}_URL=${input_url}"
}

# Detect framework version from remote
# Usage: detect_remote_version "magento2" "dev"
function detect_remote_version() {
    local type="$1"
    local env_name="$2"
    
    if [[ "${type}" == "magento2" ]]; then
        # Fetch composer.json content
        local content
        content=$(warden remote-exec -e "${env_name}" -- cat composer.json 2>/dev/null)
        
        if [[ -n "${content}" ]]; then
            # Extract version using grep and sed/cut to be safe
            # Matches: "magento/product-community-edition": "2.4.6"
            local version
            version=$(echo "${content}" | grep -E '"magento/product-(community|enterprise)-edition"' | head -1 | cut -d: -f2 | tr -d '", ')
            
            # If empty, maybe check require-dev or standard project version? 
            # But usually the require key holds the truth.
            
            if [[ -n "${version}" ]]; then
                # Handle caret/tilde constraints? e.g. ^2.4.6 -> 2.4.6
                version=$(echo "${version}" | tr -d '^~')
                echo "${version}"
                return 0
            fi
        fi
    elif [[ "${type}" == "laravel" ]]; then
        local content
        content=$(warden remote-exec -e "${env_name}" -- cat composer.json 2>/dev/null)
        if [[ -n "${content}" ]]; then
            # "laravel/framework": "^9.0"
            local version
            version=$(echo "${content}" | grep -oP '"laravel/framework":\s*"\K[^"]+' | head -1 | tr -d '^~')
            if [[ -n "${version}" ]]; then
                echo "${version}"
                return 0
            fi
        fi
    elif [[ "${type}" == "symfony" ]]; then
        local content
        content=$(warden remote-exec -e "${env_name}" -- cat composer.json 2>/dev/null)
        if [[ -n "${content}" ]]; then
            # "symfony/framework-bundle": "6.0.*" or "symfony/symfony": "*"
            local version
            version=$(echo "${content}" | grep -oP '"symfony/(framework-bundle|symfony)":\s*"\K[^"]+' | head -1 | tr -d '^~')
            # If version is just *, we can't really guess.
            if [[ -n "${version}" && "${version}" != "*" ]]; then
                echo "${version}"
                return 0
            fi
        fi
    elif [[ "${type}" == "wordpress" ]]; then
        local content
        content=$(warden remote-exec -e "${env_name}" -- cat wp-includes/version.php 2>/dev/null)
        if [[ -n "${content}" ]]; then
            # $wp_version = '6.4.2';
            local version
            version=$(echo "${content}" | grep "\$wp_version =" | grep -oP "'\K[^']+" | head -1)
            if [[ -n "${version}" ]]; then
                echo "${version}"
                return 0
            fi
        fi
    fi
    
    # Fall through
    return 1
}
