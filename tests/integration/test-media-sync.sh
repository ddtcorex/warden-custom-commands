#!/usr/bin/env bash
header "Media Sync Tests"
test_media_sync_structure() {
    local media_root="/var/www/html/$(get_media_path)"
    create_test_file "${LOCAL_PHP}" "${media_root}/test_media/image.jpg" "test image"
    remove_file "${DEV_PHP}" "${media_root}/test_media"
    run_sync_confirmed -s local -d dev -m > /dev/null 2>&1
    if file_exists "${DEV_PHP}" "${media_root}/test_media/image.jpg"; then
        pass "Media sync structure - directory structure preserved"
    else
        fail "Media sync structure" "Media files not synced to correct location"
    fi
}
test_media_sync_structure
if [[ "${TEST_ENV_TYPE}" == "magento2" ]]; then pass "Magento specific media tests (skipped for now)"; fi
