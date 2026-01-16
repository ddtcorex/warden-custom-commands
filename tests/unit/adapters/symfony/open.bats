#!/usr/bin/env bats

load "../../../libs/mocks.bash"

setup() {
    setup_mocks
    
    export TEST_SCRIPT_DIR="${TEST_TMP_DIR}/symfony-open"
    mkdir -p "${TEST_SCRIPT_DIR}"
    
    cp "${BATS_TEST_DIRNAME}/../../../../env-adapters/symfony/open.cmd" "${TEST_SCRIPT_DIR}/open.cmd"
    cp "${BATS_TEST_DIRNAME}/../../../../env-adapters/symfony/utils.sh" "${TEST_SCRIPT_DIR}/utils.sh"
    
    BOOTSTRAP_CMD="${TEST_SCRIPT_DIR}/open.cmd"
    
    export WARDEN_ENV_NAME="symfony-test"
    export TRAEFIK_SUBDOMAIN="app"
    export TRAEFIK_DOMAIN="test"
    export ENV_SOURCE="local"
    export SSH_OPTS="-o StrictHostKeyChecking=no"
    
    export MOCK_BIN="${TEST_TMP_DIR}/mock-bin"
    mkdir -p "${MOCK_BIN}"
    
    function warden() {
        echo "warden $*" >> "$MOCK_LOG"
        if [[ "$1" == "remote-exec" ]]; then
            shift 4
            echo "warden-remote-exec $*" >> "$MOCK_LOG"
            if [[ "$*" == *"grep"* ]]; then
                 echo "DATABASE_URL=mysql://remote_user:remote_pass@remote-db:3306/remote_db"
            elif [[ "$*" == *"bash"* ]]; then
                 echo "Remote shell opened"
            fi
            return 0
        fi

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
    
    # Mock ssh returning DATABASE_URL for util
    cat > "${MOCK_BIN}/ssh" << 'EOF'
#!/usr/bin/env bash
echo "ssh $*" >> "${MOCK_LOG}"
if [[ "$*" == *"-L"* ]]; then
    echo "Tunnel opened"
fi
EOF
    chmod +x "${MOCK_BIN}/ssh"
    
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

@test "Symfony Open: DB Local" {
    run run_open "db"
    
    [[ "$output" == *"SSH tunnel opened"* ]]
    [[ "$output" == *"mysql://local_user:local_pass@127.0.0.1"* ]]
}

@test "Symfony Open: DB Remote" {
    export ENV_SOURCE="dev"
    export ENV_SOURCE_HOST="example.com"
    export ENV_SOURCE_PORT="22"
    export ENV_SOURCE_USER="user"
    export ENV_SOURCE_DIR="/var/www/html"
    export ENV_SOURCE_HOST_VAR="REMOTE_DEV_HOST"
    
    run run_open "db"
    
    [[ "$output" == *"SSH tunnel opened"* ]]
    [[ "$output" == *"mysql://remote_user:remote_pass@127.0.0.1"* ]]
    
    grep -q "ssh .* -L .*remote-db:3306" "$MOCK_LOG"
}

@test "Symfony Open: Shell Remote" {
    export ENV_SOURCE="dev"
    export ENV_SOURCE_HOST="example.com"
    export ENV_SOURCE_PORT="22"
    export ENV_SOURCE_USER="user"
    export ENV_SOURCE_DIR="/var/www/html"
     export ENV_SOURCE_HOST_VAR="REMOTE_DEV_HOST"
    
    run run_open "shell"
    
    grep -q "warden-remote-exec.*bash" "$MOCK_LOG"
}
