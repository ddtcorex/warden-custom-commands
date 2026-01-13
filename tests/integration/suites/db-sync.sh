#!/usr/bin/env bash
header "Database Sync Tests"

test_db_sync_download() {
    run_db_query "${DEV_PHP}" "DROP TABLE IF EXISTS test_sync_table;"
    run_db_query "${DEV_PHP}" "CREATE TABLE test_sync_table (id INT, val VARCHAR(255));"
    run_db_query "${DEV_PHP}" "INSERT INTO test_sync_table VALUES (1, 'remote-dev-data');"
    setup_mock_env "${DEV_PHP}"
    run_db_query "${LOCAL_PHP}" "DROP TABLE IF EXISTS test_sync_table;"
    
    local output
    # Test download with backup to verify standard behavior
    output=$(run_sync -s dev -d local --db --backup 2>&1) || status=$?
    local status=${status:-0}
    
    # Check data transfer
    local result
    result=$(run_db_query "${LOCAL_PHP}" "SELECT val FROM test_sync_table WHERE id=1;" 2>&1 | grep "remote-dev-data" | head -n 1)
    
    if [[ "${result}" == *"remote-dev-data"* ]]; then
        pass "DB sync download - data transferred correctly"
    else
        fail "DB sync download" "Verification failed. Result: ${result}. Sync Status: ${status}. Output: ${output}"
    fi

    # Verify backup exists and follows hyphenated naming
    # Pattern: {WARDEN_ENV_NAME}_local-{TIMESTAMP}.sql.gz
    local backup_exists=$(ls "${LOCAL_ENV}/var/${TEST_ENV_TYPE}-local_local-"*.sql.gz 2>/dev/null | wc -l)
    if [[ "${backup_exists}" -gt 0 ]]; then
        pass "DB sync download - Local backup created with standard hyphenated naming"
    else
        fail "DB sync download" "Local backup NOT found in var/. Output: ${output}"
    fi
}
test_db_sync_download

test_db_sync_upload() {
    setup_mock_env "${LOCAL_PHP}"
    setup_mock_env "${DEV_PHP}"
    
    run_db_query "${LOCAL_PHP}" "DROP TABLE IF EXISTS test_upload_table;"
    run_db_query "${LOCAL_PHP}" "CREATE TABLE test_upload_table (id INT, val VARCHAR(255));"
    run_db_query "${LOCAL_PHP}" "INSERT INTO test_upload_table VALUES (1, 'local-upload-data');"
    run_db_query "${DEV_PHP}" "DROP TABLE IF EXISTS test_upload_table;"
    
    # Clear remote backup dir
    docker exec --workdir / "${DEV_PHP}" bash -c "rm -rf /home/www-data/backup/*.sql.gz"

    local output
    output=$(run_sync_confirmed -s local -d dev --db --backup 2>&1) || true
    
    # 1. Verify data transfer
    local result
    result=$(run_db_query "${DEV_PHP}" "SELECT val FROM test_upload_table WHERE id=1;" 2>&1 | grep "local-upload-data" | head -n 1)
    
    if [[ "${result}" == *"local-upload-data"* ]]; then
        pass "DB sync upload - data transferred (Local -> Dev)"
    else
        fail "DB sync upload" "Verification failed. Result: ${result}. Output: ${output}"
    fi

    # 2. Verify remote backup follows hyphenated naming
    # Pattern: {WARDEN_ENV_NAME}_dev-{TIMESTAMP}.sql.gz (handled by warden db-dump -e dev)
    # The local WARDEN_ENV_NAME is used as prefix
    local backup_exists=$(docker exec --workdir / "${DEV_PHP}" bash -c "ls /home/www-data/backup/${TEST_ENV_TYPE}-local_dev-*.sql.gz 2>/dev/null | wc -l")
    if [[ "${backup_exists}" -gt 0 ]]; then
        pass "DB sync upload - Remote backup created with standard hyphenated naming"
    else
        fail "DB sync upload" "Remote backup NOT found in ~/backup/. Output: ${output}"
    fi

    # 3. Verify the temporary upload file used hyphenated naming during the process
    # We can check the output for the scp line or just rely on the fact that if it finished, it worked.
    # But let's check output for the new hyphenated pattern
    if echo "${output}" | grep -q "local-to-dev" || echo "${output}" | grep -q "Streaming mysqldump from local to"; then
        pass "DB sync upload - Used hyphenated 'local-to-dev' naming OR streamed directly"
    else
        fail "DB sync upload" "Output did not contain expected 'local-to-dev' pattern or streaming confirmation. Output: ${output}"
    fi
}
test_db_sync_upload
