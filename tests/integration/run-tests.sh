#!/usr/bin/env bash
# run-tests.sh - Main entry point for integration tests

# Load helpers
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# Configuration
export TEST_ENV_TYPE="magento2"
for i in "$@"; do
    case $i in
        --type=*) export TEST_ENV_TYPE="${i#*=}"; shift ;;
    esac
done

echo ""
echo "Running tests for environment type: ${TEST_ENV_TYPE}"

header "Warden Sync Integration Tests"

# Step 1: Verify code is linked to Warden commands directory
echo "Verifying ~/.warden/commands link..."
if [[ -L ~/.warden/commands ]]; then
    echo "Commands linked successfully to $(readlink ~/.warden/commands)"
else
    echo "Warning: ~/.warden/commands is not a symbolic link. Local changes might not be reflected."
fi

# Step 2: Checking Environments
header "Checking Test Environments"
if ! check_environments; then
    echo "Please run: ./tests/integration/setup-test-envs.sh --type=${TEST_ENV_TYPE}"
    exit 1
fi
echo "All environments running"

export WARDEN_SSH_IDENTITY_FILE='~/.ssh/id_rsa'
unset WARDEN_SSH_IDENTITIES_ONLY

# Remove env overrides from .env
sed -i "/WARDEN_SSH_IDENTITY_FILE/d" "${TEST_DIR}/project-local/.env"
sed -i "/WARDEN_SSH_OPTS/d" "${TEST_DIR}/project-local/.env"
sed -i "/WARDEN_SSH_IDENTITIES_ONLY/d" "${TEST_DIR}/project-local/.env"

header "Verifying Host SSH Connectivity"
# Grab the first IP address found to avoid concatenation if multiple networks exist
DEV_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' project-dev-php-fpm-1 | awk '{print $1}')
if ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -p 22 "www-data@${DEV_IP}" echo "OK" 2>/dev/null; then
    echo "✓ Host -> Dev (${DEV_IP}): OK"
else
    echo "✗ Host -> Dev (${DEV_IP}): FAILED"
fi

header "Cleaning Up Test Artifacts"
cleanup_test_files
echo "Done"

TEST_SUITES=(
    "test-file-sync.sh"
    "test-media-sync.sh"
    "test-db-sync.sh"
    "test-full-sync.sh"
    "test-custom-path.sh"
    "test-remote-to-remote.sh"
    "test-error-handling.sh"
)

for suite in "${TEST_SUITES[@]}"; do
    echo "🚀 Starting suite: ${suite}"
    source "${TEST_DIR}/integration/${suite}"
    echo "✅ Finished suite: ${suite}"
done

test_summary
