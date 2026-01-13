#!/usr/bin/env bats

load "../../../libs/mocks.bash"

setup() {
    setup_mocks
    
    # Environment variables mock
    export WARDEN_DIR="/tmp/warden"
    export WARDEN_HOME_DIR="/tmp/warden-home"
    export ENV_SOURCE="local"
    
    # Copy script to temp location
    export TEST_SCRIPT_DIR="${TEST_TMP_DIR}/magento2-upgrade"
    mkdir -p "${TEST_SCRIPT_DIR}"
    cp "${BATS_TEST_DIRNAME}/../../../../env-adapters/magento2/upgrade.cmd" "${TEST_SCRIPT_DIR}/upgrade.cmd"
    chmod +x "${TEST_SCRIPT_DIR}/upgrade.cmd"
    
    BOOTSTRAP_CMD="${TEST_SCRIPT_DIR}/upgrade.cmd"
    
    # Mock fix-deps.cmd
    echo 'echo "fix-deps called with $*"' > "${TEST_SCRIPT_DIR}/fix-deps.cmd"
    chmod +x "${TEST_SCRIPT_DIR}/fix-deps.cmd"
    
    # Create dummy help file
    mkdir -p "${WARDEN_HOME_DIR}/commands"
    echo "Usage info" > "${WARDEN_HOME_DIR}/commands/upgrade.help"

    # Mock wardens output for version detection
    function warden() {
        if [[ "$*" == *"php bin/magento --version"* ]]; then
            echo "Magento CLI 2.4.5"
            return 0
        fi
        echo "warden $*" >> "$MOCK_LOG"
        return 0
    }
    export -f warden
    
    # Mock other commands
    function jq() { echo "{}"; }
    export -f jq
    
    function sleep() { return 0; }
    export -f sleep
}

@test "Upgrade: Missing version argument fails" {
    run "$BOOTSTRAP_CMD"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Target version is required"* ]]
}

@test "Upgrade: Dry run outputs steps without execution" {
    run "$BOOTSTRAP_CMD" --version=2.4.6 --dry-run
    
    [ "$status" -eq 0 ]
    [[ "$output" == *"[DRY RUN]"* ]]
    # Should not call warden env down/up
    assert_command_not_called "warden env down"
}

@test "Upgrade: Standard execution flow" {
    # Skip confirmation prompt using yes
    run bash -c "yes | $BOOTSTRAP_CMD --version=2.4.6"
    
    # Check dependencies update
    [[ "$output" == *"fix-deps called with --version=2.4.6"* ]]
    
    # Check restart
    assert_command_called "warden env down"
    assert_command_called "warden env up -d"
    
    # Check composer usage
    assert_command_called "warden env exec -T php-fpm cp composer.json composer.json.bak"
    assert_command_called "composer create-project"
    
    # Check magento commands
    assert_command_called "bin/magento setup:upgrade"
    assert_command_called "bin/magento setup:di:compile"
    assert_command_called "bin/magento cache:flush"
    
    # Check cleanup
    assert_command_called "rm -f composer.json.bak"
}

@test "Upgrade: Skip environment update" {
    run bash -c "yes | $BOOTSTRAP_CMD --version=2.4.6 --skip-env-update"
    
    # Should not call fix-deps
    [[ "$output" != *"fix-deps called"* ]]
    
    # Should not call restart
    assert_command_not_called "warden env down"
}

@test "Upgrade: Skip DB upgrade" {
    run bash -c "yes | $BOOTSTRAP_CMD --version=2.4.6 --skip-db-upgrade"
    
    assert_command_not_called "bin/magento setup:upgrade"
    assert_command_called "bin/magento setup:di:compile"
}
