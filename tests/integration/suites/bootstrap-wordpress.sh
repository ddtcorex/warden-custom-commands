#!/usr/bin/env bash
# suites/bootstrap-wordpress.sh

# Source helpers if not already sourced
if [[ -z "$(type -t header)" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/../helpers.sh"
fi

if [[ "${TEST_ENV_TYPE}" != "wordpress" ]]; then
    echo "Skipping WordPress bootstrap tests for environment type: ${TEST_ENV_TYPE}"
    return
fi

header "Bootstrap Workflow Tests (WordPress)"

# -----------------------------------------------------
# Scenario 1: Clean Install in Staging
# -----------------------------------------------------
header "Scenario 1: Clean Install in Staging (WordPress)"

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
CONFIG_FILE="/var/www/html/wp-config.php"
TABLE_CHECK="wp_users"

if file_exists "${STAGING_PHP}" "/var/www/html/composer.json"; then
    pass "composer.json exists in staging"
else
    # Wordpress might not have composer.json by default on clean install
    info "composer.json missing in staging (expected for vanilla WordPress)"
fi

if file_exists "${STAGING_PHP}" "${CONFIG_FILE}"; then
    pass "${CONFIG_FILE} exists in staging"
else
    fail "${CONFIG_FILE} missing in staging" "File verify failed"
fi

# Check DB connectivity
if run_db_query "${STAGING_PHP}" "SHOW TABLES LIKE '${TABLE_CHECK}'" | grep -q "${TABLE_CHECK}"; then
    pass "Database migrations/install ran (${TABLE_CHECK} table exists)"
else
    fail "Database check failed" "${TABLE_CHECK} table not found"
    echo "DEBUG: Tables in Staging:"
    run_db_query "${STAGING_PHP}" "SHOW TABLES"
fi

# -----------------------------------------------------
# Scenario 2: Clone Staging to Local
# -----------------------------------------------------
header "Scenario 2: Clone Local from Staging (WordPress)"

echo "Navigating to local environment: ${LOCAL_ENV}"
cd "${LOCAL_ENV}"

echo "Running: warden bootstrap --download-source --source=staging --db-dump"

if warden bootstrap --download-source --source=staging; then
    pass "warden bootstrap --download-source executed successfully"
else
    fail "warden bootstrap --download-source failed" "Exit code $?"
fi

# Assertions
if file_exists "${LOCAL_PHP}" "${CONFIG_FILE}"; then
    pass "${CONFIG_FILE} synced/created in local"
else
    fail "${CONFIG_FILE} missing in local" "File sync failed"
fi

local_config_content=$(get_file_content "${LOCAL_PHP}" "${CONFIG_FILE}")
if echo "$local_config_content" | grep -E -q "define\(\s*'DB_HOST',\s*'(db|.*-db-1)'\s*\);"; then
    pass "Local wp-config.php DB_HOST is correctly set ('db' or explicit container)"
else
    fail "Local wp-config.php DB_HOST incorrect" "Content match failed. Content: $local_config_content"
fi

# Check DB in local
if run_db_query "${LOCAL_PHP}" "SHOW TABLES LIKE '${TABLE_CHECK}'" | grep -q "${TABLE_CHECK}"; then
    pass "Database imported to local (${TABLE_CHECK} table exists)"
else
    fail "Database import failed in local" "${TABLE_CHECK} table not found"
    echo "DEBUG: Tables in Local:"
    run_db_query "${LOCAL_PHP}" "SHOW TABLES"
fi
