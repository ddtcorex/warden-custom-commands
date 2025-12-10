#!/usr/bin/env bash
[[ ! ${WARDEN_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

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
        --version=*)
            TARGET_VERSION="${1#*=}"
            shift
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

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Magento 2 Upgrade"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Target version: ${TARGET_VERSION}"
echo ""

# Detect current version
CURRENT_VERSION=$(warden env exec -T php-fpm php bin/magento --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' || echo "unknown")
echo "Current version: ${CURRENT_VERSION}"
echo ""

if [[ -n "${DRY_RUN}" ]]; then
    echo "[DRY RUN] Would perform the following steps:"
    echo "  1. Run fix-deps --version=${TARGET_VERSION} to update PHP/Composer versions"
    echo "  2. Restart environment (warden env down && warden env up)"
    echo "  3. composer require magento/product-community-edition:${TARGET_VERSION} --no-update"
    echo "  4. composer update"
    echo "  5. bin/magento setup:upgrade"
    echo "  6. bin/magento setup:di:compile"
    echo "  7. bin/magento cache:flush"
    exit 0
fi

# Confirm upgrade
echo "⚠ This will update PHP/Composer versions in .env and restart the environment."
read -p "Proceed with upgrade to ${TARGET_VERSION}? [y/N] " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Upgrade cancelled."
    exit 0
fi

# Step 1: Update environment dependencies for target version
if [[ -z "${SKIP_ENV_UPDATE}" ]]; then
    echo ""
    echo "Step 1/7: Updating environment for target version..."
    if [[ -f "${SUBCOMMAND_DIR}/fix-deps.cmd" ]]; then
        source "${SUBCOMMAND_DIR}/fix-deps.cmd" --version="${TARGET_VERSION}"
    else
        echo "⚠ fix-deps not found, skipping environment update"
    fi
    
    echo ""
    echo "Step 2/7: Restarting environment with new PHP/Composer versions..."
    warden env down
    warden env up -d
    
    # Wait for services to be ready
    echo "Waiting for services to start..."
    sleep 5
    warden shell -c "while ! nc -z db 3306 </dev/null; do sleep 2; done"
else
    echo ""
    echo "Steps 1-2: Skipped (--skip-env-update)"
fi

echo ""
echo "Step 3/7: Updating composer.json..."
warden env exec -T php-fpm composer require magento/product-community-edition:${TARGET_VERSION} --no-update

echo ""
echo "Step 4/7: Running composer update..."
warden env exec -T php-fpm composer update

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
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Magento upgrade to ${TARGET_VERSION} completed!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

