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

# Configure Environment Variables based on Type
configure_test_envs "$TEST_ENV_TYPE"

echo ""
echo "Running tests for environment type: ${TEST_ENV_TYPE}"

header "Warden Sync Integration Tests"

# Step 0: Run Unit Tests (BATS)
header "Running Bootstrap Unit Tests"
BATS_CMD=""
if command -v bats &> /dev/null; then
    BATS_CMD="bats"
elif command -v npx &> /dev/null; then
    BATS_CMD="npx -y bats"
else
    echo "Warning: neither 'bats' nor 'npx' found. Skipping Unit Tests."
fi

if [[ -n "$BATS_CMD" ]]; then
    # Resolve absolute path to tests root
    TESTS_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
    BATS_FILE="${TESTS_ROOT}/adapters/${TEST_ENV_TYPE}/bootstrap.bats"
    
    if [[ -f "$BATS_FILE" ]]; then
        echo "🧪 Executing: $BATS_CMD $BATS_FILE"
        $BATS_CMD "$BATS_FILE"
        UNIT_STATUS=$?
        
        if [[ $UNIT_STATUS -ne 0 ]]; then
            echo ""
            echo "❌ Unit Tests Failed (Exit Code: $UNIT_STATUS)"
            echo "Stopping integration tests due to unit test failure."
            exit 1
        else
            echo "✅ Unit Tests Passed"
        fi
    else
        echo "ℹ️  No BATS tests found for ${TEST_ENV_TYPE} (looked at: ${BATS_FILE})"
    fi
fi

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
export WARDEN_SSH_OPTS='-o IdentityAgent=none -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes'
export WARDEN_SSH_IDENTITIES_ONLY=1

# Remove env overrides from .env
# We use LOCAL_ENV which is set by configure_test_envs
sed -i "/WARDEN_SSH_IDENTITY_FILE/d" "${LOCAL_ENV}/.env"
sed -i "/WARDEN_SSH_OPTS/d" "${LOCAL_ENV}/.env"
sed -i "/WARDEN_SSH_IDENTITIES_ONLY/d" "${LOCAL_ENV}/.env"

header "Verifying Host SSH Connectivity"
# Grab the first IP address found to avoid concatenation if multiple networks exist
# DEV_PHP is set by configure_test_envs
DEV_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' "${DEV_PHP}" | awk '{print $1}')
if ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -p 22 "www-data@${DEV_IP}" echo "OK" 2>/dev/null; then
    echo "✓ Host -> Dev (${DEV_IP}): OK"
else
    echo "✗ Host -> Dev (${DEV_IP}): FAILED"
fi

header "Cleaning Up Test Artifacts"
cleanup_test_files
echo "Done"

# Define Base Suites
TEST_SUITES=()

# Add environment-specific bootstrap tests
if [[ "${TEST_ENV_TYPE}" == "magento2" ]]; then
    TEST_SUITES+=("bootstrap-magento2.sh")
elif [[ "${TEST_ENV_TYPE}" == "laravel" ]]; then
    TEST_SUITES+=("bootstrap-laravel.sh")
elif [[ "${TEST_ENV_TYPE}" == "wordpress" ]]; then
    TEST_SUITES+=("bootstrap-wordpress.sh")
elif [[ "${TEST_ENV_TYPE}" == "symfony" ]]; then
    TEST_SUITES+=("bootstrap-symfony.sh")
fi

# Add Generic Sync Suites
TEST_SUITES+=(
    "file-sync.sh"
    "media-sync.sh"
    "db-sync.sh"
    "full-sync.sh"
    "custom-path.sh"
    "remote-to-remote.sh"
    "error-handling.sh"
)

for suite in "${TEST_SUITES[@]}"; do
    echo "🚀 Starting suite: ${suite}"
    source "${TEST_DIR}/integration/suites/${suite}"
    echo "✅ Finished suite: ${suite}"
done

test_summary
