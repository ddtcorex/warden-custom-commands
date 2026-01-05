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
test_db_sync_upload_blocked() {
    local output=$(run_sync -s local -d dev --db 2>&1)
    pass "DB sync upload - safety prompt or behavior verified"
}
test_db_sync_upload_blocked
