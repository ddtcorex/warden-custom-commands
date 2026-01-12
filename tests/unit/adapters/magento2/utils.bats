#!/usr/bin/env bats

load "../../../libs/mocks.bash"

setup() {
    setup_mocks
    
    export TEST_SCRIPT_DIR="${TEST_TMP_DIR}/magento2-utils"
    mkdir -p "${TEST_SCRIPT_DIR}"
    cp "${BATS_TEST_DIRNAME}/../../../../env-adapters/magento2/utils.sh" "${TEST_SCRIPT_DIR}/utils.sh"
    
    export MOCK_BIN="${TEST_TMP_DIR}/mock-bin"
    mkdir -p "${MOCK_BIN}"
    
    # Mock ssh to return a base64 encoded json
    cat > "${MOCK_BIN}/ssh" << 'EOF'
#!/usr/bin/env bash
# Return valid base64 json: {"host":"remote-db:3306","username":"remote_user","password":"remote_pass","dbname":"remote_db"}
# Base64: eyJob3N0IjoicmVtb3RlLWRiOjMzMDYiLCJ1c2VybmFtZSI6InJlbW90ZV91c2VyIiwicGFzc3dvcmQiOiJyZW1vdGVfcGFzcyIsImRibmFtZSI6InJlbW90ZV9kYiJ9
echo "eyJob3N0IjoicmVtb3RlLWRiOjMzMDYiLCJ1c2VybmFtZSI6InJlbW90ZV91c2VyIiwicGFzc3dvcmQiOiJyZW1vdGVfcGFzcyIsImRibmFtZSI6InJlbW90ZV9kYiJ9"
EOF
    chmod +x "${MOCK_BIN}/ssh"
    
    # Mock php to decode
    cat > "${MOCK_BIN}/php" << 'EOF'
#!/usr/bin/env bash
# The script calls: php -r CODE -- ARGS
# $1 = -r
# $2 = code
# $3 = --
# $4 = json_base64

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
    source ./utils.sh
    get_remote_db_info "$@"
EOF
    chmod +x "${TEST_SCRIPT_DIR}/test_wrapper.sh"
    
    cd "${TEST_SCRIPT_DIR}"
}

@test "Magento2 Utils: Get DB info decoding" {
    run ./test_wrapper.sh "host" "2222" "user" "/var/www"
    
    [[ "$output" == *"DB_HOST=remote-db"* ]]
    [[ "$output" == *"DB_PORT=3306"* ]]
    [[ "$output" == *"DB_DATABASE=remote_db"* ]]
}
