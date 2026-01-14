#!/usr/bin/env bats

load "../../../libs/mocks.bash"

setup() {
    setup_mocks
    unset -f warden
    
    export TEST_SCRIPT_DIR="${TEST_TMP_DIR}/magento2-deployer"
    mkdir -p "${TEST_SCRIPT_DIR}"
    
    # Copy the script to be tested
    cp "${BATS_TEST_DIRNAME}/../../../../env-adapters/magento2/deploy.cmd" "${TEST_SCRIPT_DIR}/deploy.cmd"

    # Setup mock bin
    export MOCK_BIN="${TEST_TMP_DIR}/mock-bin"
    rm -rf "${MOCK_BIN}"
    mkdir -p "${MOCK_BIN}"
    export PATH="${MOCK_BIN}:${PATH}"
    
    # Mock environment variables
    export WARDEN_ENV_PATH="${TEST_SCRIPT_DIR}"
    export WARDEN_ENV_TYPE="magento2"
    mkdir -p "${WARDEN_ENV_PATH}/.warden"
}

@test "DeployCmd: Deployer strategy executes correctly with automated env detection" {
    unset -f warden
    export DEPLOY_STRATEGY="deployer"
    export ENV_SOURCE_ORIG="develop"
    touch "${TEST_SCRIPT_DIR}/deploy.php"
    
    cat > "${MOCK_BIN}/warden" << 'EOF'
#!/usr/bin/env bash
case "$*" in
    *"test -f vendor/bin/dep"*) exit 1 ;;
    *"command -v dep"*) exit 1 ;;
    *"composer global config bin-dir"*) echo "/home/www-data/.composer/vendor/bin" ;;
    *"test -f /home/www-data/.composer/vendor/bin/dep"*) exit 0 ;;
    *) echo "WARDEN_CALL: $*" >&2 ;;
esac
EOF
    chmod +x "${MOCK_BIN}/warden"
    
    cd "${TEST_SCRIPT_DIR}"
    run ./deploy.cmd
    
    [[ "$output" =~ "env exec -T php-fpm bash -c mkdir -p ~/.ssh" ]]
    [[ "$output" =~ "StrictHostKeyChecking no" ]]
    [[ "$output" =~ "env exec -T php-fpm /home/www-data/.composer/vendor/bin/dep deploy develop -f deploy.php" ]]
}

@test "DeployCmd: Deployer strategy installs deployer if missing" {
    unset -f warden
    export DEPLOY_STRATEGY="deployer"
    export ENV_SOURCE_ORIG="staging"
    touch "${TEST_SCRIPT_DIR}/deploy.php"
    
    cat > "${MOCK_BIN}/warden" << 'EOF'
#!/usr/bin/env bash
case "$*" in
    *"test -f vendor/bin/dep"*) exit 1 ;;
    *"command -v dep"*) exit 1 ;;
    *"composer global config bin-dir"*) echo "/home/www-data/.composer/vendor/bin" ;;
    *"test -f /home/www-data/.composer/vendor/bin/dep"*)
        if [[ -f "/tmp/deployer_installed" ]]; then exit 0; else exit 1; fi
        ;;
    *"composer global require deployer/deployer"*)
        touch "/tmp/deployer_installed"
        echo "Installing deployer..." >&2 # Informative output to STDERR
        ;;
    *) echo "WARDEN_CALL: $*" >&2 ;;
esac
EOF
    chmod +x "${MOCK_BIN}/warden"
    rm -f /tmp/deployer_installed
    
    cd "${TEST_SCRIPT_DIR}"
    run ./deploy.cmd
    
    [[ "$output" =~ "Deployer not found in container. Installing globally..." ]]
    [[ "$output" =~ "env exec -T php-fpm /home/www-data/.composer/vendor/bin/dep deploy staging -f deploy.php" ]]
}

@test "DeployCmd: Deployer strategy respects custom config path" {
    unset -f warden
    export DEPLOY_STRATEGY="deployer"
    export DEPLOYER_CONFIG="custom/deploy.yaml"
    export ENV_SOURCE_ORIG="production"
    
    mkdir -p "${TEST_SCRIPT_DIR}/custom"
    touch "${TEST_SCRIPT_DIR}/custom/deploy.yaml"
    
    cat > "${MOCK_BIN}/warden" << 'EOF'
#!/usr/bin/env bash
case "$*" in
    *"test -f vendor/bin/dep"*) exit 1 ;;
    *"command -v dep"*) exit 0 ;;
    *) echo "WARDEN_CALL: $*" >&2 ;;
esac
EOF
    chmod +x "${MOCK_BIN}/warden"
    
    cd "${TEST_SCRIPT_DIR}"
    run ./deploy.cmd
    
    [[ "$output" =~ "env exec -T php-fpm dep deploy production -f custom/deploy.yaml" ]]
}
