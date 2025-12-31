#!/usr/bin/env bash
# test-remote-to-remote.sh - Remote-to-remote sync integration tests

header "Remote-to-Remote Sync Tests"

# Ensure networks are connected for R2R
connect_remote_networks

# Test 1: Sync file from dev to staging
test_r2r_file_sync() {
    # 1. Create file in dev
    create_test_file "${DEV_PHP}" "/var/www/html/test_r2r_file.txt" "content from dev"
    
    # 2. Ensure it doesn't exist on staging
    remove_file "${STAGING_PHP}" "/var/www/html/test_r2r_file.txt"
    
    # 3. Setup SSH agent in local container for agent forwarding to work
    # Note: We run on host, but sync.cmd uses 'ssh -A'
    # For R2R file sync, we need source to be able to talk to destination.
    # Since we use IPs in .env, they should be reachable.
    local sync_output=$(run_sync -s dev -d staging -f)
    
    # 4. Verify on staging
    if file_exists "${STAGING_PHP}" "/var/www/html/test_r2r_file.txt"; then
        local content=$(get_file_content "${STAGING_PHP}" "/var/www/html/test_r2r_file.txt")
        if [[ "${content}" == *"content from dev"* ]]; then
            pass "R2R file sync - file transferred from dev to staging"
        else
            fail "R2R file sync" "Content mismatch. Expected 'content from dev', got '${content}'. Output: ${sync_output}"
        fi
    else
        fail "R2R file sync" "File not found on staging. Output: ${sync_output}"
    fi
}

# Test 2: Sync DB from dev to staging
test_r2r_db_sync() {
    local table_name="test_r2r_val_table"
    
    # 1. Setup mock data in dev DB
    run_db_query "${DEV_PHP}" "DROP TABLE IF EXISTS ${table_name};"
    run_db_query "${DEV_PHP}" "CREATE TABLE ${table_name} (id INT, val VARCHAR(255));"
    run_db_query "${DEV_PHP}" "INSERT INTO ${table_name} VALUES (1, 'r2r-dev-data');"
    
    # 2. Setup mock env.php in both dev (source) and staging (dest)
    # We use IPs because 'db' might resolve incorrectly when networks are cross-connected
    local dev_db_ip=$(docker inspect -f '{{(index .NetworkSettings.Networks "project-dev_default").IPAddress}}' project-dev-db-1)
    local staging_db_ip=$(docker inspect -f '{{(index .NetworkSettings.Networks "project-staging_default").IPAddress}}' project-staging-db-1)
    
    setup_mock_magento_env "${DEV_PHP}" "${dev_db_ip}" "magento" "magento" "magento"
    setup_mock_magento_env "${STAGING_PHP}" "${staging_db_ip}" "magento" "magento" "magento"
    
    # 3. Ensure staging DB table doesn't exist
    run_db_query "${STAGING_PHP}" "DROP TABLE IF EXISTS ${table_name};"
    
    # 4. Run sync
	local sync_output=$(run_sync -s dev -d staging --db)
    
    # 5. Verify on staging with retry loop (in case of slow commit)
    local result=""
    for i in {1..5}; do
        result=$(run_db_query "${STAGING_PHP}" "SELECT val FROM ${table_name} WHERE id=1;" | grep -v val | xargs)
        if [[ "${result}" == "r2r-dev-data" ]]; then
            break
        fi
        sleep 1
    done

    if [[ "${result}" == "r2r-dev-data" ]]; then
        pass "R2R DB sync - data transferred from dev to staging"
    else
        local all_tables=$(run_db_query "${STAGING_PHP}" "SHOW TABLES;")
        fail "R2R DB sync" "Expected 'r2r-dev-data', got '${result}'. Tables on staging: ${all_tables}. Output: ${sync_output}"
    fi
}

# Run tests
test_r2r_file_sync
test_r2r_db_sync
