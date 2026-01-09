#!/usr/bin/env bash
header "Database Sync Tests"
test_db_sync_download() {
    run_db_query "${DEV_PHP}" "DROP TABLE IF EXISTS test_sync_table;"
    run_db_query "${DEV_PHP}" "CREATE TABLE test_sync_table (id INT, val VARCHAR(255));"
    run_db_query "${DEV_PHP}" "INSERT INTO test_sync_table VALUES (1, 'remote-dev-data');"
    setup_mock_env "${DEV_PHP}"
    run_db_query "${LOCAL_PHP}" "DROP TABLE IF EXISTS test_sync_table;"
    local output
    output=$(run_sync -s dev -d local --db 2>&1) || status=$?
    local status=${status:-0}
    local result
    result=$(run_db_query "${LOCAL_PHP}" "SELECT val FROM test_sync_table WHERE id=1;" 2>&1 | grep "remote-dev-data" | head -n 1)
    if [[ "${result}" == *"remote-dev-data"* ]]; then
        pass "DB sync download - data transferred correctly"
    else
        fail "DB sync download" "Verification failed. Result: ${result}. Sync Status: ${status}. Output: ${output}"
    fi
}
test_db_sync_download
test_db_sync_upload() {
    # 1. Setup Data on Local
    # Ensure env.php is valid on Local (restoring from potential file sync test overwrites)
    setup_mock_env "${LOCAL_PHP}"
    
    run_db_query "${LOCAL_PHP}" "DROP TABLE IF EXISTS test_upload_table;"
    run_db_query "${LOCAL_PHP}" "CREATE TABLE test_upload_table (id INT, val VARCHAR(255));"
    run_db_query "${LOCAL_PHP}" "INSERT INTO test_upload_table VALUES (1, 'local-upload-data');"
    # 2. Clear Destination (Dev)
    run_db_query "${DEV_PHP}" "DROP TABLE IF EXISTS test_upload_table;"
    
    # 3. Ensure Dev environment is mocked correctly for connection
    setup_mock_env "${DEV_PHP}"
    
    # 4. Run Sync (Local -> Dev)
    # Using run_sync_confirmed because uploading to remote triggers a CAUTION prompt
    local output
    output=$(run_sync_confirmed -s local -d dev --db 2>&1) || true
    
    # 5. Verify on Destination (Dev)
    local result
    result=$(run_db_query "${DEV_PHP}" "SELECT val FROM test_upload_table WHERE id=1;" 2>&1 | grep "local-upload-data" | head -n 1)
    
    if [[ "${result}" == *"local-upload-data"* ]]; then
        pass "DB sync upload - data transferred (Local -> Dev)"
    else
        fail "DB sync upload" "Verification failed. Result: ${result}. Output: ${output}"
    fi
}
test_db_sync_upload
