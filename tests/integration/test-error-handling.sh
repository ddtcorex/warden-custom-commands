#!/usr/bin/env bash

header "Error Handling Tests"

# Test 1: Invalid Source Environment
echo "Testing invalid source environment..."
OUTPUT=$(run_sync -s non_existent_env 2>&1 || true)
if echo "${OUTPUT}" | grep -q "Environment details not found"; then
    pass "Invalid source environment check"
else
    fail "Invalid source environment check" "Expected error message not found. Output: ${OUTPUT}"
fi

# Test 2: Invalid Destination Environment
echo "Testing invalid destination environment..."
OUTPUT=$(run_sync -d non_existent_env 2>&1 || true)
if echo "${OUTPUT}" | grep -q "environment details not found"; then
    pass "Invalid destination environment check"
else
    fail "Invalid destination environment check" "Expected error message not found. Output: ${OUTPUT}"
fi

# Test 3: Source == Destination
echo "Testing identical source and destination..."
OUTPUT=$(run_sync -s dev -d dev 2>&1 || true)
if echo "${OUTPUT}" | grep -q "Source and destination environments cannot be the same"; then
    pass "Identical source/destination check"
else
    fail "Identical source/destination check" "Expected error message not found. Output: ${OUTPUT}"
fi

# Test 4: Missing Source Details (Mock if possible or rely on previous check)
# The invalid source check covers this mostly.
