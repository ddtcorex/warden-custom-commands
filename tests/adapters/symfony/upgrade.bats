#!/usr/bin/env bats

load "../../libs/mocks.bash"

setup() {
    setup_mocks
    
    # Environment variables mock
    export WARDEN_DIR="/tmp/warden"
    
    # Copy script to temp location
    export TEST_SCRIPT_DIR="${BATS_TMPDIR}/symfony-upgrade"
    mkdir -p "${TEST_SCRIPT_DIR}"
    cp "${BATS_TEST_DIRNAME}/../../../env-adapters/symfony/upgrade.cmd" "${TEST_SCRIPT_DIR}/upgrade.cmd"
    chmod +x "${TEST_SCRIPT_DIR}/upgrade.cmd"
    
    BOOTSTRAP_CMD="${TEST_SCRIPT_DIR}/upgrade.cmd"
    
    # Create dummy help file
    mkdir -p "${WARDEN_HOME_DIR}/commands"
    echo "Usage info" > "${WARDEN_HOME_DIR}/commands/upgrade.help"

    # Mock warden output for version detection
    function warden() {
        if [[ "$*" == *"bin/console --version"* ]]; then
            echo "Symfony 5.4.0 (env: dev, debug: true)"
            return 0
        fi
        echo "warden $*" >> "$MOCK_LOG"
        return 0
    }
    export -f warden
}

@test "Symfony Upgrade: Dry run" {
    run "$BOOTSTRAP_CMD" --version=6.4 --dry-run
    
    [ "$status" -eq 0 ]
    [[ "$output" == *"[DRY RUN]"* ]]
    assert_command_not_called "composer update"
}

@test "Symfony Upgrade: Execution flow" {
    # Skip confirmation prompt using yes
    run bash -c "yes | $BOOTSTRAP_CMD --version=6.4"
    
    assert_command_called "composer require symfony/framework-bundle:^6.4"
    assert_command_called "composer update"
    assert_command_called "doctrine:migrations:migrate"
    assert_command_called "cache:clear"
}
