#!/usr/bin/env bash
[[ ! ${WARDEN_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

# env-variables is already sourced by the root dispatcher

## Parse options
DRY_RUN=
LARAVEL_VERSION=

while (( "$#" )); do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --version=*)
            LARAVEL_VERSION="${1#*=}"
            shift
            ;;
        *)
            shift
            ;;
    esac
done

SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
JSON_FILE="${SCRIPT_DIR}/laravel-versions.json"

if [[ ! -f "${JSON_FILE}" ]]; then
    >&2 echo "Error: laravel-versions.json not found at ${JSON_FILE}"
    exit 1
fi

# Detect Laravel version if not specified
if [[ -z "${LARAVEL_VERSION}" ]]; then
    if [[ -f "composer.json" ]] && command -v jq &> /dev/null; then
        # Try to get version from composer.json
        LARAVEL_VERSION=$(jq -r '.require["laravel/framework"] // "unknown"' composer.json | sed 's/[\^~]//g' | grep -oP '^\d+' || echo "unknown")
        if [[ "${LARAVEL_VERSION}" != "unknown" ]]; then
            echo "Detected Laravel version from composer.json: ${LARAVEL_VERSION}"
        fi
    fi
    
    # Fall back to artisan if available
    if [[ -z "${LARAVEL_VERSION}" ]] || [[ "${LARAVEL_VERSION}" == "unknown" ]]; then
        if [[ -f "artisan" ]] && warden env exec php-fpm php artisan --version &> /dev/null; then
            LARAVEL_VERSION=$(warden env exec php-fpm php artisan --version 2>/dev/null | grep -oP '\d+' | head -1)
            echo "Detected installed Laravel version: ${LARAVEL_VERSION}"
        fi
    fi
fi

if [[ -z "${LARAVEL_VERSION}" ]]; then
    echo "Warning: Could not detect Laravel version. Using default (latest) configuration."
    VERSION_KEY="default"
else
    echo "Using Laravel version: ${LARAVEL_VERSION}"
    # Check if version exists in JSON
    if jq -e ".\"${LARAVEL_VERSION}\"" "${JSON_FILE}" > /dev/null 2>&1; then
        VERSION_KEY="${LARAVEL_VERSION}"
    else
        echo "Warning: Version ${LARAVEL_VERSION} not found in mapping. Using default configuration."
        VERSION_KEY="default"
    fi
fi

PHP_VERSION=$(jq -r ".\"${VERSION_KEY}\".php_default" "${JSON_FILE}")
MYSQL_VERSION=$(jq -r ".\"${VERSION_KEY}\".mysql" "${JSON_FILE}")
MARIADB_VERSION=$(jq -r ".\"${VERSION_KEY}\".mariadb_default" "${JSON_FILE}")
REDIS_VERSION=$(jq -r ".\"${VERSION_KEY}\".redis" "${JSON_FILE}")
COMPOSER_VERSION=$(jq -r ".\"${VERSION_KEY}\".composer" "${JSON_FILE}")

echo ""
echo "Recommended versions for Laravel ${LARAVEL_VERSION:-latest}:"
echo "  PHP: ${PHP_VERSION}"
echo "  MySQL: ${MYSQL_VERSION} / MariaDB: ${MARIADB_VERSION}"
[[ "${REDIS_VERSION}" != "null" ]] && echo "  Redis: ${REDIS_VERSION}"
echo "  Composer: ${COMPOSER_VERSION}"
echo ""

if [[ -n "${DRY_RUN}" ]]; then
    echo "[DRY RUN] Would update .env with the following changes:"
    echo "  PHP_VERSION=${PHP_VERSION}"
    echo "  MYSQL_DISTRIBUTION_VERSION=${MARIADB_VERSION} (MariaDB)"
    [[ "${REDIS_VERSION}" != "null" ]] && echo "  REDIS_VERSION=${REDIS_VERSION}"
    echo "  COMPOSER_VERSION=${COMPOSER_VERSION}"
    echo ""
    echo "Run without --dry-run to apply changes."
    exit 0
fi

# Apply changes to .env
echo "Updating .env file..."

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

# Update Redis if version is not null
if [[ "${REDIS_VERSION}" != "null" ]]; then
    if grep -q "^REDIS_VERSION=" .env; then
        sed -i "s/^REDIS_VERSION=.*/REDIS_VERSION=${REDIS_VERSION}/" .env
    else
        echo "REDIS_VERSION=${REDIS_VERSION}" >> .env
    fi
fi

# Update Composer
if grep -q "^COMPOSER_VERSION=" .env; then
    sed -i "s/^COMPOSER_VERSION=.*/COMPOSER_VERSION=${COMPOSER_VERSION}/" .env
else
    echo "COMPOSER_VERSION=${COMPOSER_VERSION}" >> .env
fi

echo "✅ .env file updated successfully!"
echo ""
echo "Summary of changes:"
grep -E "^(PHP_VERSION|MYSQL_DISTRIBUTION|MYSQL_DISTRIBUTION_VERSION|REDIS_VERSION|COMPOSER_VERSION)=" .env | sort
