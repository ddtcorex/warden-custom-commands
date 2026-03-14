#!/usr/bin/env bash
# Strict mode inherited from env-variables
[[ ! "${WARDEN_DIR:-}" ]] && >&2 printf "\033[31mThis script is not intended to be run directly!\033[0m\n" && exit 1

# env-variables is already sourced by the root dispatcher

## Parse options
DRY_RUN=
MAGENTO_VERSION=

while (( "$#" )); do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        -v=*|--version=*)
            MAGENTO_VERSION="${1#*=}"
            shift
            ;;
        -v|--version)
            MAGENTO_VERSION="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
JSON_FILE="${SCRIPT_DIR}/magento-versions.json"

if [[ ! -f "${JSON_FILE}" ]]; then
    >&2 printf "Error: magento-versions.json not found at %s\n" "${JSON_FILE}"
    exit 1
fi

# Detect Magento version if not specified
if [[ -z "${MAGENTO_VERSION}" ]]; then
    MAGENTO_VERSION=$(detect_magento_version)
    if [[ -n "${MAGENTO_VERSION}" ]]; then
        printf "Detected Magento version: %s\n" "${MAGENTO_VERSION}"
    fi
fi

if [[ -z "${MAGENTO_VERSION:-}" ]]; then
    printf "Warning: Could not detect Magento version. Using default (latest) configuration.\n"
    VERSION_KEY="default"
