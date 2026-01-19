#!/usr/bin/env bash
# suites/bootstrap-symfony.sh

# Source helpers if not already sourced
if [[ -z "$(type -t header)" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/../helpers.sh"
fi

if [[ "${TEST_ENV_TYPE}" != "symfony" ]]; then
    echo "Skipping Symfony bootstrap tests for environment type: ${TEST_ENV_TYPE}"
    return
fi

header "Bootstrap Workflow Tests (Symfony)"

# -----------------------------------------------------
# Scenario 1: Clean Install in Staging
# -----------------------------------------------------
header "Scenario 1: Clean Install in Staging (Symfony)"

echo "Navigating to staging environment: ${STAGING_ENV}"
cd "${STAGING_ENV}"

# Run fresh install
echo "Running: warden bootstrap --fresh"
if warden bootstrap --fresh; then
    pass "warden bootstrap --fresh executed successfully"
else
    fail "warden bootstrap --fresh failed" "Exit code $?"
fi

# Assertions
if file_exists "${STAGING_PHP}" "/var/www/html/composer.json"; then
    pass "composer.json exists in staging"
else
    fail "composer.json missing in staging" "File verify failed"
fi

# Symfony uses .env or .env.local
if file_exists "${STAGING_PHP}" "/var/www/html/.env"; then
    pass ".env exists in staging"
else
    fail ".env missing in staging" "File verify failed"
fi

# Check DB configuration string
staging_env_content=$(get_file_content "${STAGING_PHP}" "/var/www/html/.env")
if [[ "$staging_env_content" == *"DATABASE_URL"* ]]; then
    pass "DATABASE_URL exists in staging .env"
else
    fail "DATABASE_URL missing in staging" "Content verification failed"
fi

# -----------------------------------------------------
# Scenario 2: Clone Staging to Local
# -----------------------------------------------------
header "Scenario 2: Clone Local from Staging (Symfony)"

# Scenario 1's clean-install may have restarted staging container or killed sshd
# Ensure SSH is running on staging before attempting sync
echo "Ensuring SSH is running on staging..."
docker exec --workdir / -u root "${STAGING_PHP}" bash -c "command -v sshd >/dev/null 2>&1 || dnf install -y openssh-server > /dev/null 2>&1; ssh-keygen -A > /dev/null 2>&1; mkdir -p /run/sshd; /usr/sbin/sshd 2>/dev/null || true"

# Ensure SSH keys are in place for local -> staging
LOCAL_PUBKEY=$(docker exec --workdir / "${LOCAL_PHP}" cat /home/www-data/.ssh/id_rsa.pub 2>/dev/null || true)
if [[ -n "${LOCAL_PUBKEY}" ]]; then
    docker exec --workdir / -u www-data "${STAGING_PHP}" bash -c "mkdir -p ~/.ssh && echo '${LOCAL_PUBKEY}' >> ~/.ssh/authorized_keys && sort -u ~/.ssh/authorized_keys -o ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys" 2>/dev/null || true
fi

echo "Navigating to local environment: ${LOCAL_ENV}"
cd "${LOCAL_ENV}"

echo "Running: warden bootstrap -c --source=staging"

if warden bootstrap -c --source=staging; then
    pass "warden bootstrap -c (clone) executed successfully"
else
    fail "warden bootstrap -c (clone) failed" "Exit code $?"
fi

# Assertions
if file_exists "${LOCAL_PHP}" "/var/www/html/composer.json"; then
    pass "composer.json synced to local"
else
    fail "composer.json missing in local" "File sync failed"
fi

# Check .env or .env.local in local
local_env_content=$(get_file_content "${LOCAL_PHP}" "/var/www/html/.env")
local_env_local_content=$(get_file_content "${LOCAL_PHP}" "/var/www/html/.env.local")
merged_content="${local_env_content}${local_env_local_content}"

if echo "$merged_content" | grep -E -q "DATABASE_URL=.*@(db|.*-db-1):3306"; then
    pass "Local configuration DATABASE_URL is correctly set ('db' or explicit container)"
else
    fail "Local configuration DATABASE_URL incorrect" "Content: $(echo "$merged_content" | grep DATABASE_URL)"
fi
