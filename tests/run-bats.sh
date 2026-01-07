#!/usr/bin/env bash
# Run BATS tests from the tests directory to prevent artifacts in root

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Change to tests directory
cd "$SCRIPT_DIR"

# Clean up any previous test artifacts
rm -rf .tmp
mkdir -p .tmp

# Run bats with all adapter tests
npx -y bats adapters/magento2/*.bats adapters/symfony/*.bats adapters/laravel/*.bats adapters/wordpress/*.bats "$@"

# Clean up npx artifacts from root (if any)
rm -f "$ROOT_DIR/composer.json" "$ROOT_DIR/.env" "$ROOT_DIR/dump.sql.gz"

echo ""
echo "✅ Tests complete. Artifacts cleaned."
