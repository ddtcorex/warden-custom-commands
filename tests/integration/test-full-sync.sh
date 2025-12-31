#!/usr/bin/env bash
# test-full-sync.sh - Full sync integration tests

header "Full Sync Tests"

# Test 1: Full sync (Files + Media + DB)
test_full_sync() {
    # 1. Setup mock data in dev
    create_test_file "${DEV_PHP}" "/var/www/html/test_full_file.txt" "full file"
    create_test_file "${DEV_PHP}" "/var/www/html/pub/media/test_full_media.txt" "full media"
    run_db_query "${DEV_PHP}" "DROP TABLE IF EXISTS test_full_table;"
    run_db_query "${DEV_PHP}" "CREATE TABLE test_full_table (id INT, val VARCHAR(255));"
    run_db_query "${DEV_PHP}" "INSERT INTO test_full_table VALUES (1, 'full-db-data');"
    setup_mock_magento_env "${DEV_PHP}" "db" "magento" "magento" "magento"

    # 2. Clean local
    remove_file "${LOCAL_PHP}" "/var/www/html/test_full_file.txt"
    remove_file "${LOCAL_PHP}" "/var/www/html/pub/media/test_full_media.txt"
    run_db_query "${LOCAL_PHP}" "DROP TABLE IF EXISTS test_full_table;"

    # 3. Run full sync
    run_sync -s dev -d local --full > /dev/null

    # 4. Verify everything
    local fail_reasons=""
    
    if ! file_exists "${LOCAL_PHP}" "/var/www/html/test_full_file.txt"; then
        fail_reasons+="Code not synced. "
    fi
    
    if ! file_exists "${LOCAL_PHP}" "/var/www/html/pub/media/test_full_media.txt"; then
        fail_reasons+="Media not synced. "
    fi
    
    local result
    result=$(run_db_query "${LOCAL_PHP}" "SELECT val FROM test_full_table WHERE id=1;" 2>&1)
    if [[ "${result}" != *"full-db-data"* ]]; then
        fail_reasons+="DB not synced (Result: ${result}). "
    fi

    if [[ -z "${fail_reasons}" ]]; then
        pass "Full sync --full - Files, Media, and DB transferred successfully"
    else
        fail "Full sync --full" "${fail_reasons}"
    fi
}

# Run tests
test_full_sync
