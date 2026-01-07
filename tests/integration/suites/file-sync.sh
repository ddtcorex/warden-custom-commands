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
        wordpress) exclude_path="wp-content/cache" ;;
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

# Test 5: Verify environment config file (env.php, .env, etc) is NOT overwritten if it exists on destination
test_file_sync_config_exclusion() {
    local config_path=""
    case "${TEST_ENV_TYPE}" in
        magento2)  config_path="app/etc/env.php" ;;
        laravel)   config_path=".env" ;;
        symfony)   config_path=".env.local" ;;
        wordpress) config_path="wp-config.php" ;;
    esac

    # Only run if we have a config file to protect for this environment type
    [[ -z "${config_path}" ]] && return 0
    
    local app_root=$(get_app_root)
    
    # Ensure config exists on both source (local) and destination (dev)
    setup_mock_env "${LOCAL_PHP}" "${LOCAL_DB}"
    setup_mock_env "${DEV_PHP}" "${DEV_DB}"
    
    # Modify config files with markers
    modify_config_file "${LOCAL_PHP}" "${app_root}/${config_path}" "MARKER_LOCAL"
    modify_config_file "${DEV_PHP}" "${app_root}/${config_path}" "MARKER_REMOTE"
    
    # 1. Test Upload (should NOT overwrite)
    run_sync_confirmed -s local -d dev --file > /dev/null 2>&1
    local dev_content=$(get_file_content "${DEV_PHP}" "${app_root}/${config_path}")
    
    if [[ "${dev_content}" == *"MARKER_REMOTE"* ]]; then
        pass "Config file upload exclusion (${config_path}) - NOT overwritten"
    else
        fail "Config file upload exclusion (${config_path})" "File WAS overwritten"
    fi

    # 2. Test Download (should NOT overwrite)
    modify_config_file "${LOCAL_PHP}" "${app_root}/${config_path}" "MARKER_LOCAL"
    modify_config_file "${DEV_PHP}" "${app_root}/${config_path}" "MARKER_REMOTE"
    
    run_sync_confirmed -s dev -d local --file > /dev/null 2>&1
    local local_content=$(get_file_content "${LOCAL_PHP}" "${app_root}/${config_path}")
    
    if [[ "${local_content}" == *"MARKER_LOCAL"* ]]; then
        pass "Config file download exclusion (${config_path}) - NOT overwritten"
    else
        fail "Config file download exclusion (${config_path})" "File WAS overwritten"
    fi

    # 3. Test Subdirectory sync (path-aware exclusion)
    local config_dir=$(dirname "${config_path}")
    if [[ "${config_dir}" != "." ]]; then
        modify_config_file "${LOCAL_PHP}" "${app_root}/${config_path}" "MARKER_LOCAL"
        modify_config_file "${DEV_PHP}" "${app_root}/${config_path}" "MARKER_REMOTE"
        
        run_sync_confirmed -s local -d dev --path="${config_dir}" > /dev/null 2>&1
        dev_content=$(get_file_content "${DEV_PHP}" "${app_root}/${config_path}")
        
        if [[ "${dev_content}" == *"MARKER_REMOTE"* ]]; then
            pass "Config file exclusion with --path=${config_dir} - correctly excluded"
        else
            fail "Config file exclusion with --path=${config_dir}" "File WAS overwritten"
        fi
    fi

    # 4. Test "Missing on Destination" (should NOT be excluded)
    # BE CAREFUL: For Laravel, we must NOT delete .env on local, only on destination
    remove_file "${DEV_PHP}" "${app_root}/${config_path}"
    run_sync_confirmed -s local -d dev --file > /dev/null 2>&1
    
    if [[ "${TEST_ENV_TYPE}" == "symfony" ]]; then
        if ! file_exists "${DEV_PHP}" "${app_root}/${config_path}"; then
             pass "Config file sync when missing on destination - correctly excluded (Symfony Strict)"
        else
             fail "Config file sync when missing on destination" "File was synced but should be excluded (Symfony)"
        fi
    else
        if file_exists "${DEV_PHP}" "${app_root}/${config_path}"; then
            pass "Config file sync when missing on destination - correctly uploaded"
        else
            fail "Config file sync when missing on destination" "File was incorrectly excluded"
        fi
    fi
}

# Run tests
test_file_sync_dry_run
test_file_sync_upload
test_file_sync_download
test_file_sync_exclusions
test_file_sync_config_exclusion
