#!/usr/bin/env bash
set -u
[[ ! "${WARDEN_DIR:-}" ]] && >&2 printf "\033[31mThis script is not intended to be run directly!\033[0m\n" && exit 1

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
        -v=*|--version=*)
            LARAVEL_VERSION="${1#*=}"
            shift
            ;;
        -v|--version)
            LARAVEL_VERSION="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
JSON_FILE="${SCRIPT_DIR}/laravel-versions.json"

if [[ ! -f "${JSON_FILE}" ]]; then
    >&2 printf "Error: laravel-versions.json not found at %s\n" "${JSON_FILE}"
    exit 1
fi

# Detect Laravel version if not specified
if [[ -z "${LARAVEL_VERSION}" ]]; then
    if [[ -f "composer.json" ]] && command -v jq &> /dev/null; then
        # Try to get version from composer.json
        LARAVEL_VERSION=$(jq -r '.require["laravel/framework"] // "unknown"' composer.json | sed 's/[\^~]//g' | grep -oP '^\d+' || echo "unknown")
        if [[ "${LARAVEL_VERSION}" != "unknown" ]]; then
            printf "Detected Laravel version from composer.json: %s\n" "${LARAVEL_VERSION}"
        fi
    fi
    
    # Fall back to artisan if available
    if [[ -z "${LARAVEL_VERSION:-}" ]] || [[ "${LARAVEL_VERSION:-}" == "unknown" ]]; then
        if [[ -f "artisan" ]] && warden env exec php-fpm php artisan --version &> /dev/null; then
            LARAVEL_VERSION=$(warden env exec php-fpm php artisan --version 2>/dev/null | grep -oP '\d+' | head -1)
            printf "Detected installed Laravel version: %s\n" "${LARAVEL_VERSION}"
        fi
    fi
fi

if [[ -z "${LARAVEL_VERSION:-}" ]]; then
    printf "Warning: Could not detect Laravel version. Using default (latest) configuration.\n"
    VERSION_KEY="default"
else
    printf "Using Laravel version: %s\n" "${LARAVEL_VERSION}"
    # Check if version exists in JSON
    if jq -e ".\"${LARAVEL_VERSION}\"" "${JSON_FILE}" > /dev/null 2>&1; then
        VERSION_KEY="${LARAVEL_VERSION}"
    else
        printf "Warning: Version %s not found in mapping. Using default configuration.\n" "${LARAVEL_VERSION}"
        VERSION_KEY="default"
    fi
fi

PHP_VERSION=$(jq -r ".\"${VERSION_KEY}\".php_default" "${JSON_FILE}")
MYSQL_VERSION=$(jq -r ".\"${VERSION_KEY}\".mysql" "${JSON_FILE}")
MARIADB_VERSION=$(jq -r ".\"${VERSION_KEY}\".mariadb_default" "${JSON_FILE}")
REDIS_VERSION=$(jq -r ".\"${VERSION_KEY}\".redis" "${JSON_FILE}")
COMPOSER_VERSION=$(jq -r ".\"${VERSION_KEY}\".composer" "${JSON_FILE}")

printf "\n"
printf "Recommended versions for Laravel %s:\n" "${LARAVEL_VERSION:-latest}"
printf "  PHP: %s\n" "${PHP_VERSION}"
printf "  MySQL: %s / MariaDB: %s\n" "${MYSQL_VERSION}" "${MARIADB_VERSION}"
[[ "${REDIS_VERSION}" != "null" ]] && printf "  Redis: %s\n" "${REDIS_VERSION}"
printf "  Composer: %s\n" "${COMPOSER_VERSION}"
printf "\n"

if [[ -n "${DRY_RUN:-}" ]]; then
    printf "[DRY RUN] Would update .env with the following changes:\n"
    printf "  PHP_VERSION=%s\n" "${PHP_VERSION}"
    printf "  MYSQL_DISTRIBUTION_VERSION=%s (MariaDB)\n" "${MARIADB_VERSION}"
    [[ "${REDIS_VERSION}" != "null" ]] && printf "  REDIS_VERSION=%s\n" "${REDIS_VERSION}"
    printf "  COMPOSER_VERSION=%s\n" "${COMPOSER_VERSION}"
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
