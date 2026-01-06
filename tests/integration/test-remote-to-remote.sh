#!/usr/bin/env bash
header "Remote-to-Remote Sync Tests"
test_r2r_file_sync() {
    local web_root="$(get_web_root)"
    create_test_file "${DEV_PHP}" "${web_root}/test_r2r.txt" "r2r data"
    remove_file "${STAGING_PHP}" "${web_root}/test_r2r.txt"
    local output
    output=$(run_sync_confirmed -s dev -d staging 2>&1) || true
    if file_exists "${STAGING_PHP}" "${web_root}/test_r2r.txt"; then 
        pass "R2R file sync - data transferred via source"
    else 
        fail "R2R file sync" "File not found on staging. Output: ${output}"
    fi
}
test_r2r_file_sync

test_r2r_db_sync() {
    run_db_query "${DEV_PHP}" "DROP TABLE IF EXISTS test_r2r_db;"
    run_db_query "${DEV_PHP}" "CREATE TABLE test_r2r_db (id INT, val VARCHAR(255));"
    run_db_query "${DEV_PHP}" "INSERT INTO test_r2r_db VALUES (1, 'r2r-db-data');"
    setup_mock_env "${DEV_PHP}" "${DEV_DB}"
    setup_mock_env "${STAGING_PHP}" "${STAGING_DB}"
    
    run_db_query "${STAGING_PHP}" "DROP TABLE IF EXISTS test_r2r_db;"
    
    # Verify data exists on source first
    local src_result=$(run_db_query "${DEV_PHP}" "SELECT val FROM test_r2r_db WHERE id=1;" 2>&1)
    if [[ "${src_result}" != *"r2r-db-data"* ]]; then
        fail "R2R DB sync" "Setup failed - data missing on source (Dev). Result: ${src_result}"
        return 1
    fi
    
    local output
    output=$(run_sync_confirmed -s dev -d staging --db 2>&1) || true
    
    local result
    result=$(run_db_query "${STAGING_PHP}" "SELECT val FROM test_r2r_db WHERE id=1;" 2>&1 | grep "r2r-db-data" | head -n 1)
    
    if [[ "${result}" == *"r2r-db-data"* ]]; then
        pass "R2R DB sync - data transferred correctly"
    else
        fail "R2R DB sync" "Verification failed. Result: ${result}. Output: ${output}"
    fi
}
test_r2r_db_sync
