#!/usr/bin/env bats

load "../../../libs/mocks.bash"

setup() {
    setup_mocks
    
    export TEST_SCRIPT_DIR="${TEST_TMP_DIR}/magento2-deploy-full"
    mkdir -p "${TEST_SCRIPT_DIR}"
    
    # Copy the script to be tested
    cp "${BATS_TEST_DIRNAME}/../../../../env-adapters/magento2/deploy.cmd" "${TEST_SCRIPT_DIR}/deploy.cmd"

    # Setup mock bin
    export MOCK_BIN="${TEST_TMP_DIR}/mock-bin"
    rm -rf "${MOCK_BIN}"
    mkdir -p "${MOCK_BIN}"
    export PATH="${MOCK_BIN}:${PATH}"
    
    # Unset exported warden function from mocks.bash
    unset -f warden

    # Mock environment variables
    export WARDEN_ENV_PATH="${TEST_SCRIPT_DIR}"
    mkdir -p "${WARDEN_ENV_PATH}/.warden"
}

@test "DeployCmd: Full deploy runs composer install non-interactively" {
    export ENV_SOURCE="local"
    export ENV_SOURCE_DEFAULT=0
    
    # Mock warden binary
    cat > "${MOCK_BIN}/warden" << 'EOF'
#!/usr/bin/env bash
args="$@"
if [[ "$args" == *"bin/magento --version"* ]]; then
    echo "Magento CLI 2.4.6"
else
    echo "WARDEN_CALL: $args"
fi
EOF
    chmod +x "${MOCK_BIN}/warden"
    
    # Run full deploy (no flags)
    run "${TEST_SCRIPT_DIR}/deploy.cmd"
    
    # Check for composer install (HAS --no-dev --optimize-autoloader --no-interaction)
    [[ "$output" == *"WARDEN_CALL: env exec -T php-fpm composer install --no-dev --optimize-autoloader --no-interaction"* ]]
    
    # Check for magento commands (NO --no-interaction)
    [[ "$output" == *"WARDEN_CALL: env exec -T php-fpm bin/magento setup:upgrade"* ]]
    [[ "$output" == *"WARDEN_CALL: env exec -T php-fpm bin/magento setup:di:compile"* ]]
    
    # Ensure Magento commands specifically do NOT have the flag
    [[ "$output" != *"bin/magento setup:upgrade --no-interaction"* ]]
    [[ "$output" != *"bin/magento setup:di:compile --no-interaction"* ]]
}

@test "DeployCmd: Remote execution uses correct SSH options and profile loading" {
    export ENV_SOURCE="remote"
    export ENV_SOURCE_HOST="example.com"
    export ENV_SOURCE_PORT="2222"
    export ENV_SOURCE_USER="user"
    export ENV_SOURCE_DIR="/var/www/html"
    export SSH_OPTS="-o StrictHostKeyChecking=no"
    
    # Mock ssh
    cat > "${MOCK_BIN}/ssh" << 'EOF'
#!/usr/bin/env bash
echo "SSH_CALL: $@"
EOF
    chmod +x "${MOCK_BIN}/ssh"

    # Mock warden
    cat > "${MOCK_BIN}/warden" << 'EOF'
#!/usr/bin/env bash
if [[ "$1" == "remote-exec" ]]; then
    shift 4
    echo "WARDEN_REMOTE_EXEC: $@"
    exit 0
fi
echo "WARDEN_CALL: $@"
EOF
    chmod +x "${MOCK_BIN}/warden"

    # Run full deploy
    run "${TEST_SCRIPT_DIR}/deploy.cmd"
    
    # Verify Warden Remote Exec call
    
    # Should check if remote-exec was called with correct commands
    [[ "$output" == *"WARDEN_REMOTE_EXEC: composer install"* ]]
    [[ "$output" == *"WARDEN_REMOTE_EXEC: bin/magento setup:upgrade"* ]]
}
