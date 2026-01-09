#!/usr/bin/env bash
set -u
[[ ! "${WARDEN_DIR:-}" ]] && >&2 printf "\033[31mThis script is not intended to be run directly!\033[0m\n" && exit 1

# env-variables is already sourced by the root dispatcher

## Parse options
DRY_RUN=
WORDPRESS_VERSION=

while (( "$#" )); do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        -v=*|--version=*)
            WORDPRESS_VERSION="${1#*=}"
            shift
            ;;
        -v|--version)
            WORDPRESS_VERSION="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
JSON_FILE="${SCRIPT_DIR}/wordpress-versions.json"

if [[ ! -f "${JSON_FILE}" ]]; then
    >&2 echo "Error: wordpress-versions.json not found at ${JSON_FILE}"
    exit 1
fi

# Detect WordPress version if not specified
if [[ -z "${WORDPRESS_VERSION}" ]]; then
    # Try to get version from wp-includes/version.php
    if [[ -f "wp-includes/version.php" ]]; then
        WORDPRESS_VERSION=$(grep "\$wp_version = " wp-includes/version.php | grep -oP "'\K[^']+" | grep -oP '^\d+\.\d+')
        if [[ -n "${WORDPRESS_VERSION}" ]]; then
            echo "Detected WordPress version from version.php: ${WORDPRESS_VERSION}"
        fi
    fi
    
    # Fall back to WP-CLI if available
    if [[ -z "${WORDPRESS_VERSION}" ]]; then
        if warden env exec php-fpm wp core version &> /dev/null; then
            WORDPRESS_VERSION=$(warden env exec php-fpm wp core version 2>/dev/null | grep -oP '^\d+\.\d+')
            echo "Detected installed WordPress version: ${WORDPRESS_VERSION}"
        fi
    fi
fi

if [[ -z "${WORDPRESS_VERSION}" ]]; then
    echo "Warning: Could not detect WordPress version. Using default (latest) configuration."
    VERSION_KEY="default"
else
    echo "Using WordPress version: ${WORDPRESS_VERSION}"
    # Check if version exists in JSON
    if jq -e ".\"${WORDPRESS_VERSION}\"" "${JSON_FILE}" > /dev/null 2>&1; then
        VERSION_KEY="${WORDPRESS_VERSION}"
    else
        echo "Warning: Version ${WORDPRESS_VERSION} not found in mapping. Using default configuration."
        VERSION_KEY="default"
    fi
fi

PHP_VERSION=$(jq -r ".\"${VERSION_KEY}\".php_default" "${JSON_FILE}")
MYSQL_VERSION=$(jq -r ".\"${VERSION_KEY}\".mysql" "${JSON_FILE}")
MARIADB_VERSION=$(jq -r ".\"${VERSION_KEY}\".mariadb_default" "${JSON_FILE}")

echo ""
echo "Recommended versions for WordPress ${WORDPRESS_VERSION:-latest}:"
echo "  PHP: ${PHP_VERSION}"
echo "  MySQL: ${MYSQL_VERSION} / MariaDB: ${MARIADB_VERSION}"
echo ""

if [[ -n "${DRY_RUN}" ]]; then
    echo "[DRY RUN] Would update .env with the following changes:"
    echo "  PHP_VERSION=${PHP_VERSION}"
    echo "  MYSQL_DISTRIBUTION_VERSION=${MARIADB_VERSION} (MariaDB)"
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
grep -E "^(PHP_VERSION|MYSQL_DISTRIBUTION|MYSQL_DISTRIBUTION_VERSION|PHP_XDEBUG_3)=" .env | sort
