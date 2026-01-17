#!/usr/bin/env bash
# teardown-test-envs.sh - Remove all test environments

TEST_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

echo "Stopping test environments..."
# Find all directories in tests/ that end with -local, -dev, or -staging
# Using nullglob to handle case where no files match
shopt -s nullglob
for env_dir in "${TEST_DIR}"/*-local "${TEST_DIR}"/*-dev "${TEST_DIR}"/*-staging; do
    if [[ -d "${env_dir}" ]]; then
        env_name=$(basename "${env_dir}")
        echo "  Stopping ${env_name}..."
        (
            cd "${env_dir}"
            warden env down -v > /dev/null 2>&1
        )
        echo "  ${env_name}: Stopped"
    fi
done
shopt -u nullglob

echo ""
echo "All test environments stopped."
echo ""
echo "Removing environment directories..."
rm -rf "${TEST_DIR}"/*-local "${TEST_DIR}"/*-dev "${TEST_DIR}"/*-staging
echo "Cleanup complete."
