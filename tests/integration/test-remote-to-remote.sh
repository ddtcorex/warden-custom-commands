#!/usr/bin/env bash
header "Remote-to-Remote (R2R) Sync Tests"

# 1. R2R File Sync (General & Path)
test_r2r_file_sync() {
    local web_root="$(get_web_root)"
    # Use pub/media/tmp as it is more likely to exist/be usable across frameworks than var/log
    # and we know pub/media exists from other tests
    local media_path="$(get_media_path)"
    local test_dir="/var/www/html/${media_path}/tmp"
    
    # Ensure directory exists on both
    docker exec --workdir / "${DEV_PHP}" mkdir -p "${test_dir}"
    docker exec --workdir / "${STAGING_PHP}" mkdir -p "${test_dir}"
    
    # Clean setup
    create_test_file "${DEV_PHP}" "${test_dir}/r2r_sync.log" "r2r data"
    create_test_file "${DEV_PHP}" "${test_dir}/r2r_exclude.txt" "should exclude"
    remove_file "${STAGING_PHP}" "${test_dir}/r2r_sync.log"
    remove_file "${STAGING_PHP}" "${test_dir}/r2r_exclude.txt"
    create_test_file "${STAGING_PHP}" "${test_dir}/r2r_stale.log" "stale data"
    
    # We will exclude *.txt via argument or rely on default excludes if possible, 
    # but for generic test lets assume we want to sync a specific path
    
    # Test --path sync with --delete
    # We explicitly exclude .txt files to test exclusion injection if possible, 
    # but run_sync_confirmed doesn't easily take extra rsync flags directly without modifying common code.
    # Instead, we'll rely on basic file sync first.

    # 1. Basic Path Sync
    # Note: For R2R, the --path argument should be relative to project root
    local rel_path="${media_path}/tmp"
    local output
    output=$(run_sync_confirmed -s dev -d staging --path="${rel_path}" 2>&1) || true
    
    if file_exists "${STAGING_PHP}" "${test_dir}/r2r_sync.log"; then 
        pass "R2R file sync (--path) - file transferred"
    else 
        fail "R2R file sync (--path)" "File not found on staging. Output: ${output}"
    fi

    # 2. Test --delete (Stale file should be removed)
    output=$(run_sync_confirmed -s dev -d staging --path="${rel_path}" --delete 2>&1) || true
    
    if ! file_exists "${STAGING_PHP}" "${test_dir}/r2r_stale.log"; then
        pass "R2R file sync (--delete) - stale file removed"
    else
        fail "R2R file sync (--delete)" "Stale file WAS NOT removed"
    fi
}
test_r2r_file_sync

# 2. R2R Config Exclusion Protection
test_r2r_config_protection() {
    local config_path=""
    case "${TEST_ENV_TYPE}" in
        magento2)  config_path="app/etc/env.php" ;;
        laravel)   config_path=".env" ;;
        symfony)   config_path=".env.local" ;;
        wordpress) config_path="wp-config.php" ;;
    esac
    
    # Skip if no config define
    [[ -z "${config_path}" ]] && return 0
    
    local app_root=$(get_app_root)
    
    # Ensure config exists on both
    setup_mock_env "${DEV_PHP}" "${DEV_DB}"
    setup_mock_env "${STAGING_PHP}" "${STAGING_DB}"
    
    # Setup: Different configs on Dev and Staging
    modify_config_file "${DEV_PHP}" "${app_root}/${config_path}" "CONFIG_FROM_DEV"
    modify_config_file "${STAGING_PHP}" "${app_root}/${config_path}" "CONFIG_ON_STAGING_ORIGINAL"
    
    # Sync from Dev to Staging (Files)
    run_sync_confirmed -s dev -d staging --file > /dev/null 2>&1
    
    local content=$(get_file_content "${STAGING_PHP}" "${app_root}/${config_path}")
    
    if [[ "${content}" == *"CONFIG_ON_STAGING_ORIGINAL"* ]]; then
         pass "R2R Config Protection - Config NOT overwritten"
    else
         fail "R2R Config Protection" "Config WAS overwritten by source"
    fi
}
test_r2r_config_protection

# 3. R2R Media Sync
test_r2r_media_sync() {
    local media_path="$(get_media_path)"
    local full_media_path="/var/www/html/${media_path}"
    
    # Setup
    create_test_file "${DEV_PHP}" "${full_media_path}/r2r_image.jpg" "IMAGE_DATA"
    remove_file "${STAGING_PHP}" "${full_media_path}/r2r_image.jpg"
    
    # Sync Media
    run_sync_confirmed -s dev -d staging --media > /dev/null 2>&1
    
    if file_exists "${STAGING_PHP}" "${full_media_path}/r2r_image.jpg"; then
        pass "R2R Media Sync - Media file transferred"
    else
        fail "R2R Media Sync" "Media file not found on destination"
    fi
}
test_r2r_media_sync

# 4. R2R Database Sync
test_r2r_db_sync() {
    run_db_query "${DEV_PHP}" "DROP TABLE IF EXISTS test_r2r_db;"
    run_db_query "${DEV_PHP}" "CREATE TABLE test_r2r_db (id INT, val VARCHAR(255));"
    run_db_query "${DEV_PHP}" "INSERT INTO test_r2r_db VALUES (1, 'r2r-db-data');"
    setup_mock_env "${DEV_PHP}" "${DEV_DB}"
    setup_mock_env "${STAGING_PHP}" "${STAGING_DB}"
    
    run_db_query "${STAGING_PHP}" "DROP TABLE IF EXISTS test_r2r_db;"
    
    # Verify data exists on source first
    local src_result=$(run_db_query "${DEV_PHP}" "SELECT val FROM test_r2r_db WHERE id=1;" 2>&1)
    if [[ "${src_result}" != *"r2r-db-data"* ]]; then
        fail "R2R DB sync" "Setup failed - data missing on source (Dev). Result: ${src_result}"
        return 1
    fi
    
    local output
    output=$(run_sync_confirmed -s dev -d staging --db 2>&1) || true
    
    local result
    result=$(run_db_query "${STAGING_PHP}" "SELECT val FROM test_r2r_db WHERE id=1;" 2>&1 | grep "r2r-db-data" | head -n 1)
    
    if [[ "${result}" == *"r2r-db-data"* ]]; then
        pass "R2R DB sync - data transferred correctly"
    else
        fail "R2R DB sync" "Verification failed. Result: ${result}. Output: ${output}"
    fi
}
test_r2r_db_sync
