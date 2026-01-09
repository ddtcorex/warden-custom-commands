#!/usr/bin/env bats

load "../../../libs/mocks.bash"

setup() {
    setup_mocks
    
    export TEST_SCRIPT_DIR="${TEST_TMP_DIR}/laravel-utils"
    mkdir -p "${TEST_SCRIPT_DIR}"
    cp "${BATS_TEST_DIRNAME}/../../../../env-adapters/laravel/utils.sh" "${TEST_SCRIPT_DIR}/utils.sh"
    
    # Create mock bin directory
    export MOCK_BIN="${TEST_TMP_DIR}/mock-bin"
    mkdir -p "${MOCK_BIN}"
    
    # Mock ssh
    cat > "${MOCK_BIN}/ssh" << 'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"grep"* ]]; then
    # Simulate .env lookup
    if [[ "$*" == *"fail/.env"* ]]; then
        # Return empty for failure case
        exit 0
    fi
    echo "DB_HOST=127.0.0.1"
    echo "DB_PORT=3306"
    echo "DB_DATABASE=laravel_env"
    echo "DB_USERNAME=user"
    echo "DB_PASSWORD=pass"
elif [[ "$*" == *"php -r"* ]]; then
    # Simulate .env.php lookup
    echo "DB_HOST=127.0.0.1"
    echo "DB_PORT=3306"
    echo "DB_DATABASE=laravel_php"
    echo "DB_USERNAME=user_php"
    echo "DB_PASSWORD=pass_php"
else
    echo "Other SSH: $*"
fi
EOF
    chmod +x "${MOCK_BIN}/ssh"
    
    export PATH="${MOCK_BIN}:${PATH}"
    
    # Source the utils file to test functions directly
    # We wrap it in a function to capture output in run
    cat > "${TEST_SCRIPT_DIR}/test_wrapper.sh" << 'EOF'
    source ./utils.sh
    get_remote_db_info "$@"
EOF
    chmod +x "${TEST_SCRIPT_DIR}/test_wrapper.sh"
    
    cd "${TEST_SCRIPT_DIR}"
}

@test "Laravel Utils: Get DB info from .env" {
    # .env lookup success (default behavior of mock ssh)
    run ./test_wrapper.sh "host" "2222" "user" "/var/www"
    
    [[ "$output" == *"DB_DATABASE=laravel_env"* ]]
    [[ "$output" == *"DB_USERNAME=user"* ]]
}

@test "Laravel Utils: Get DB info from .env.php (fallback)" {
    # .env lookup failure (simulated by passing fail.env arg to grep if logic allows)
    # The utils.sh passes "${remote_dir}/.env". I can pass a remote_dir that triggers failure in mock.
    
    run ./test_wrapper.sh "host" "2222" "user" "fail"
    
    # grep should fail (empty output), triggering fallback to php
    [[ "$output" == *"DB_DATABASE=laravel_php"* ]]
    [[ "$output" == *"DB_USERNAME=user_php"* ]]
}
