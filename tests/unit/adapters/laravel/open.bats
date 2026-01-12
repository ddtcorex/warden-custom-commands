#!/usr/bin/env bats

load "../../../libs/mocks.bash"

setup() {
    setup_mocks
    
    export TEST_SCRIPT_DIR="${TEST_TMP_DIR}/laravel-open"
    mkdir -p "${TEST_SCRIPT_DIR}"
    
    # Copy script and utils
    cp "${BATS_TEST_DIRNAME}/../../../../env-adapters/laravel/open.cmd" "${TEST_SCRIPT_DIR}/open.cmd"
    cp "${BATS_TEST_DIRNAME}/../../../../env-adapters/laravel/utils.sh" "${TEST_SCRIPT_DIR}/utils.sh"
    
    BOOTSTRAP_CMD="${TEST_SCRIPT_DIR}/open.cmd"
    
    # Mock environment variables
    export WARDEN_ENV_NAME="laravel-test"
    export TRAEFIK_SUBDOMAIN="app"
    export TRAEFIK_DOMAIN="test"
    export ENV_SOURCE="local"
    export SSH_OPTS="-o StrictHostKeyChecking=no"
    
    # Custom Mocks
    export MOCK_BIN="${TEST_TMP_DIR}/mock-bin"
    mkdir -p "${MOCK_BIN}"
    
    # Override warden function
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

    # Mock lsof
    cat > "${MOCK_BIN}/lsof" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
    chmod +x "${MOCK_BIN}/lsof"
    
    # Mock ssh
    cat > "${MOCK_BIN}/ssh" << 'EOF'
#!/usr/bin/env bash
echo "ssh $*" >> "${MOCK_LOG}"
if [[ "$*" == *"-L"* ]]; then
    echo "Tunnel opened"
elif [[ "$*" == *"grep"* ]]; then
    echo "DB_HOST=10.0.0.1"
    echo "DB_PORT=3306"
    echo "DB_DATABASE=remote_db"
    echo "DB_USERNAME=remote_user"
    echo "DB_PASSWORD=remote_pass"
else
    entry="$*"
    if [[ "$entry" =~ "cd /var/www/html" ]]; then
        echo "Remote shell opened"
    fi
fi
EOF
    chmod +x "${MOCK_BIN}/ssh"
    
    # Mock xdg-open for linux
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

@test "Laravel Open: DB Local" {
    run run_open "db"
    
    [[ "$output" == *"SSH tunnel opened"* ]]
    [[ "$output" == *"mysql://local_user:local_pass@127.0.0.1"* ]]
    
    grep -q "warden env exec -T db printenv MYSQL_USER" "$MOCK_LOG"
}

@test "Laravel Open: DB Remote" {
    export ENV_SOURCE="dev"
    export ENV_SOURCE_HOST="example.com"
    export ENV_SOURCE_PORT="22"
    export ENV_SOURCE_USER="user"
    export ENV_SOURCE_DIR="/var/www/html"
    
    run run_open "db"
    
    [[ "$output" == *"SSH tunnel opened"* ]]
    [[ "$output" == *"mysql://remote_user:remote_pass@127.0.0.1"* ]]
    
    grep -q "ssh .* -L .*10.0.0.1:3306" "$MOCK_LOG"
}

@test "Laravel Open: Shell Local" {
    run run_open "shell"
    
    grep -q "warden shell" "$MOCK_LOG"
}

@test "Laravel Open: Shell Remote" {
    export ENV_SOURCE="dev"
    export ENV_SOURCE_HOST="example.com"
    export ENV_SOURCE_PORT="22"
    export ENV_SOURCE_USER="user"
    export ENV_SOURCE_DIR="/var/www/html"
    
    run run_open "shell"
    
    grep -q "ssh .* -t -p 22 user@example.com .* bash" "$MOCK_LOG"
}

@test "Laravel Open: Admin Local (HTTPS)" {
    # Pass -a flag to trigger open_link
    run run_open "admin" "-a"
    
    [[ "$output" == *"https://app.test/"* ]]
    grep -q "xdg-open https://app.test/" "$MOCK_LOG"
}
