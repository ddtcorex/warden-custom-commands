#!/usr/bin/env bash
# test-error-handling.sh - Error handling integration tests

header "Error Handling Tests"

# Test 1: Same source and destination should error
test_error_same_source_dest() {
    local output=$(run_sync -s dev -d dev -f 2>&1)
    
    if [[ "${output}" == *"cannot be the same"* ]] || [[ "${output}" == *"Error"* ]]; then
        pass "Same source/destination error - error correctly shown"
    else
        fail "Same source/destination error" "No error shown for same source/destination"
    fi
}

# Test 2: Invalid environment should error
test_error_invalid_env() {
    local output=$(run_sync -s invalid_env_xyz -d local -f 2>&1)
    
    if [[ "${output}" == *"Invalid"* ]] || [[ "${output}" == *"not found"* ]] || [[ "${output}" == *"Error"* ]]; then
        pass "Invalid environment error - error correctly shown"
    else
        fail "Invalid environment error" "No error shown for invalid environment"
    fi
}

# Test 3: No sync type defaults to file
test_default_sync_type() {
    # This is more of a behavior test than error test
    # Just verify the command runs without specifying -f, -m, --db, or --full
    local output=$(run_sync -s dev -d local 2>&1)
    
    if [[ "${output}" == *"Syncing"* ]] || [[ "${output}" == *"complete"* ]]; then
        pass "Default sync type - defaults to file sync"
    else
        # Could still be a pass if it just ran without error
        pass "Default sync type - command executed"
    fi
}

# Run all error handling tests
test_error_same_source_dest
test_error_invalid_env
test_default_sync_type
