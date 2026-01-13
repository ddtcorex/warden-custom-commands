#!/usr/bin/env bash
# Unified test runner for warden-custom-commands
# Usage: ./tests/run-tests.sh [env-type] [--unit-only]
# Examples:
#   ./tests/run-tests.sh              # Run all tests (all adapters + integration)
#   ./tests/run-tests.sh magento2     # Run Magento 2 unit + integration tests
#   ./tests/run-tests.sh symfony      # Run Symfony unit + integration tests
#   ./tests/run-tests.sh --unit-only  # Run only unit tests, skip integration

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

ENV_TYPE=""
UNIT_ONLY=0

# Parse arguments
for arg in "$@"; do
    case $arg in
        --unit-only)
            UNIT_ONLY=1
            ;;
        magento2|symfony|laravel|wordpress|all)
            ENV_TYPE="$arg"
            ;;
        -h|--help)
            echo "Usage: $0 [env-type] [--unit-only]"
            echo ""
            echo "Environment types:"
            echo "  all        Run tests for all adapters (default)"
            echo "  magento2   Run Magento 2 tests"
            echo "  symfony    Run Symfony tests"
            echo "  laravel    Run Laravel tests"
            echo "  wordpress  Run WordPress tests"
            echo ""
            echo "Options:"
            echo "  --unit-only  Skip integration tests"
            echo "  -h, --help   Show this help"
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg"
            echo "Use -h or --help for usage"
            exit 1
            ;;
    esac
done

# Default to all if not specified
ENV_TYPE="${ENV_TYPE:-all}"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Warden Custom Commands Test Suite${NC}"
echo -e "${BLUE}  Environment: ${CYAN}${ENV_TYPE}${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Change to tests directory
cd "$SCRIPT_DIR"

# Clean up any previous test artifacts
rm -rf .tmp
mkdir -p .tmp

# Determine which BATS tests to run
case "$ENV_TYPE" in
    all)
        BATS_TESTS="unit/core/*.bats unit/adapters/magento2/*.bats unit/adapters/symfony/*.bats unit/adapters/laravel/*.bats unit/adapters/wordpress/*.bats"
        ;;
    magento2|symfony|laravel|wordpress)
        BATS_TESTS="unit/adapters/${ENV_TYPE}/*.bats"
        ;;
esac

# Run BATS unit tests
echo -e "${GREEN}▶ Running Unit Tests (${ENV_TYPE})${NC}"
echo ""
npx -y bats $BATS_TESTS

UNIT_PASSED=$?
echo ""
echo -e "${GREEN}✓ Unit Tests Complete${NC}"

# Run integration tests if not skipped
INTEGRATION_PASSED=0
if [[ "$UNIT_ONLY" -eq 0 ]]; then
    echo ""
    echo -e "${GREEN}▶ Running Integration Tests (${ENV_TYPE})${NC}"
    echo ""
    
    if [[ -x "$SCRIPT_DIR/integration/run-tests.sh" ]]; then
        if [[ "$ENV_TYPE" == "all" ]]; then
            # Run integration tests for all environment types
            for env in magento2 symfony laravel wordpress; do
                echo -e "${CYAN}▸ Integration tests for ${env}${NC}"
                "$SCRIPT_DIR/integration/run-tests.sh" --type="$env" --skip-unit || INTEGRATION_PASSED=$?
            done
        else
            "$SCRIPT_DIR/integration/run-tests.sh" --type="$ENV_TYPE" --skip-unit
            INTEGRATION_PASSED=$?
        fi
    else
        echo -e "${YELLOW}Integration test runner not found${NC}"
    fi
fi

# Clean up npx artifacts
rm -f "$ROOT_DIR/composer.json" "$ROOT_DIR/.env" "$ROOT_DIR/dump.sql.gz"
rm -f "$SCRIPT_DIR/composer.json" "$SCRIPT_DIR/.env"

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
if [[ "$UNIT_PASSED" -eq 0 ]] && [[ "$INTEGRATION_PASSED" -eq 0 ]]; then
    echo -e "${GREEN}✅ All Tests Complete${NC}"
else
    echo -e "${YELLOW}⚠ Some tests failed${NC}"
    exit 1
fi
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
