#!/usr/bin/env bash
[[ ! ${WARDEN_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

## Laravel Upgrade Command
## Upgrades Laravel framework to a specified version

# Default values
TARGET_VERSION=""
DRY_RUN=""

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
echo "Laravel Upgrade"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Target version: ${TARGET_VERSION}"
echo ""

# Detect current version
CURRENT_VERSION=$(warden env exec -T php-fpm php artisan --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' || echo "unknown")
echo "Current version: ${CURRENT_VERSION}"
echo ""

if [[ -n "${DRY_RUN}" ]]; then
    echo "[DRY RUN] Would perform the following steps:"
    echo "  1. composer require laravel/framework:^${TARGET_VERSION} --no-update"
    echo "  2. composer update"
    echo "  3. php artisan migrate (if applicable)"
    exit 0
fi

# Confirm upgrade
read -p "Proceed with upgrade to ${TARGET_VERSION}? [y/N] " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Upgrade cancelled."
    exit 0
fi

echo ""
echo "Step 1/3: Updating composer.json..."
warden env exec -T php-fpm composer require laravel/framework:^${TARGET_VERSION} --no-update

echo ""
echo "Step 2/3: Running composer update..."
warden env exec -T php-fpm composer update

echo ""
echo "Step 3/3: Running migrations..."
warden env exec -T php-fpm php artisan migrate --force || true

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Laravel upgrade to ${TARGET_VERSION} completed!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
