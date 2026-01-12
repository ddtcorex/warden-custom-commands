#!/usr/bin/env bats

load "../../../libs/mocks.bash"

setup() {
    setup_mocks
    
    export TEST_SCRIPT_DIR="${TEST_TMP_DIR}/magento2-open"
    mkdir -p "${TEST_SCRIPT_DIR}"
    
    cp "${BATS_TEST_DIRNAME}/../../../../env-adapters/magento2/open.cmd" "${TEST_SCRIPT_DIR}/open.cmd"
    cp "${BATS_TEST_DIRNAME}/../../../../env-adapters/magento2/utils.sh" "${TEST_SCRIPT_DIR}/utils.sh"
    
    BOOTSTRAP_CMD="${TEST_SCRIPT_DIR}/open.cmd"
    
    export WARDEN_ENV_NAME="magento2-test"
    export TRAEFIK_SUBDOMAIN="app"
    export TRAEFIK_DOMAIN="test"
    export ENV_SOURCE="local"
    export SSH_OPTS="-o StrictHostKeyChecking=no"
    
    export MOCK_BIN="${TEST_TMP_DIR}/mock-bin"
    mkdir -p "${MOCK_BIN}"
    
    function warden() {
        echo "warden $*" >> "$MOCK_LOG"
        if [[ "$*" == *"printenv MYSQL_USER"* ]]; then
            echo "local_user"
        elif [[ "$*" == *"printenv MYSQL_PASSWORD"* ]]; then
            echo "local_pass"
        elif [[ "$*" == *"printenv MYSQL_DATABASE"* ]]; then
            echo "local_db"
        elif [[ "$*" == "shell" ]]; then
            echo "Entering shell"
        fi
    }
    export -f warden

    cat > "${MOCK_BIN}/lsof" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
    chmod +x "${MOCK_BIN}/lsof"
    
    # Mock ssh returning base64 for util
    cat > "${MOCK_BIN}/ssh" << 'EOF'
#!/usr/bin/env bash
echo "ssh $*" >> "${MOCK_LOG}"
if [[ "$*" == *"-L"* ]]; then
    echo "Tunnel opened"
elif [[ "$*" == *"php -r"* ]] && [[ "$*" == *"json_encode"* ]]; then
    echo "eyJob3N0IjoicmVtb3RlLWRiOjMzMDYiLCJ1c2VybmFtZSI6InJlbW90ZV91c2VyIiwicGFzc3dvcmQiOiJyZW1vdGVfcGFzcyIsImRibmFtZSI6InJlbW90ZV9kYiJ9"
elif [[ "$*" == *"php -r"* ]]; then
    echo "admin"
else
    entry="$*"
    if [[ "$entry" =~ "cd /var/www/html" ]]; then
        echo "Remote shell opened"
    fi
fi
EOF
    chmod +x "${MOCK_BIN}/ssh"
    
     # Mock php to decode (local)
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

    cat > "${MOCK_BIN}/xdg-open" << 'EOF'
#!/usr/bin/env bash
echo "xdg-open $*" >> "${MOCK_LOG}"
EOF
    chmod +x "${MOCK_BIN}/xdg-open"

    export PATH="${MOCK_BIN}:${PATH}"
    
    cd "${TEST_SCRIPT_DIR}"
}

run_open() {
    export WARDEN_PARAMS=("$1")
    shift
    source "$BOOTSTRAP_CMD" "$@"
}

@test "Magento2 Open: DB Local" {
    run run_open "db"
    
    [[ "$output" == *"SSH tunnel opened"* ]]
    [[ "$output" == *"mysql://local_user:local_pass@127.0.0.1"* ]]
}

@test "Magento2 Open: DB Remote" {
    export ENV_SOURCE="dev"
    export ENV_SOURCE_HOST="example.com"
    export ENV_SOURCE_PORT="22"
    export ENV_SOURCE_USER="user"
    export ENV_SOURCE_DIR="/var/www/html"
    export ENV_SOURCE_HOST_VAR="REMOTE_DEV_HOST"
    export REMOTE_DEV_HOST="dummy"
    
    run run_open "db"
    
    [[ "$output" == *"SSH tunnel opened"* ]]
    [[ "$output" == *"mysql://remote_user:remote_pass@127.0.0.1"* ]]
    
    grep -q "ssh .* -L .*remote-db:3306" "$MOCK_LOG"
}

@test "Magento2 Open: Shell Remote" {
    export ENV_SOURCE="dev"
    export ENV_SOURCE_HOST="example.com"
    export ENV_SOURCE_PORT="22"
    export ENV_SOURCE_USER="user"
    export ENV_SOURCE_DIR="/var/www/html"
     export ENV_SOURCE_HOST_VAR="REMOTE_DEV_HOST"
     export REMOTE_DEV_HOST="dummy"
    
    run run_open "shell"
    
    grep -q "ssh .* -t -p 22 user@example.com .* bash" "$MOCK_LOG"
}
