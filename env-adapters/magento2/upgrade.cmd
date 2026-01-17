#!/usr/bin/env bash
# Strict mode inherited from env-variables
[[ ! "${WARDEN_DIR:-}" ]] && >&2 printf "\033[31mThis script is not intended to be run directly!\033[0m\n" && exit 1

## Magento 2 Upgrade Command
## Upgrades Magento to a specified version

SUBCOMMAND_DIR=$(dirname "${BASH_SOURCE[0]}")

# Default values
TARGET_VERSION=""
DRY_RUN=""
SKIP_DB_UPGRADE=""
SKIP_ENV_UPDATE=""

# Parse arguments
while (( "$#" )); do
    case "$1" in
        -v=*|--version=*)
            TARGET_VERSION="${1#*=}"
            shift
            ;;
        -v|--version)
            TARGET_VERSION="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --skip-db-upgrade)
            SKIP_DB_UPGRADE=1
            shift
            ;;
        --skip-env-update)
            SKIP_ENV_UPDATE=1
            shift
            ;;
        --help)
            cat "${WARDEN_HOME_DIR:-~/.warden}/commands/upgrade.help"
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

# Validate required arguments
if [[ -z "${TARGET_VERSION}" ]]; then
    fatal "Target version is required. Usage: warden upgrade --version=<version>"
fi

printf "\n"
printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
printf "Magento 2 Upgrade\n"
printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
printf "\n"
printf "Target version: %s\n" "${TARGET_VERSION}"
printf "\n"

# Detect current version
CURRENT_VERSION=$(warden env exec -T php-fpm php bin/magento --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+(-p\d+)?' | head -n1 || true)

if [[ -z "${CURRENT_VERSION}" ]]; then
    # Fallback: Try reading from composer.json
    CURRENT_VERSION=$(warden env exec -T php-fpm cat composer.json 2>/dev/null | grep -oP '"version": "\K[^"]+' || echo "unknown")
    
    # If still unknown, try looking for magento/product package version
    if [[ "${CURRENT_VERSION}" == "unknown" ]]; then
         CURRENT_VERSION=$(warden env exec -T php-fpm composer show magento/product-community-edition 2>/dev/null | grep 'versions' | grep -oP ' \K\d+\.\d+\.\d+(-p\d+)?' | head -n1 || echo "unknown")
    fi
fi
printf "Current version: %s\n" "${CURRENT_VERSION}"
printf "\n"

if [[ -n "${DRY_RUN:-}" ]]; then
    printf "[DRY RUN] Would perform the following steps:\n"
    printf "  1. Run fix-deps --version=%s to update PHP/Composer versions\n" "${TARGET_VERSION}"
    printf "  2. Restart environment (warden env down && warden env up)\n"
    printf "  3. composer require-commerce magento/product-community-edition %s --with-all-dependencies\n" "${TARGET_VERSION}"
    printf "  4. (composer update handled by require-commerce)\n"
    printf "  5. bin/magento setup:upgrade\n"
    printf "  6. bin/magento setup:di:compile\n"
    printf "  7. bin/magento cache:flush\n"
    exit 0
fi

# Confirm upgrade
printf "⚠ This will update versions for PHP, Composer, Varnish, Redis, RabbitMQ, Elasticsearch/OpenSearch, and Database in .env and restart the environment.\n"
printf "Proceed with upgrade to %s? [y/N] " "${TARGET_VERSION}"
read -n 1 -r
printf "\n"
if [[ ! "${REPLY:-n}" =~ ^[Yy]$ ]]; then
    printf "Upgrade cancelled.\n"
    exit 0
fi

# Step 1: Update environment dependencies for target version
if [[ -z "${SKIP_ENV_UPDATE:-}" ]]; then
    printf "\n"
    printf "Step 1/7: Updating environment for target version...\n"
    if [[ -f "${SUBCOMMAND_DIR:-}/fix-deps.cmd" ]]; then
        source "${SUBCOMMAND_DIR:-}/fix-deps.cmd" --version="${TARGET_VERSION}"
    else
        printf "⚠ fix-deps not found, skipping environment update\n"
    fi
    
    printf "\n"
    printf "Step 2/7: Restarting environment (PHP, Composer, Varnish, Redis, RabbitMQ, Elasticsearch/OpenSearch, Database)...\n"
    warden env down
    warden env up -d
    
    # Wait for services to be ready
    printf "Waiting for services to start...\n"
    sleep 5
    warden shell -c "while ! nc -z db 3306 </dev/null; do sleep 2; done"
else
    printf "\n"
    printf "Steps 1-2: Skipped (--skip-env-update)\n"
fi

echo "Step 3/7: Updating composer.json..."

# Backup current composer.json
warden env exec -T php-fpm cp composer.json composer.json.bak

# Fetch target composer.json from official Magento repo via Composer (more robust than curl)
echo "Fetching composer.json for version ${TARGET_VERSION} from repo.magento.com..."

# Create a temporary project to get the composer.json
# We use --no-install to avoid downloading dependencies, just the skeleton
# We specify --repository=https://repo.magento.com/ explicitly because global config might not apply to create-project
warden env exec -T php-fpm composer create-project --no-install --ignore-platform-reqs --repository=https://repo.magento.com/ magento/project-community-edition temp_upgrade_source "${TARGET_VERSION}" || {
    echo "ERROR: Failed to fetch composer.json for version ${TARGET_VERSION}. usage of create-project failed."
    exit 1
}

