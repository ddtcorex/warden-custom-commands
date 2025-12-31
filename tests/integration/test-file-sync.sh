#!/usr/bin/env bash
# test-file-sync.sh - File sync integration tests

header "File Sync Tests"

# Test 1: Create test file on local, verify it doesn't exist on dev
test_file_sync_setup() {
    create_test_file "${LOCAL_PHP}" "/var/www/html/test_file_sync.txt" "file sync test"
    remove_file "${DEV_PHP}" "/var/www/html/test_file_sync.txt"
}

# Test 2: Dry run should not transfer files
test_file_sync_dry_run() {
    test_file_sync_setup
    
    run_sync -s local -d dev -f --dry-run <<< "y" > /dev/null 2>&1
    
    if file_exists "${DEV_PHP}" "/var/www/html/test_file_sync.txt"; then
        fail "Dry run file sync" "File was transferred when it should not have been"
    else
        pass "Dry run file sync - no files transferred"
    fi
}

# Test 3: Actual file upload
test_file_sync_upload() {
    test_file_sync_setup
    
    local output
    output=$(run_sync_confirmed -s local -d dev -f 2>&1) || status=$?
    local status=${status:-0}
    
    if [[ $status -eq 0 ]] && file_exists "${DEV_PHP}" "/var/www/html/test_file_sync.txt"; then
        local content=$(get_file_content "${DEV_PHP}" "/var/www/html/test_file_sync.txt")
        if [[ "${content}" == *"file sync test"* ]]; then
            pass "File upload sync - file transferred with correct content"
        else
            fail "File upload sync" "File exists but content mismatch"
        fi
    else
        fail "File upload sync" "Status: $status. Output: $output"
    fi
}

# Test 4: File download
test_file_sync_download() {
    create_test_file "${DEV_PHP}" "/var/www/html/test_download.txt" "download test"
    remove_file "${LOCAL_PHP}" "/var/www/html/test_download.txt"
    
    run_sync -s dev -d local -f > /dev/null 2>&1
    
    if file_exists "${LOCAL_PHP}" "/var/www/html/test_download.txt"; then
        pass "File download sync - file received"
    else
        fail "File download sync" "File was not downloaded"
    fi
}

# Test 5: Exclusions applied (check /generated is excluded)
test_file_sync_exclusions() {
    create_test_file "${LOCAL_PHP}" "/var/www/html/generated/test_excluded.txt" "should be excluded"
    remove_file "${DEV_PHP}" "/var/www/html/generated/test_excluded.txt"
    
    run_sync_confirmed -s local -d dev -f > /dev/null 2>&1
    
    if file_exists "${DEV_PHP}" "/var/www/html/generated/test_excluded.txt"; then
        fail "File sync exclusions" "/generated directory was not excluded"
    else
        pass "File sync exclusions - /generated excluded correctly"
    fi
}

# Run all file sync tests
test_file_sync_dry_run
test_file_sync_upload
test_file_sync_download
test_file_sync_exclusions

# Cleanup
remove_file "${LOCAL_PHP}" "/var/www/html/test_file_sync.txt"
remove_file "${LOCAL_PHP}" "/var/www/html/test_download.txt"
remove_file "${LOCAL_PHP}" "/var/www/html/generated"
remove_file "${DEV_PHP}" "/var/www/html/test_file_sync.txt"
remove_file "${DEV_PHP}" "/var/www/html/test_download.txt"
remove_file "${DEV_PHP}" "/var/www/html/generated"
