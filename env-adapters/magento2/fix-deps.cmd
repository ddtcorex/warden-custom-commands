#!/usr/bin/env bash
set -u
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
    if [[ -f "composer.json" ]] && command -v jq &> /dev/null; then
        # Try to get version from composer.json
        MAGENTO_VERSION=$(jq -r '.require["magento/product-community-edition"] // .require["magento/product-enterprise-edition"] // "unknown"' composer.json | sed 's/[\^~]//g')
        if [[ "${MAGENTO_VERSION}" != "unknown" ]]; then
            printf "Detected Magento version from composer.json: %s\n" "${MAGENTO_VERSION}"
        fi
    fi
    
    # Fall back to installed version if available
    if [[ -z "${MAGENTO_VERSION:-}" ]] || [[ "${MAGENTO_VERSION:-}" == "unknown" ]]; then
        if warden env exec php-fpm bin/magento --version &> /dev/null; then
            MAGENTO_VERSION=$(warden env exec php-fpm bin/magento --version 2>/dev/null | awk '{print $3}')
            printf "Detected installed Magento version: %s\n" "${MAGENTO_VERSION}"
        fi
    fi
fi

# Store original version for display
ORIGINAL_VERSION="${MAGENTO_VERSION}"

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
        BASE_VERSION=$(echo "${MAGENTO_VERSION}" | grep -oP '^\d+\.\d+\.\d+')
        
        if [[ -n "${BASE_VERSION}" ]]; then
            # Escape dots for regex
            ESCAPED_BASE="${BASE_VERSION//./\\.}"
            
            # Find the first key in the file that matches this base version.
            # Since the file is sorted descending, the first match (e.g. 2.4.8-p3) is the latest known patch.
            # Regex matches "2.4.8" followed by " or -...
            FALLBACK_VERSION=$(grep -P -m 1 "^\s*\"${ESCAPED_BASE}(?:-[^\"]+)?\"\s*:" "${JSON_FILE}" | grep -oP "\"\K[^\"]+(?=\")")
            
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

# Update or add PHP_VERSION
if grep -q "^PHP_VERSION=" .env; then
    sed -i "s/^PHP_VERSION=.*/PHP_VERSION=${PHP_VERSION}/" .env
else
    echo "PHP_VERSION=${PHP_VERSION}" >> .env
fi

# Update MariaDB version
if grep -q "^MYSQL_DISTRIBUTION_VERSION=" .env; then
    sed -i "s/^MYSQL_DISTRIBUTION_VERSION=.*/MYSQL_DISTRIBUTION_VERSION=${MARIADB_VERSION}/" .env
else
    echo "MYSQL_DISTRIBUTION_VERSION=${MARIADB_VERSION}" >> .env
fi

# Set MySQL distribution to mariadb
if grep -q "^MYSQL_DISTRIBUTION=" .env; then
    sed -i "s/^MYSQL_DISTRIBUTION=.*/MYSQL_DISTRIBUTION=mariadb/" .env
else
    echo "MYSQL_DISTRIBUTION=mariadb" >> .env
fi

# Update Redis
if grep -q "^REDIS_VERSION=" .env; then
    sed -i "s/^REDIS_VERSION=.*/REDIS_VERSION=${REDIS_VERSION}/" .env
else
    echo "REDIS_VERSION=${REDIS_VERSION}" >> .env
fi

# Update Composer
if grep -q "^COMPOSER_VERSION=" .env; then
    sed -i "s/^COMPOSER_VERSION=.*/COMPOSER_VERSION=${COMPOSER_VERSION}/" .env
else
    echo "COMPOSER_VERSION=${COMPOSER_VERSION}" >> .env
fi

