#!/usr/bin/env bash
# teardown-test-envs.sh - Stop and remove test environments

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

echo ""
echo -e "${YELLOW}Stopping test environments...${NC}"

for env in project-local project-dev project-staging; do
    if [[ -d "${TEST_DIR}/${env}" ]]; then
        cd "${TEST_DIR}/${env}"
        warden env down > /dev/null 2>&1 || true
        echo "  ${env}: Stopped"
    fi
done

echo ""
echo -e "${GREEN}All test environments stopped.${NC}"
echo ""
echo "To remove environment directories completely, run:"
echo "  rm -rf tests/project-local tests/project-dev tests/project-staging"
echo ""
