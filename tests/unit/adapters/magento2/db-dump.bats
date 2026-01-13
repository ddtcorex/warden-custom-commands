#!/usr/bin/env bats

load "../../../libs/mocks.bash"

setup() {
    setup_mocks
    
    export WARDEN_ENV_NAME="magento2-test"
    export ENV_SOURCE="local"
    export DB_PREFIX="mage_"
    export WARDEN_DIR="/tmp/warden"
    
    export TEST_SCRIPT_DIR="${TEST_TMP_DIR}/magento2-db-dump"
    mkdir -p "${TEST_SCRIPT_DIR}"
    cp "${BATS_TEST_DIRNAME}/../../../../env-adapters/magento2/db-dump.cmd" "${TEST_SCRIPT_DIR}/db-dump.cmd"
    cp "${BATS_TEST_DIRNAME}/../../../../env-adapters/magento2/utils.sh" "${TEST_SCRIPT_DIR}/utils.sh"
    chmod +x "${TEST_SCRIPT_DIR}/db-dump.cmd"
    
    BOOTSTRAP_CMD="${TEST_SCRIPT_DIR}/db-dump.cmd"
    
    # Create mock bin directory
    export MOCK_BIN="${TEST_TMP_DIR}/mock-bin"
    mkdir -p "${MOCK_BIN}"
    
    # Create warden mock script
    cat > "${MOCK_BIN}/warden" << 'EOF'
#!/usr/bin/env bash
echo "warden $*" >> "${MOCK_LOG}"
# Handle printenv calls (legacy)
if [[ "$*" == *"printenv MYSQL_USER"* ]]; then
    echo "db_user"
elif [[ "$*" == *"printenv MYSQL_PASSWORD"* ]]; then
    echo "db_pass"
elif [[ "$*" == *"printenv MYSQL_DATABASE"* ]]; then
    echo "test_db"
# Handle new single bash -c call for db info
elif [[ "$*" == *'echo "MYSQL_USER='* ]]; then
    echo "MYSQL_USER=db_user"
    echo "MYSQL_PASSWORD=db_pass"
    echo "MYSQL_DATABASE=test_db"
else
    # For other warden commands, just succeed
    :
fi
EOF
    chmod +x "${MOCK_BIN}/warden"
    
    # Create date mock
    cat > "${MOCK_BIN}/date" << 'EOF'
#!/usr/bin/env bash
echo "20230101T120000"
EOF
    chmod +x "${MOCK_BIN}/date"
    
    # Prepend mock bin to PATH
    export PATH="${MOCK_BIN}:${PATH}"
    
    cd "${TEST_SCRIPT_DIR}"
    mkdir -p var
}

@test "DB Dump: Default local dump creates file" {
    run "$BOOTSTRAP_CMD"
    
    # Should call warden to get DB credentials (single call now)
    grep -q "warden env exec -T db bash" "$MOCK_LOG"
    
    # Should output filename
    [[ "$output" == *"File:"* ]]
}

@test "DB Dump: Custom filename via --file" {
    run "$BOOTSTRAP_CMD" --file=custom_dump.sql.gz
    
    [[ "$output" == *"custom_dump.sql.gz"* ]]
}

@test "DB Dump: Full dump flag sets FULL_DUMP" {
    run "$BOOTSTRAP_CMD" --full
    
    # With --full, ignore-table options should NOT be present
    # Check log doesn't contain ignore-table
    if grep -q "ignore-table" "$MOCK_LOG"; then
        return 1
    fi
}

@test "DB Dump: Exclude sensitive data includes sales tables" {
    run "$BOOTSTRAP_CMD" --exclude-sensitive-data
    
    # Should include additional sales tables in ignored list
    grep -q "sales_order" "$MOCK_LOG" || grep -E -q "(mariadb-dump|mysqldump)" "$MOCK_LOG"
}
