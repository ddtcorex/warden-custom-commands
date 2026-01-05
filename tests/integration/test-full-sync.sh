#!/usr/bin/env bash
header "Full Sync Tests"
test_full_sync() {
    local web_root="$(get_web_root)"
    local media_path="/var/www/html/$(get_media_path)"
    create_test_file "${DEV_PHP}" "${web_root}/test_full_file.txt" "full file"
    create_test_file "${DEV_PHP}" "${media_path}/test_full_media.txt" "full media"
    run_db_query "${DEV_PHP}" "DROP TABLE IF EXISTS test_full_table; CREATE TABLE test_full_table (id INT, val VARCHAR(255)); INSERT INTO test_full_table VALUES (1, 'full-db-data');"
    setup_mock_env "${DEV_PHP}"
    remove_file "${LOCAL_PHP}" "${web_root}/test_full_file.txt"
    remove_file "${LOCAL_PHP}" "${media_path}/test_full_media.txt"
    run_db_query "${LOCAL_PHP}" "DROP TABLE IF EXISTS test_full_table;"
    run_sync -s dev -d local --full > /dev/null 2>&1
    local fail_reasons=""
    if ! file_exists "${LOCAL_PHP}" "${web_root}/test_full_file.txt"; then fail_reasons+="Code not synced. "; fi
    if ! file_exists "${LOCAL_PHP}" "${media_path}/test_full_media.txt"; then fail_reasons+="Media not synced. "; fi
    local result=$(run_db_query "${LOCAL_PHP}" "SELECT val FROM test_full_table WHERE id=1;" 2>&1)
    if [[ "${result}" != *"full-db-data"* ]]; then fail_reasons+="DB not synced. "; fi
    if [[ -z "${fail_reasons}" ]]; then pass "Full sync --full - Files, Media, and DB transferred successfully"; else fail "Full sync --full" "${fail_reasons}"; fi
}
test_full_sync
