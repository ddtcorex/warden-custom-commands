#!/usr/bin/env bash
# suites/bootstrap-laravel.sh

# Source helpers if not already sourced
if [[ -z "$(type -t header)" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/../helpers.sh"
fi

if [[ "${TEST_ENV_TYPE}" != "laravel" ]]; then
    echo "Skipping Laravel bootstrap tests for environment type: ${TEST_ENV_TYPE}"
    return
fi

header "Bootstrap Workflow Tests (Laravel)"

# -----------------------------------------------------
# Scenario 1: Clean Install in Staging
# -----------------------------------------------------
header "Scenario 1: Clean Install in Staging (Laravel)"

echo "Navigating to staging environment: ${STAGING_ENV}"
cd "${STAGING_ENV}"

# Run clean install
echo "Running: warden bootstrap --clean-install"
if warden bootstrap --clean-install; then
    pass "warden bootstrap --clean-install executed successfully"
else
    fail "warden bootstrap --clean-install failed" "Exit code $?"
fi

# Assertions
if file_exists "${STAGING_PHP}" "/var/www/html/composer.json"; then
    pass "composer.json exists in staging"
else
    fail "composer.json missing in staging" "File verify failed"
fi

if file_exists "${STAGING_PHP}" "/var/www/html/.env"; then
    pass ".env exists in staging"
else
    fail ".env missing in staging" "File verify failed"
fi

# Check DB connectivity
if run_db_query "${STAGING_PHP}" "SHOW TABLES LIKE 'users'" | grep -q "users"; then
    pass "Database migrations ran (users table exists)"
else
    fail "Database migrations failed" "users table not found"
fi

# -----------------------------------------------------
# Scenario 2: Clone Staging to Local
# -----------------------------------------------------
header "Scenario 2: Clone Local from Staging (Laravel)"

echo "Navigating to local environment: ${LOCAL_ENV}"
cd "${LOCAL_ENV}"

echo "Running: warden bootstrap --download-source --source=staging --db-dump"

if warden bootstrap --download-source --source=staging; then
    pass "warden bootstrap --download-source executed successfully"
else
    fail "warden bootstrap --download-source failed" "Exit code $?"
fi

# Assertions
if file_exists "${LOCAL_PHP}" "/var/www/html/composer.json"; then
    pass "composer.json synced to local"
else
    fail "composer.json missing in local" "File sync failed"
fi

local_env_content=$(get_file_content "${LOCAL_PHP}" "/var/www/html/.env")
if echo "$local_env_content" | grep -q "DB_HOST=db"; then
    pass "Local .env DB_HOST is correctly set to 'db'"
else
    fail "Local .env DB_HOST incorrect" "Content: $(echo "$local_env_content" | grep DB_HOST)"
fi

# Check DB in local
if run_db_query "${LOCAL_PHP}" "SHOW TABLES LIKE 'users'" | grep -q "users"; then
    pass "Database imported to local (users table exists)"
else
    fail "Database import failed in local" "users table not found"
fi
