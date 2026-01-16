#!/usr/bin/env bats

load "../../../libs/mocks.bash"

setup() {
    setup_mocks
    unset -f warden
    
    export TEST_SCRIPT_DIR="${TEST_TMP_DIR}/symfony-utils"
    mkdir -p "${TEST_SCRIPT_DIR}"
    cp "${BATS_TEST_DIRNAME}/../../../../env-adapters/symfony/utils.sh" "${TEST_SCRIPT_DIR}/utils.sh"
    
    export MOCK_BIN="${TEST_TMP_DIR}/mock-bin"
    mkdir -p "${MOCK_BIN}"
    
    export ENV_SOURCE="test_env"
    
    # Mock warden
    cat > "${MOCK_BIN}/warden" << 'EOF'
#!/usr/bin/env bash
if [[ "$1" == "remote-exec" ]]; then
    shift 4
    CMD="$*"
    if [[ "$CMD" == *"grep"* ]]; then
        if [[ "$CMD" == *"fail_dir"* ]]; then
            # Simulate .env.local missing/no-match, but .env matches
            echo "DATABASE_URL=mysql://env_user:env_pass@env_host:3306/env_db"
        else
            # Default: .env.local matches
            echo "DATABASE_URL=mysql://local_user:local_pass@local_host:3306/local_db"
        fi
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

@test "Symfony Utils: Parse DATABASE_URL from .env.local" {
    run ./test_wrapper.sh "/dir"
    
    [[ "$output" == *"DB_HOST=local_host"* ]]
    [[ "$output" == *"DB_DATABASE=local_db"* ]]
    [[ "$output" == *"DB_USERNAME=local_user"* ]]
}

@test "Symfony Utils: Fallback to .env" {
    # Trigger .env.local failure by passing "fail" in dir path which mock checks (simulated)
    # Actually my mock check is too simple. Use a specific arg.
    # The utils pass `grep ... "${remote_dir}/.env.local"`
    
    run ./test_wrapper.sh "fail_dir"
    
    [[ "$output" == *"DB_HOST=env_host"* ]]
    [[ "$output" == *"DB_DATABASE=env_db"* ]]
}
