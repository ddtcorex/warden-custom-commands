#!/usr/bin/env bash
# run-tests.sh - Main test runner for warden sync integration tests

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     Warden Sync Integration Tests                          ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"

# Check environments are running
header "Checking Test Environments"
if ! check_environments; then
    echo -e "${RED}Please start test environments first:${NC}"
    echo "  cd tests/project-local && warden env up -d"
    echo "  cd tests/project-dev && warden env up -d"
    echo "  cd tests/project-staging && warden env up -d"
    exit 1
fi
echo -e "${GREEN}All environments running${NC}"

# Detect IPs and configure .env for project-local
# We use IPs because the host might not resolve container hostnames
DEV_IP=$(docker inspect -f '{{(index .NetworkSettings.Networks "project-dev_default").IPAddress}}' project-dev-php-fpm-1)
STAGING_IP=$(docker inspect -f '{{(index .NetworkSettings.Networks "project-staging_default").IPAddress}}' project-staging-php-fpm-1)

# Update local .env with dev/staging IPs
sed -i "s|^REMOTE_DEV_HOST=.*|REMOTE_DEV_HOST=${DEV_IP}|" "${TEST_DIR}/project-local/.env"
sed -i "s|^REMOTE_STAGING_HOST=.*|REMOTE_STAGING_HOST=${STAGING_IP}|" "${TEST_DIR}/project-local/.env"

# Export the container's private key to the host for Warden to use
docker exec project-local-php-fpm-1 cat /home/www-data/.ssh/id_rsa > "${SCRIPT_DIR}/test_id_rsa"
chmod 600 "${SCRIPT_DIR}/test_id_rsa"

export WARDEN_SSH_IDENTITY_FILE="${SCRIPT_DIR}/test_id_rsa"
export WARDEN_SSH_IDENTITIES_ONLY=1
export WARDEN_SSH_OPTS="-o IdentityAgent=none"
unset SSH_AUTH_SOCK

# Also update .env just in case
sed -i "s|^WARDEN_SSH_IDENTITY_FILE=.*|WARDEN_SSH_IDENTITY_FILE=${WARDEN_SSH_IDENTITY_FILE}|" "${TEST_DIR}/project-local/.env"
grep -q "WARDEN_SSH_IDENTITY_FILE" "${TEST_DIR}/project-local/.env" || echo "WARDEN_SSH_IDENTITY_FILE=${WARDEN_SSH_IDENTITY_FILE}" >> "${TEST_DIR}/project-local/.env"


# Clean up before tests
header "Cleaning Up Test Artifacts"
cleanup_test_files
echo "Done"

# Run test suites
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
    echo -e "🚀 ${YELLOW}Starting suite: ${suite}${NC}"
    if [[ -f "${SCRIPT_DIR}/${suite}" ]]; then
        source "${SCRIPT_DIR}/${suite}" || echo -e "${RED}Suite ${suite} failed with exit code $?${NC}"
    else
        echo -e "${YELLOW}Skipping ${suite} (not implemented)${NC}"
    fi
    echo -e "✅ ${GREEN}Finished suite: ${suite}${NC}"
done

# Show summary
summary
exit $?
