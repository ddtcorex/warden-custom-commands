#!/usr/bin/env bash
set -u
[[ ! "${WARDEN_DIR:-}" ]] && >&2 printf "\033[31mThis script is not intended to be run directly!\033[0m\n" && exit 1

## WordPress Upgrade Command
## Upgrades WordPress core to a specified version

# Default values
TARGET_VERSION=""
DRY_RUN=""

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
printf "WordPress Upgrade\n"
printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
printf "\n"
printf "Target version: %s\n" "${TARGET_VERSION}"
printf "\n"

# Detect current version
CURRENT_VERSION=$(warden env exec -T php-fpm wp core version 2>/dev/null || echo "unknown")
printf "Current version: %s\n" "${CURRENT_VERSION}"
printf "\n"

if [[ -n "${DRY_RUN:-}" ]]; then
    printf "[DRY RUN] Would perform the following steps:\n"
    printf "  1. wp core update --version=%s\n" "${TARGET_VERSION}"
    printf "  2. wp core update-db\n"
    printf "  3. wp cache flush\n"
    exit 0
fi

# Confirm upgrade
printf "Proceed with upgrade to %s? [y/N] " "${TARGET_VERSION}"
read -n 1 -r
printf "\n"
if [[ ! "${REPLY:-n}" =~ ^[Yy]$ ]]; then
    printf "Upgrade cancelled.\n"
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

printf "\n"
printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
printf "✅ WordPress upgrade to %s completed!\n" "${TARGET_VERSION}"
printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
printf "\n"
