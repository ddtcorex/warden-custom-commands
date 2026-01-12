#!/usr/bin/env bash
# suites/bootstrap-magento2.sh
#
# Integration tests for Magento 2 bootstrap command
# Focus on clean install scenario which is the most reliable test

# Source helpers if not already sourced
if [[ -z "$(type -t header)" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/../helpers.sh"
fi

if [[ "${TEST_ENV_TYPE}" != "magento2" ]]; then
    echo "Skipping Magento 2 bootstrap tests for environment type: ${TEST_ENV_TYPE}"
    return
fi

header "Bootstrap Workflow Tests (Magento 2)"

# -----------------------------------------------------
# Scenario 1: Clean Install in Staging
# Tests the full Magento installation process
# -----------------------------------------------------
header "Scenario 1: Clean Install in Staging (Magento 2)"

echo "Navigating to staging environment: ${STAGING_ENV}"
cd "${STAGING_ENV}"

# Clean any existing Magento files to ensure fresh install (keep .env for warden)
echo "Cleaning existing Magento files for fresh installation..."
docker exec --workdir / -u www-data "${STAGING_PHP}" bash -c "rm -rf /var/www/html/{app,bin,dev,generated,lib,phpserver,pub,setup,var,vendor} /var/www/html/composer.* 2>/dev/null" || true

# Run clean install (using latest stable version for PHP 8.4 compatibility)
echo "Running: warden bootstrap --clean-install --meta-version=2.4.8 --skip-admin-create"
if warden bootstrap --clean-install --meta-version=2.4.8 --skip-admin-create; then
    pass "warden bootstrap --clean-install executed successfully"
else
    fail "warden bootstrap --clean-install failed" "Exit code $?"
fi

# Assertions - Check composer.json exists
if file_exists "${STAGING_PHP}" "/var/www/html/composer.json"; then
    pass "composer.json exists in staging"
else
    fail "composer.json missing in staging" "File verify failed"
fi

# Check app/etc/env.php exists and has proper content (not the minimal mock)
if file_exists "${STAGING_PHP}" "/var/www/html/app/etc/env.php"; then
    ENV_PHP_SIZE=$(docker exec "${STAGING_PHP}" wc -c /var/www/html/app/etc/env.php | awk '{print $1}')
    if [[ "${ENV_PHP_SIZE}" -gt 500 ]]; then
        pass "app/etc/env.php exists in staging (${ENV_PHP_SIZE} bytes - full config)"
    else
        fail "app/etc/env.php too small" "Size: ${ENV_PHP_SIZE} bytes (expected > 500 for full install)"
    fi
else
    fail "app/etc/env.php missing in staging" "File verify failed"
fi

# Check app/etc/config.php exists (Magento specific - proves modules were enabled)
if file_exists "${STAGING_PHP}" "/var/www/html/app/etc/config.php"; then
    pass "app/etc/config.php exists in staging"
else
    fail "app/etc/config.php missing in staging" "File verify failed"
fi

# Check DB connectivity - Magento uses core_config_data table
TABLE_CHECK="core_config_data"
if run_db_query "${STAGING_PHP}" "SHOW TABLES LIKE '${TABLE_CHECK}'" | grep -q "${TABLE_CHECK}"; then
    pass "Database install ran (${TABLE_CHECK} table exists)"
else
    fail "Database install failed" "${TABLE_CHECK} table not found"
    echo "DEBUG: Tables in Staging:"
    run_db_query "${STAGING_PHP}" "SHOW TABLES" | head -20
fi

# Check store_website table exists (proof of full Magento install)
if run_db_query "${STAGING_PHP}" "SHOW TABLES LIKE 'store_website'" | grep -q "store_website"; then
    pass "Full Magento schema installed (store_website table exists)"
else
    fail "Incomplete Magento installation" "store_website table not found"
fi

# -----------------------------------------------------
# Scenario 2: Verify Magento CLI works after clean install
# -----------------------------------------------------
header "Scenario 2: Verify Magento CLI (Magento 2)"

# Stay in staging environment which has the installation
cd "${STAGING_ENV}"

# Check Magento CLI is functional
MAGENTO_VERSION=$(warden env exec -T php-fpm bin/magento --version 2>/dev/null)
if echo "$MAGENTO_VERSION" | grep -q "Magento"; then
    pass "Magento CLI is functional (${MAGENTO_VERSION})"
else
    fail "Magento CLI not working" "bin/magento --version output: ${MAGENTO_VERSION}"
fi

# Check module:status works
MODULE_STATUS=$(warden env exec -T php-fpm bin/magento module:status 2>/dev/null)
if echo "$MODULE_STATUS" | grep -q "Magento_Catalog"; then
    pass "Magento module:status works (Magento_Catalog found)"
else
    fail "Magento module:status failed" "Could not find Magento_Catalog module"
fi

# Check setup:db:status works (verifies DB connection and schema)
DB_STATUS=$(warden env exec -T php-fpm bin/magento setup:db:status 2>&1)
if echo "$DB_STATUS" | grep -q -E "(up to date|All modules are up to date)"; then
    pass "Magento DB status check passed (up to date)"
elif echo "$DB_STATUS" | grep -q "schema"; then
    pass "Magento DB status check passed (schema present)"
else
    fail "Magento DB status check failed" "Output: ${DB_STATUS}"
fi

# Check config:show works (proves env.php is properly configured)
CONFIG_OUTPUT=$(warden env exec -T php-fpm bin/magento config:show web/unsecure/base_url 2>/dev/null)
if [[ -n "$CONFIG_OUTPUT" ]]; then
    pass "Magento config:show works (base_url: ${CONFIG_OUTPUT})"
else
    fail "Magento config:show failed" "Could not retrieve configuration"
fi

# -----------------------------------------------------
# Scenario 3: Verify Dynamic DB Credentials
# Tests that env.php uses container-specific DB settings
# -----------------------------------------------------
header "Scenario 3: Verify Dynamic DB Credentials (Magento 2)"

cd "${STAGING_ENV}"

# Check that env.php has the expected DB host
ENV_PHP_CONTENT=$(get_file_content "${STAGING_PHP}" "/var/www/html/app/etc/env.php")

# Check for container-specific DB host (magento2-staging-db-1) or generic 'db'
if echo "$ENV_PHP_CONTENT" | grep -E -q "'host' => '(db|magento2-staging-db-1)'"; then
    pass "env.php DB host is correctly configured"
else
    fail "env.php DB host incorrect" "Check host configuration in env.php"
fi

# Check that DB credentials match container environment
if echo "$ENV_PHP_CONTENT" | grep -q "'dbname'"; then
    pass "env.php contains database name configuration"
else
    fail "env.php missing database name" "dbname not found in env.php"
fi

# Verify the crypt key was generated (proof of proper setup:install)
if echo "$ENV_PHP_CONTENT" | grep -q "'key'"; then
    pass "env.php contains encryption key (proper install)"
else
    fail "env.php missing encryption key" "Indicates setup:install did not complete properly"
fi
