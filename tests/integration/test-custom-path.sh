#!/usr/bin/env bash
# test-custom-path.sh - Custom path sync integration tests

header "Custom Path Sync Tests"

# Test 1: Sync specific directory
test_custom_path_sync() {
    create_test_file "${LOCAL_PHP}" "/var/www/html/app/code/Vendor/Module/test.php" "custom path test"
    remove_file "${DEV_PHP}" "/var/www/html/app/code/Vendor/Module/test.php"
    
    run_sync_confirmed -s local -d dev -p app/code/Vendor/Module > /dev/null 2>&1
    
    if file_exists "${DEV_PHP}" "/var/www/html/app/code/Vendor/Module/test.php"; then
        pass "Custom path sync - specific directory synced"
    else
        fail "Custom path sync" "Directory was not synced"
    fi
}

# Test 2: Path with trailing slash is normalized
test_custom_path_trailing_slash() {
    create_test_file "${LOCAL_PHP}" "/var/www/html/app/design/test_theme/file.xml" "theme file"
    remove_file "${DEV_PHP}" "/var/www/html/app/design/test_theme"
    
    # Use trailing slash - should be normalized
    run_sync_confirmed -s local -d dev -p "app/design/test_theme/" > /dev/null 2>&1
    
    if file_exists "${DEV_PHP}" "/var/www/html/app/design/test_theme/file.xml"; then
        pass "Custom path trailing slash - normalized correctly"
    else
        fail "Custom path trailing slash" "Path with trailing slash not handled correctly"
    fi
}

# Test 3: Custom path download
test_custom_path_download() {
    create_test_file "${DEV_PHP}" "/var/www/html/var/log/test.log" "log content"
    remove_file "${LOCAL_PHP}" "/var/www/html/var/log/test.log"
    
    run_sync -s dev -d local -p var/log > /dev/null 2>&1
    
    if file_exists "${LOCAL_PHP}" "/var/www/html/var/log/test.log"; then
        pass "Custom path download - directory downloaded"
    else
        fail "Custom path download" "Directory was not downloaded"
    fi
}

# Run all custom path tests
test_custom_path_sync
test_custom_path_trailing_slash
test_custom_path_download

# Cleanup
remove_file "${LOCAL_PHP}" "/var/www/html/app/code/Vendor"
remove_file "${LOCAL_PHP}" "/var/www/html/app/design/test_theme"
remove_file "${LOCAL_PHP}" "/var/www/html/var/log/test.log"
remove_file "${DEV_PHP}" "/var/www/html/app/code/Vendor"
remove_file "${DEV_PHP}" "/var/www/html/app/design/test_theme"
remove_file "${DEV_PHP}" "/var/www/html/var/log"
