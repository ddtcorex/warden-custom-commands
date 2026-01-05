#!/usr/bin/env bash
# test-file-sync.sh - File sync integration tests

header "File Sync Tests"

# Test 1: Dry run sync
test_file_sync_dry_run() {
    local web_root="$(get_web_root)"
    create_test_file "${LOCAL_PHP}" "${web_root}/test_dry_run.txt" "dry run"
    remove_file "${DEV_PHP}" "${web_root}/test_dry_run.txt"
    
    # Run with dry-run flag
    run_sync_confirmed -s local -d dev --dry-run > /dev/null 2>&1
    
    if file_exists "${DEV_PHP}" "${web_root}/test_dry_run.txt"; then
        fail "Dry run file sync" "File was transferred during dry run"
    else
        pass "Dry run file sync - no files transferred"
    fi
}

# Test 2: Upload Files
test_file_sync_upload() {
    local web_root="$(get_web_root)"
    create_test_file "${LOCAL_PHP}" "${web_root}/test_upload.txt" "upload content"
    remove_file "${DEV_PHP}" "${web_root}/test_upload.txt"
    
    run_sync_confirmed -s local -d dev > /dev/null 2>&1
    
    if file_exists "${DEV_PHP}" "${web_root}/test_upload.txt"; then
        local content=$(get_file_content "${DEV_PHP}" "${web_root}/test_upload.txt")
        if [[ "${content}" == *"upload content"* ]]; then
            pass "File upload sync - file transferred with correct content"
        else
            fail "File upload sync" "Content mismatch: ${content}"
        fi
    else
        fail "File upload sync" "File was not transferred"
    fi
}

# Test 3: Download Files
test_file_sync_download() {
    local web_root="$(get_web_root)"
    create_test_file "${DEV_PHP}" "${web_root}/test_download.txt" "download content"
    remove_file "${LOCAL_PHP}" "${web_root}/test_download.txt"
    
    run_sync -s dev -d local > /dev/null 2>&1
    
    if file_exists "${LOCAL_PHP}" "${web_root}/test_download.txt"; then
        pass "File download sync - file received"
    else
        fail "File download sync" "File was not downloaded"
    fi
}

# Test 4: Verify Exclusions
test_file_sync_exclusions() {
    local app_root=$(get_app_root)
    local exclude_path=""
    case "${TEST_ENV_TYPE}" in
        magento2) exclude_path="var/cache" ;;
        laravel)  exclude_path="storage/framework/cache/data" ;;
        symfony)  exclude_path="var/cache" ;;
        *)        exclude_path="var/cache" ;;
    esac
    
    create_test_file "${LOCAL_PHP}" "${app_root}/${exclude_path}/test.txt" "excluded"
    remove_file "${DEV_PHP}" "${app_root}/${exclude_path}/test.txt"
    
    run_sync_confirmed -s local -d dev > /dev/null 2>&1
    
    if file_exists "${DEV_PHP}" "${app_root}/${exclude_path}/test.txt"; then
        fail "File sync exclusions" "${exclude_path} was not excluded"
    else
        pass "File sync exclusions - ${exclude_path} excluded correctly"
    fi
}

# Run tests
test_file_sync_dry_run
test_file_sync_upload
test_file_sync_download
test_file_sync_exclusions