else
    # Read version requirements - Check if version exists in JSON
    if jq -e ".\"${MAGENTO_VERSION}\"" "${JSON_FILE}" > /dev/null 2>&1; then
        VERSION_KEY="${MAGENTO_VERSION}"
        printf "Using Magento version: %s\n" "${MAGENTO_VERSION}"
    else
        # Fallback logic: Find latest available patch for this main version
        # 1. Extract valid base version (X.Y.Z)
        BASE_VERSION=$(echo "${MAGENTO_VERSION}" | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+')
        
        if [[ -n "${BASE_VERSION}" ]]; then
            # Escape dots for regex
            ESCAPED_BASE="${BASE_VERSION//./\\.}"
            
            # Find the first key in the file that matches this base version.
            # Since the file is sorted descending, the first match (e.g. 2.4.8-p3) is the latest known patch.
            # Use POSIX-compatible grep/awk instead of GNU grep-only PCRE
            FALLBACK_VERSION=$(grep -E "^\s*\"${ESCAPED_BASE}(-[^\"]+)?\"\s*:" "${JSON_FILE}" 2>/dev/null | awk -F '"' 'NR==1{print $2}')
            
            if [[ -n "${FALLBACK_VERSION}" ]]; then
                printf "⚠ Version '%s' not found.\n" "${MAGENTO_VERSION}"
                printf "⚠ Enforcing latest available version '%s'.\n" "${FALLBACK_VERSION}"
                
                VERSION_KEY="${FALLBACK_VERSION}"
                MAGENTO_VERSION="${FALLBACK_VERSION}"
                
                # Update .env to enforce this version for bootstrap
                if [[ -z "${DRY_RUN:-}" ]]; then
                    if grep -q "^META_VERSION=" .env 2>/dev/null; then
                        sed -i "s/^META_VERSION=.*/META_VERSION=${FALLBACK_VERSION}/" .env
                    else
                        printf "META_VERSION=%s\n" "${FALLBACK_VERSION}" >> .env
                    fi
                    printf "Updated META_VERSION in .env to %s\n" "${FALLBACK_VERSION}"
                fi
            else
                 printf "Warning: No configuration found for %s.*. Using default.\n" "${BASE_VERSION}"
                 VERSION_KEY="default"
            fi
        else
            printf "Warning: Could not parse version %s. Using default.\n" "${MAGENTO_VERSION:-}"
            VERSION_KEY="default"
        fi
    fi
fi

PHP_VERSION=$(jq -r ".\"${VERSION_KEY}\".php_default" "${JSON_FILE}")
MYSQL_VERSION=$(jq -r ".\"${VERSION_KEY}\".mysql" "${JSON_FILE}")
MARIADB_VERSION=$(jq -r ".\"${VERSION_KEY}\".mariadb_default" "${JSON_FILE}")
OPENSEARCH_VERSION=$(jq -r ".\"${VERSION_KEY}\".opensearch" "${JSON_FILE}")
ELASTICSEARCH_VERSION=$(jq -r ".\"${VERSION_KEY}\".elasticsearch" "${JSON_FILE}")
REDIS_VERSION=$(jq -r ".\"${VERSION_KEY}\".redis" "${JSON_FILE}")
COMPOSER_VERSION=$(jq -r ".\"${VERSION_KEY}\".composer" "${JSON_FILE}")
RABBITMQ_VERSION=$(jq -r ".\"${VERSION_KEY}\".rabbitmq" "${JSON_FILE}")
VARNISH_VERSION=$(jq -r ".\"${VERSION_KEY}\".varnish" "${JSON_FILE}")
printf "\n"
printf "Recommended versions for Magento %s:\n" "${MAGENTO_VERSION:-latest}"
printf "  PHP: %s\n" "${PHP_VERSION}"
printf "  MySQL: %s / MariaDB: %s\n" "${MYSQL_VERSION}" "${MARIADB_VERSION}"
[[ "${OPENSEARCH_VERSION}" != "null" ]] && printf "  OpenSearch: %s\n" "${OPENSEARCH_VERSION}"
[[ "${ELASTICSEARCH_VERSION}" != "null" ]] && printf "  Elasticsearch: %s\n" "${ELASTICSEARCH_VERSION}"
printf "  Redis: %s\n" "${REDIS_VERSION}"
printf "  Composer: %s\n" "${COMPOSER_VERSION}"
printf "  RabbitMQ: %s\n" "${RABBITMQ_VERSION}"
printf "  Varnish: %s\n" "${VARNISH_VERSION}"
printf "\n"

if [[ -n "${DRY_RUN:-}" ]]; then
    printf "[DRY RUN] Would update .env with the following changes:\n"
    printf "  PHP_VERSION=%s\n" "${PHP_VERSION}"
    printf "  MYSQL_DISTRIBUTION_VERSION=%s (MariaDB)\n" "${MARIADB_VERSION}"
    [[ "${OPENSEARCH_VERSION}" != "null" ]] && printf "  WARDEN_OPENSEARCH=1\n" && printf "  OPENSEARCH_VERSION=%s\n" "${OPENSEARCH_VERSION}"
    [[ "${ELASTICSEARCH_VERSION}" != "null" ]] && printf "  WARDEN_ELASTICSEARCH=1\n" && printf "  ELASTICSEARCH_VERSION=%s\n" "${ELASTICSEARCH_VERSION}"
    printf "  REDIS_VERSION=%s\n" "${REDIS_VERSION}"
    printf "  COMPOSER_VERSION=%s\n" "${COMPOSER_VERSION}"
    [[ "${RABBITMQ_VERSION}" != "null" ]] && printf "  RABBITMQ_VERSION=%s\n" "${RABBITMQ_VERSION}"
    [[ "${VARNISH_VERSION}" != "null" ]] && printf "  VARNISH_VERSION=%s\n" "${VARNISH_VERSION}"
    printf "\n"
    printf "Run without --dry-run to apply changes.\n"
    exit 0
fi

# Apply changes to .env
printf "Updating .env file...\n"

function update_env_var() {
    local key="$1"
    local val="$2"
    if grep -q "^${key}=" .env; then
        # Use \| as delimiter for sed to avoid issues if value contains /
        sed -i "s|^${key}=.*|${key}=${val}|" .env
    else
        echo "${key}=${val}" >> .env
    fi
}

update_env_var "PHP_VERSION" "${PHP_VERSION}"
update_env_var "MYSQL_DISTRIBUTION_VERSION" "${MARIADB_VERSION}"
update_env_var "MYSQL_DISTRIBUTION" "mariadb"
update_env_var "REDIS_VERSION" "${REDIS_VERSION}"
update_env_var "COMPOSER_VERSION" "${COMPOSER_VERSION}"

# Enable/disable OpenSearch/Elasticsearch based on version
if [[ "${OPENSEARCH_VERSION}" != "null" ]]; then
    update_env_var "WARDEN_OPENSEARCH" "1"
    update_env_var "OPENSEARCH_VERSION" "${OPENSEARCH_VERSION}"
    
    # Disable Elasticsearch if OpenSearch is used
    if grep -q "^WARDEN_ELASTICSEARCH=" .env; then
        sed -i "s/^WARDEN_ELASTICSEARCH=.*/WARDEN_ELASTICSEARCH=0/" .env
    fi
elif [[ "${ELASTICSEARCH_VERSION}" != "null" ]]; then
    update_env_var "WARDEN_ELASTICSEARCH" "1"
    update_env_var "ELASTICSEARCH_VERSION" "${ELASTICSEARCH_VERSION}"
    
    # Disable OpenSearch if Elasticsearch is used
    if grep -q "^WARDEN_OPENSEARCH=" .env; then
        sed -i "s/^WARDEN_OPENSEARCH=.*/WARDEN_OPENSEARCH=0/" .env
    fi
fi

if [[ "${RABBITMQ_VERSION}" != "null" ]]; then
    update_env_var "RABBITMQ_VERSION" "${RABBITMQ_VERSION}"
fi

if [[ "${VARNISH_VERSION}" != "null" ]]; then
    update_env_var "VARNISH_VERSION" "${VARNISH_VERSION}"
fi

# Disable xdebug3 for PHP versions < 7.2 (xdebug3 requires PHP 7.2+)
PHP_MAJOR=$(echo "${PHP_VERSION}" | cut -d. -f1)
PHP_MINOR=$(echo "${PHP_VERSION}" | cut -d. -f2)
if [[ "${PHP_MAJOR}" -lt 7 ]] || [[ "${PHP_MAJOR}" -eq 7 && "${PHP_MINOR}" -lt 2 ]]; then
    update_env_var "PHP_XDEBUG_3" "0"
fi

echo "✅ .env file updated successfully!"
echo ""
echo "Summary of changes:"
grep -E "^(PHP_VERSION|MYSQL_DISTRIBUTION|MYSQL_DISTRIBUTION_VERSION|REDIS_VERSION|COMPOSER_VERSION|WARDEN_OPENSEARCH|WARDEN_ELASTICSEARCH|OPENSEARCH_VERSION|ELASTICSEARCH_VERSION|RABBITMQ_VERSION|VARNISH_VERSION|PHP_XDEBUG_3)=" .env | sort