# Update RabbitMQ if version is not null
# Enable/disable OpenSearch/Elasticsearch based on version
if [[ "${OPENSEARCH_VERSION}" != "null" ]]; then
    if grep -q "^WARDEN_OPENSEARCH=" .env; then
        sed -i "s/^WARDEN_OPENSEARCH=.*/WARDEN_OPENSEARCH=1/" .env
    else
        echo "WARDEN_OPENSEARCH=1" >> .env
    fi
    
    # Set OPENSEARCH_VERSION
    if grep -q "^OPENSEARCH_VERSION=" .env; then
        sed -i "s/^OPENSEARCH_VERSION=.*/OPENSEARCH_VERSION=${OPENSEARCH_VERSION}/" .env
    else
        echo "OPENSEARCH_VERSION=${OPENSEARCH_VERSION}" >> .env
    fi

    # Disable Elasticsearch if OpenSearch is used
    if grep -q "^WARDEN_ELASTICSEARCH=" .env; then
        sed -i "s/^WARDEN_ELASTICSEARCH=.*/WARDEN_ELASTICSEARCH=0/" .env
    fi
elif [[ "${ELASTICSEARCH_VERSION}" != "null" ]]; then
    if grep -q "^WARDEN_ELASTICSEARCH=" .env; then
        sed -i "s/^WARDEN_ELASTICSEARCH=.*/WARDEN_ELASTICSEARCH=1/" .env
    else
        echo "WARDEN_ELASTICSEARCH=1" >> .env
    fi
    
    # Set ELASTICSEARCH_VERSION
    if grep -q "^ELASTICSEARCH_VERSION=" .env; then
        sed -i "s/^ELASTICSEARCH_VERSION=.*/ELASTICSEARCH_VERSION=${ELASTICSEARCH_VERSION}/" .env
    else
        echo "ELASTICSEARCH_VERSION=${ELASTICSEARCH_VERSION}" >> .env
    fi

    # Disable OpenSearch if Elasticsearch is used
    if grep -q "^WARDEN_OPENSEARCH=" .env; then
        sed -i "s/^WARDEN_OPENSEARCH=.*/WARDEN_OPENSEARCH=0/" .env
    fi
fi
if [[ "${RABBITMQ_VERSION}" != "null" ]]; then
    if grep -q "^RABBITMQ_VERSION=" .env; then
        sed -i "s/^RABBITMQ_VERSION=.*/RABBITMQ_VERSION=${RABBITMQ_VERSION}/" .env
    else
        echo "RABBITMQ_VERSION=${RABBITMQ_VERSION}" >> .env
    fi
fi

# Update Varnish if version is not null
if [[ "${VARNISH_VERSION}" != "null" ]]; then
    if grep -q "^VARNISH_VERSION=" .env; then
        sed -i "s/^VARNISH_VERSION=.*/VARNISH_VERSION=${VARNISH_VERSION}/" .env
    else
        echo "VARNISH_VERSION=${VARNISH_VERSION}" >> .env
    fi
fi

# Disable xdebug3 for PHP versions < 7.2 (xdebug3 requires PHP 7.2+)
PHP_MAJOR=$(echo "${PHP_VERSION}" | cut -d. -f1)
PHP_MINOR=$(echo "${PHP_VERSION}" | cut -d. -f2)
if [[ "${PHP_MAJOR}" -lt 7 ]] || [[ "${PHP_MAJOR}" -eq 7 && "${PHP_MINOR}" -lt 2 ]]; then
    if grep -q "^PHP_XDEBUG_3=" .env; then
        sed -i "s/^PHP_XDEBUG_3=.*/PHP_XDEBUG_3=0/" .env
    else
        echo "PHP_XDEBUG_3=0" >> .env
    fi
fi

echo "✅ .env file updated successfully!"
echo ""
echo "Summary of changes:"
grep -E "^(PHP_VERSION|MYSQL_DISTRIBUTION|MYSQL_DISTRIBUTION_VERSION|REDIS_VERSION|COMPOSER_VERSION|WARDEN_OPENSEARCH|WARDEN_ELASTICSEARCH|OPENSEARCH_VERSION|ELASTICSEARCH_VERSION|RABBITMQ_VERSION|VARNISH_VERSION|PHP_XDEBUG_3)=" .env | sort
