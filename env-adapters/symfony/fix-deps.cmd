#!/usr/bin/env bash
# Strict mode inherited from env-variables
[[ ! "${WARDEN_DIR:-}" ]] && >&2 printf "\033[31mThis script is not intended to be run directly!\033[0m\n" && exit 1

# env-variables is already sourced by the root dispatcher

## Parse options
DRY_RUN=
SYMFONY_VERSION=

while (( "$#" )); do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        -v=*|--version=*)
            SYMFONY_VERSION="${1#*=}"
            shift
            ;;
        -v|--version)
            SYMFONY_VERSION="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
JSON_FILE="${SCRIPT_DIR}/symfony-versions.json"

if [[ ! -f "${JSON_FILE}" ]]; then
    >&2 printf "Error: symfony-versions.json not found at %s\n" "${JSON_FILE}"
    exit 1
fi

# Detect Symfony version if not specified
if [[ -z "${SYMFONY_VERSION}" ]]; then
    if [[ -f "composer.json" ]] && command -v jq &> /dev/null; then
        # Try to get version from composer.json (symfony/framework-bundle)
        SYMFONY_VERSION=$(jq -r '.require["symfony/framework-bundle"] // .require["symfony/symfony"] // "unknown"' composer.json | sed 's/[\^~]//g' | grep -oP '^\d+\.\d+' || echo "unknown")
        if [[ "${SYMFONY_VERSION}" != "unknown" ]]; then
            printf "Detected Symfony version from composer.json: %s\n" "${SYMFONY_VERSION}"
        fi
    fi
    
    # Fall back to console if available
    if [[ -z "${SYMFONY_VERSION:-}" ]] || [[ "${SYMFONY_VERSION:-}" == "unknown" ]]; then
        if [[ -f "bin/console" ]] && warden env exec php-fpm php bin/console --version &> /dev/null; then
            SYMFONY_VERSION=$(warden env exec php-fpm php bin/console --version 2>/dev/null | grep -oP '\d+\.\d+' | head -1)
            printf "Detected installed Symfony version: %s\n" "${SYMFONY_VERSION}"
        fi
    fi
fi

if [[ -z "${SYMFONY_VERSION:-}" ]]; then
    printf "Warning: Could not detect Symfony version. Using default (latest) configuration.\n"
    VERSION_KEY="default"
else
    printf "Using Symfony version: %s\n" "${SYMFONY_VERSION}"
    # Check if version exists in JSON
    if jq -e ".\"${SYMFONY_VERSION}\"" "${JSON_FILE}" > /dev/null 2>&1; then
        VERSION_KEY="${SYMFONY_VERSION}"
    else
        printf "Warning: Version %s not found in mapping. Using default configuration.\n" "${SYMFONY_VERSION}"
        VERSION_KEY="default"
    fi
fi

PHP_VERSION=$(jq -r ".\"${VERSION_KEY}\".php_default" "${JSON_FILE}")
MYSQL_VERSION=$(jq -r ".\"${VERSION_KEY}\".mysql" "${JSON_FILE}")
MARIADB_VERSION=$(jq -r ".\"${VERSION_KEY}\".mariadb_default" "${JSON_FILE}")
REDIS_VERSION=$(jq -r ".\"${VERSION_KEY}\".redis" "${JSON_FILE}")
COMPOSER_VERSION=$(jq -r ".\"${VERSION_KEY}\".composer" "${JSON_FILE}")

printf "\n"
printf "Recommended versions for Symfony %s:\n" "${SYMFONY_VERSION:-latest}"
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
grep -E "^(PHP_VERSION|MYSQL_DISTRIBUTION|MYSQL_DISTRIBUTION_VERSION|REDIS_VERSION|COMPOSER_VERSION|PHP_XDEBUG_3)=" .env | sort
