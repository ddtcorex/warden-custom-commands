#!/usr/bin/env bash
header "Custom Path Sync Tests"
test_custom_path_sync() {
    local app_root=$(get_app_root)
    create_test_file "${LOCAL_PHP}" "${app_root}/test_custom/data.txt" "custom data"
    remove_file "${DEV_PHP}" "${app_root}/test_custom"
    run_sync_confirmed -s local -d dev -p test_custom > /dev/null 2>&1
    if file_exists "${DEV_PHP}" "${app_root}/test_custom/data.txt"; then pass "Custom path sync - directory synced"; else fail "Custom path sync" "Directory was not synced"; fi
}
test_custom_path_sync
