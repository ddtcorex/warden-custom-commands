#!/usr/bin/env bats

load "../../../libs/mocks.bash"

setup() {
    setup_mocks
    unset -f warden
    export WARDEN_DIR="${TEST_TMP_DIR}"
    
    export TEST_SCRIPT_DIR="${TEST_TMP_DIR}/magento1-utils"
    mkdir -p "${TEST_SCRIPT_DIR}"
    cp "${BATS_TEST_DIRNAME}/../../../../env-adapters/magento1/utils.sh" "${TEST_SCRIPT_DIR}/utils.sh"
    
    export MOCK_BIN="${TEST_TMP_DIR}/mock-bin"
    mkdir -p "${MOCK_BIN}"
    
    # Mock ssh
    cat > "${MOCK_BIN}/ssh" << 'EOF'
#!/usr/bin/env bash
    # Return base64 json for db info
    echo "eyJob3N0IjoicmVtb3RlLWRiOjMzMDYiLCJ1c2VybmFtZSI6InJlbW90ZV91c2VyIiwicGFzc3dvcmQiOiJyZW1vdGVfcGFzcyIsImRibmFtZSI6InJlbW90ZV9kYiJ9"
    exit 0
EOF
    chmod +x "${MOCK_BIN}/ssh"
    
    cat > "${MOCK_BIN}/warden" << 'EOF'
#!/usr/bin/env bash
echo "warden $*"
EOF
    chmod +x "${MOCK_BIN}/warden"
    
    # Mock php to decode
    cat > "${MOCK_BIN}/php" << 'EOF'
#!/usr/bin/env bash
code="$2"
if echo "$code" | grep -q "3306"; then
    echo "3306"
elif echo "$code" | grep -q "host"; then
    echo "remote-db"
elif echo "$code" | grep -q "dbname"; then
    echo "remote_db"
elif echo "$code" | grep -q "username"; then
    echo "remote_user"
elif echo "$code" | grep -q "password"; then
    echo "remote_pass"
fi
EOF
    chmod +x "${MOCK_BIN}/php"
    
    export PATH="${MOCK_BIN}:${PATH}"
    
    cat > "${TEST_SCRIPT_DIR}/test_wrapper.sh" << 'EOF'
    # Mock normalize_env_name to match real implementation (dots to underscores)
    function normalize_env_name() { echo "${1^^}" | tr '.' '_'; }
    export -f normalize_env_name
    
    export REMOTE_REMOTE_EXAMPLE_COM_HOST="remote.example.com"
    export REMOTE_REMOTE_EXAMPLE_COM_PORT="22"
    export REMOTE_REMOTE_EXAMPLE_COM_USER="user"
    
    source ./utils.sh
    get_remote_db_info "$@"
EOF
    chmod +x "${TEST_SCRIPT_DIR}/test_wrapper.sh"
    
    cd "${TEST_SCRIPT_DIR}"
}

@test "Magento1 Utils: Get DB info decoding from local.xml" {
    run ./test_wrapper.sh "remote.example.com" "22" "user" "/var/www"
    
    [[ "$output" == *"DB_HOST=remote-db"* ]]
    [[ "$output" == *"DB_PORT=3306"* ]]
    [[ "$output" == *"DB_DATABASE=remote_db"* ]]
}
