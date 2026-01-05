#!/usr/bin/env bash
header "Remote-to-Remote Sync Tests"
test_r2r_file_sync() {
    local web_root="$(get_web_root)"
    create_test_file "${DEV_PHP}" "${web_root}/test_r2r.txt" "r2r data"
    remove_file "${STAGING_PHP}" "${web_root}/test_r2r.txt"
    run_sync_confirmed -s dev -d staging > /dev/null 2>&1
    if file_exists "${STAGING_PHP}" "${web_root}/test_r2r.txt"; then pass "R2R file sync - data transferred via source"; else fail "R2R file sync" "File not found on staging"; fi
}
test_r2r_file_sync
