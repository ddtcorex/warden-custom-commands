#!/usr/bin/env bats

load "../../libs/mocks.bash"

setup() {
    setup_mocks
    
    export WARDEN_DIR="/tmp/warden"
    export TEST_SCRIPT_DIR="${BATS_TMPDIR}/laravel-upgrade"
    mkdir -p "${TEST_SCRIPT_DIR}"
    cp "${BATS_TEST_DIRNAME}/../../../env-adapters/laravel/upgrade.cmd" "${TEST_SCRIPT_DIR}/upgrade.cmd"
    chmod +x "${TEST_SCRIPT_DIR}/upgrade.cmd"
    
    BOOTSTRAP_CMD="${TEST_SCRIPT_DIR}/upgrade.cmd"
    
    mkdir -p "${WARDEN_HOME_DIR}/commands"
    echo "Usage info" > "${WARDEN_HOME_DIR}/commands/upgrade.help"

    function warden() {
        if [[ "$*" == *"artisan --version"* ]]; then
            echo "Laravel Framework 9.0.0"
            return 0
        fi
        echo "warden $*" >> "$MOCK_LOG"
        return 0
    }
    export -f warden
}

@test "Laravel Upgrade: Dry run" {
    run "$BOOTSTRAP_CMD" --version=10 --dry-run
    [ "$status" -eq 0 ]
    assert_command_not_called "composer update"
}

@test "Laravel Upgrade: Execution flow" {
    run bash -c "yes | $BOOTSTRAP_CMD --version=10"
    
    assert_command_called "composer require laravel/framework:^10"
    assert_command_called "composer update"
    assert_command_called "php artisan migrate --force"
}
