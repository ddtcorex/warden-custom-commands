#!/usr/bin/env bash
# teardown-test-envs.sh - Remove all test environments

TEST_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

echo "Stopping test environments..."
for env in project-local project-dev project-staging; do
    if [[ -d "${TEST_DIR}/${env}" ]]; then
        cd "${TEST_DIR}/${env}"
        warden env down -v > /dev/null 2>&1
        echo "  ${env}: Stopped"
    fi
done

echo ""
echo "All test environments stopped."
echo ""
echo "To remove environment directories completely, run:"
echo "  rm -rf tests/project-local tests/project-dev tests/project-staging"
