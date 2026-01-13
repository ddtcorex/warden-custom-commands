#!/usr/bin/env bats

load "../../../libs/mocks.bash"

setup() {
    setup_mocks
    
    export WARDEN_ENV_NAME="wordpress-test"
    export ENV_SOURCE="local"
    export WARDEN_DIR="/tmp/warden"
    
    export TEST_SCRIPT_DIR="${TEST_TMP_DIR}/wordpress-db-dump"
    mkdir -p "${TEST_SCRIPT_DIR}"
    cp "${BATS_TEST_DIRNAME}/../../../../env-adapters/wordpress/db-dump.cmd" "${TEST_SCRIPT_DIR}/db-dump.cmd"
    cp "${BATS_TEST_DIRNAME}/../../../../env-adapters/wordpress/utils.sh" "${TEST_SCRIPT_DIR}/utils.sh"
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
    echo "wordpress_db"
elif [[ "$*" == *'echo "MYSQL_USER='* ]]; then
    echo "MYSQL_USER=db_user"
    echo "MYSQL_PASSWORD=db_pass"
    echo "MYSQL_DATABASE=wordpress_db"
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

@test "WordPress DB Dump: Local dump" {
    run "$BOOTSTRAP_CMD"
    
    grep -q "warden env exec -T db" "$MOCK_LOG"
    grep -Fq "\$(command -v mariadb-dump || echo mysqldump)" "$MOCK_LOG"
    [[ "$output" == *"File:"* ]]
}

@test "WordPress DB Dump: Custom filename" {
    run "$BOOTSTRAP_CMD" --file=custom.sql.gz
    
    [[ "$output" == *"custom.sql.gz"* ]]
}
