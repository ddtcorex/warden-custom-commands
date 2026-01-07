#!/usr/bin/env bats

load "../../libs/mocks.bash"

setup() {
    setup_mocks
    
    export WARDEN_ENV_NAME="symfony-test"
    export ENV_SOURCE="local"
    export WARDEN_DIR="/tmp/warden"
    
    export TEST_SCRIPT_DIR="${TEST_TMP_DIR}/symfony-db-dump"
    mkdir -p "${TEST_SCRIPT_DIR}"
    cp "${BATS_TEST_DIRNAME}/../../../env-adapters/symfony/db-dump.cmd" "${TEST_SCRIPT_DIR}/db-dump.cmd"
    chmod +x "${TEST_SCRIPT_DIR}/db-dump.cmd"
    
    BOOTSTRAP_CMD="${TEST_SCRIPT_DIR}/db-dump.cmd"
    
    # Create mock bin directory
    export MOCK_BIN="${TEST_TMP_DIR}/mock-bin"
    mkdir -p "${MOCK_BIN}"
    
    # Create warden mock script
    cat > "${MOCK_BIN}/warden" << 'EOF'
#!/usr/bin/env bash
echo "warden $*" >> "${MOCK_LOG}"
if [[ "$*" == *"printenv MYSQL_USER"* ]]; then
    echo "db_user"
elif [[ "$*" == *"printenv MYSQL_PASSWORD"* ]]; then
    echo "db_pass"
elif [[ "$*" == *"printenv MYSQL_DATABASE"* ]]; then
    echo "symfony_db"
fi
EOF
    chmod +x "${MOCK_BIN}/warden"
    
    cat > "${MOCK_BIN}/date" << 'EOF'
#!/usr/bin/env bash
echo "20230101T120000"
EOF
    chmod +x "${MOCK_BIN}/date"
    
    export PATH="${MOCK_BIN}:${PATH}"
    
    cd "${TEST_SCRIPT_DIR}"
    mkdir -p var
}

@test "Symfony DB Dump: Local dump" {
    run "$BOOTSTRAP_CMD"
    
    grep -q "warden env exec -T db" "$MOCK_LOG"
    [[ "$output" == *"File:"* ]]
}

@test "Symfony DB Dump: Custom filename" {
    run "$BOOTSTRAP_CMD" --file=custom.sql.gz
    
    [[ "$output" == *"custom.sql.gz"* ]]
}