# Move the fetched composer.json to current dir as composer.new.json
warden env exec -T php-fpm mv temp_upgrade_source/composer.json composer.new.json
warden env exec -T php-fpm rm -rf temp_upgrade_source

printf "Merging composer.json configuration...\n"
# Merge logic: Current * Target (Target overrides keys in Current)
# We specifically target require, require-dev, conflict, autoload, minimum-stability, prefer-stable, and extra
# This preserves 3rd party packages in 'require' while updating Magento ones
# Run jq on the host as it is required by fix-deps and might not be in the container
jq -s '.[0] * .[1]' composer.json composer.new.json > composer.merged.json

# Validate that jq worked (size check or basic validity)
if [[ ! -s "composer.merged.json" ]]; then
    echo "ERROR: JSON merge failed. Restoring backup."
    rm composer.new.json composer.merged.json
    warden env exec -T php-fpm cp composer.json.bak composer.json
    exit 1
fi

mv composer.merged.json composer.json
rm composer.new.json

echo "./composer.json has been updated."

# Relax constraints for existing tools that might conflict with new platform reqs
# We set them to "*" to allow Composer to resolve compatible versions
RELAX_PACKAGES="phpunit/phpunit:* pdepend/pdepend:* phpmd/phpmd:* friendsofphp/php-cs-fixer:* magento/magento-coding-standard:* symfony/finder:* allure-framework/allure-phpunit:* sebastian/phpcpd:* laminas/laminas-dom:*"

# Check if these packages exist in composer.json before requiring them
EXISTING_PACKAGES_TO_RELAX=""
CURRENT_CONFIG=$(warden env exec -T php-fpm cat composer.json)
for pkg in $(echo $RELAX_PACKAGES | tr " " "\n" | cut -d: -f1); do
    if echo "$CURRENT_CONFIG" | grep -q "\"$pkg\""; then
        EXISTING_PACKAGES_TO_RELAX="$EXISTING_PACKAGES_TO_RELAX $pkg:*"
    fi
done

if [[ -n "${EXISTING_PACKAGES_TO_RELAX}" ]]; then
    printf "Relaxing version constraints for: %s\n" "${EXISTING_PACKAGES_TO_RELAX}"
    warden env exec -T php-fpm composer require ${EXISTING_PACKAGES_TO_RELAX} --no-update
fi

echo ""
echo "Step 4/7: Updating dependencies..."
# Update magento/* packages and their dependencies. 
# Also allow updating any packages we relaxed to ensure they pick up the compatible versions
# We assume EXISTING_PACKAGES_TO_RELAX contains "package:*" strings, we want just the package names
RELAXED_PKG_NAMES=$(echo $EXISTING_PACKAGES_TO_RELAX | sed 's/:[*]//g')

# We use targeted update to avoid hitting missing private repos for unrelated locked packages (e.g. Hyva)
# We also include "phpunit/*" explicitly to resolve deep dependencies of the testing framework
warden env exec -T php-fpm composer update "magento/*" "phpunit/*" $RELAXED_PKG_NAMES --with-all-dependencies

echo ""
echo "Step 5/7: Running setup:upgrade..."
if [[ -z "${SKIP_DB_UPGRADE}" ]]; then
    warden env exec -T php-fpm bin/magento setup:upgrade
else
    echo "Skipped (--skip-db-upgrade)"
fi

echo ""
echo "Step 6/7: Running setup:di:compile..."
warden env exec -T php-fpm bin/magento setup:di:compile

echo ""
echo "Step 7/7: Flushing cache..."
warden env exec -T php-fpm bin/magento cache:flush

echo ""
# Cleanup backup
warden env exec -T php-fpm rm -f composer.json.bak

printf "\n"
printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
printf "✅ Magento upgrade to %s completed!\n" "${TARGET_VERSION}"
printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
printf "\n"

