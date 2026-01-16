#!/usr/bin/env bats

load "../../../libs/mocks.bash"

setup() {
    setup_mocks
    unset -f warden
    
    export TEST_SCRIPT_DIR="${TEST_TMP_DIR}/wordpress-utils"
    mkdir -p "${TEST_SCRIPT_DIR}"
    cp "${BATS_TEST_DIRNAME}/../../../../env-adapters/wordpress/utils.sh" "${TEST_SCRIPT_DIR}/utils.sh"
    
    export MOCK_BIN="${TEST_TMP_DIR}/mock-bin"
    mkdir -p "${MOCK_BIN}"
    
    # Mock warden
    cat > "${MOCK_BIN}/warden" << 'EOF'
#!/usr/bin/env bash
if [[ "$1" == "remote-exec" ]]; then
    shift 4
    CMD="$*"
    if [[ "$CMD" == *"grep"* ]]; then
        # Return simulated wp-config.php content
        echo "define( 'DB_NAME', 'wp_db' );"
        echo "define( 'DB_USER', 'wp_user' );"
        echo "define( 'DB_PASSWORD', 'wp_pass' );"
        echo "define( 'DB_HOST', 'wp_host:3306' );"
    fi
    exit 0
fi
echo "warden $*"
EOF
    chmod +x "${MOCK_BIN}/warden"
    
    export PATH="${MOCK_BIN}:${PATH}"
    
    cat > "${TEST_SCRIPT_DIR}/test_wrapper.sh" << 'EOF'
    source ./utils.sh
    get_remote_db_info "$@"
EOF
    chmod +x "${TEST_SCRIPT_DIR}/test_wrapper.sh"
    
    cd "${TEST_SCRIPT_DIR}"
}

@test "WordPress Utils: Parse wp-config.php" {
    run ./test_wrapper.sh "/dir"
    
    [[ "$output" == *"DB_HOST=wp_host"* ]]
    [[ "$output" == *"DB_PORT=3306"* ]]
    [[ "$output" == *"DB_DATABASE=wp_db"* ]]
    [[ "$output" == *"DB_USERNAME=wp_user"* ]]
}
