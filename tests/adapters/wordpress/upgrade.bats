#!/usr/bin/env bats

load "../../libs/mocks.bash"

setup() {
    setup_mocks
    
    export WARDEN_DIR="/tmp/warden"
    export TEST_SCRIPT_DIR="${TEST_TMP_DIR}/wordpress-upgrade"
    mkdir -p "${TEST_SCRIPT_DIR}"
    cp "${BATS_TEST_DIRNAME}/../../../env-adapters/wordpress/upgrade.cmd" "${TEST_SCRIPT_DIR}/upgrade.cmd"
    chmod +x "${TEST_SCRIPT_DIR}/upgrade.cmd"
    
    BOOTSTRAP_CMD="${TEST_SCRIPT_DIR}/upgrade.cmd"
    
    mkdir -p "${WARDEN_HOME_DIR}/commands"
    echo "Usage info" > "${WARDEN_HOME_DIR}/commands/upgrade.help"

    function warden() {
        if [[ "$*" == *"wp core version"* ]]; then
            echo "6.0.0"
            return 0
        fi
        echo "warden $*" >> "$MOCK_LOG"
        return 0
    }
    export -f warden
}

@test "WordPress Upgrade: Dry run" {
    run "$BOOTSTRAP_CMD" --version=6.4 --dry-run
    [ "$status" -eq 0 ]
    assert_command_not_called "wp core update"
}

@test "WordPress Upgrade: Execution flow" {
    run bash -c "yes | $BOOTSTRAP_CMD --version=6.4"
    
    assert_command_called "wp core update --version=6.4"
    assert_command_called "wp core update-db"
    assert_command_called "wp cache flush"
}
