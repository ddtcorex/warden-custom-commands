#!/usr/bin/env bash
[[ ! ${WARDEN_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

## WordPress Upgrade Command
## Upgrades WordPress core to a specified version

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
echo "WordPress Upgrade"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Target version: ${TARGET_VERSION}"
echo ""

# Detect current version
CURRENT_VERSION=$(warden env exec -T php-fpm wp core version 2>/dev/null || echo "unknown")
echo "Current version: ${CURRENT_VERSION}"
echo ""

if [[ -n "${DRY_RUN}" ]]; then
    echo "[DRY RUN] Would perform the following steps:"
    echo "  1. wp core update --version=${TARGET_VERSION}"
    echo "  2. wp core update-db"
    echo "  3. wp cache flush"
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
echo "Step 1/3: Updating WordPress core..."
warden env exec -T php-fpm wp core update --version=${TARGET_VERSION}

echo ""
echo "Step 2/3: Updating database..."
warden env exec -T php-fpm wp core update-db

echo ""
echo "Step 3/3: Flushing cache..."
warden env exec -T php-fpm wp cache flush

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ WordPress upgrade to ${TARGET_VERSION} completed!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
