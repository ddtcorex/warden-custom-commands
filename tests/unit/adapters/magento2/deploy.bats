#!/usr/bin/env bats

load "../../../libs/mocks.bash"

setup() {
    setup_mocks
    
    export TEST_SCRIPT_DIR="${TEST_TMP_DIR}/magento2-deploy"
    mkdir -p "${TEST_SCRIPT_DIR}"
    
    # Copy the script to be tested
    cp "${BATS_TEST_DIRNAME}/../../../../env-adapters/magento2/deploy.cmd" "${TEST_SCRIPT_DIR}/deploy.cmd"
    
    # Setup mock bin
    export MOCK_BIN="${TEST_TMP_DIR}/mock-bin"
    rm -rf "${MOCK_BIN}"
    mkdir -p "${MOCK_BIN}"
    export PATH="${MOCK_BIN}:${PATH}"
    
    # Unset exported warden function from mocks.bash so we can use our binary mock
    unset -f warden
    
    # Mock environment variables
    export WARDEN_ENV_PATH="${TEST_SCRIPT_DIR}"
    mkdir -p "${WARDEN_ENV_PATH}/.warden"
}

@test "DeployCmd: Local execution uses warden env exec" {
    export ENV_SOURCE="local"
    export ENV_SOURCE_DEFAULT=0
    
    # Mock warden binary
    cat > "${MOCK_BIN}/warden" << 'EOF'
#!/usr/bin/env bash
echo "warden called args: $@"
EOF
    chmod +x "${MOCK_BIN}/warden"
    
    run "${TEST_SCRIPT_DIR}/deploy.cmd" --only-static
    
    # Verify warden was called for rm -rf
    [[ "$output" == *"warden called args: env exec -T php-fpm rm -rf"* ]]
}

@test "DeployCmd: Remote execution uses ssh with correct quoting" {
    export ENV_SOURCE="dev"
    export ENV_SOURCE_HOST="example.com"
    export ENV_SOURCE_USER="user"
    export ENV_SOURCE_PORT="2222"
    export ENV_SOURCE_DIR="/var/www/html"
    export SSH_OPTS="-o StrictHostKeyChecking=no"
    
    # Mock ssh
    cat > "${MOCK_BIN}/ssh" << 'EOF'
#!/usr/bin/env bash
echo "SSH_ARGS: $@"
EOF
    chmod +x "${MOCK_BIN}/ssh"
    
    run "${TEST_SCRIPT_DIR}/deploy.cmd" --only-static
    
    # We expect `ssh -p 2222 user@example.com ...`
    # The output will contain SSH_ARGS: ...
    
    [[ "$output" == *"SSH_ARGS:"* ]]
    [[ "$output" == *"cd /var/www/html"* || "$output" == *"cd '/var/www/html'"* ]]
    [[ "$output" == *"rm"* ]]
}

@test "DeployCmd: Handles empty ENV_SOURCE_DIR gracefully" {
    export ENV_SOURCE="dev"
    export ENV_SOURCE_HOST="example.com"
    export ENV_SOURCE_USER="user"
    export ENV_SOURCE_PORT="22"
    export ENV_SOURCE_DIR="" # Empty
    export SSH_OPTS="-o StrictHostKeyChecking=no"

    # Mock ssh
    cat > "${MOCK_BIN}/ssh" << 'EOF'
#!/usr/bin/env bash
echo "SSH_ARGS: $@"
EOF
    chmod +x "${MOCK_BIN}/ssh"
    
    run "${TEST_SCRIPT_DIR}/deploy.cmd" --only-static
    
    # Should NOT have "cd" in the command
    [[ "$output" == *"SSH_ARGS:"* ]]
    [[ "$output" != *"cd"* ]]
}

@test "DeployCmd: Detects Modern Magento (>= 2.2) and uses jobs" {
    export ENV_SOURCE="local"
    
    # Mock warden to simulate Magento version 2.4.6
    cat > "${MOCK_BIN}/warden" << 'EOF'
#!/usr/bin/env bash
args="$@"
if [[ "$args" == *"bin/magento --version"* ]]; then
    echo "Magento CLI 2.4.6"
elif [[ "$args" == *"setup:static-content:deploy"* ]]; then
    echo "DEPLOY_CMD: $args"
else
    echo "OTHER: $args"
fi
EOF
    chmod +x "${MOCK_BIN}/warden"

    run "${TEST_SCRIPT_DIR}/deploy.cmd" --only-static
    
    [[ "$output" == *"DEPLOY_CMD: env exec -T php-fpm bin/magento setup:static-content:deploy -f --jobs=4"* ]]
}

@test "DeployCmd: Detects Old Magento (< 2.2) and no jobs" {
    export ENV_SOURCE="local"
    
    # Mock warden to simulate Magento version 2.1.0
    cat > "${MOCK_BIN}/warden" << 'EOF'
#!/usr/bin/env bash
args="$@"
if [[ "$args" == *"bin/magento --version"* ]]; then
    echo "Magento CLI 2.1.0"
elif [[ "$args" == *"setup:static-content:deploy"* ]]; then
    echo "DEPLOY_CMD: $args"
else
    echo "OTHER: $args"
fi
EOF
    chmod +x "${MOCK_BIN}/warden"

    run "${TEST_SCRIPT_DIR}/deploy.cmd" --only-static
    
    # Should warn about jobs not supported
    [[ "$output" == *"Note: --jobs not supported"* ]]
    [[ "$output" == *"DEPLOY_CMD: env exec -T php-fpm bin/magento setup:static-content:deploy -f"* ]]
    [[ "$output" != *"--jobs=4"* ]]
}
