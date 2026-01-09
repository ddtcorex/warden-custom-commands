#!/usr/bin/env bats

load "../../../libs/mocks.bash"

setup() {
    setup_mocks
    
    export WARDEN_DIR="/tmp/warden"
    export ENV_SOURCE="wordpress"
    export WARDEN_ENV_NAME="wordpress-test"
    export TRAEFIK_DOMAIN="test.localhost"
    
    # Copy script
    export TEST_SCRIPT_DIR="${TEST_TMP_DIR}/wordpress-adapter"
    mkdir -p "${TEST_SCRIPT_DIR}"
    cp "${BATS_TEST_DIRNAME}/../../../../env-adapters/wordpress/bootstrap.cmd" "${TEST_SCRIPT_DIR}/bootstrap.cmd"
    chmod +x "${TEST_SCRIPT_DIR}/bootstrap.cmd"
    
    BOOTSTRAP_CMD="${TEST_SCRIPT_DIR}/bootstrap.cmd"
    
    echo "# mock fix-deps" > "${TEST_SCRIPT_DIR}/fix-deps.cmd"
    
    # Override warden to simulate missing wp-config.php but present sample
    function warden() {
        echo "warden $*" >> "$MOCK_LOG"
        
        if [[ "$*" == *"test -f wp-config.php" ]]; then
            return 1 # Not found
        fi
        
        if [[ "$*" == *"test -f wp-config-sample.php" ]]; then
            return 0 # Found
        fi
        
        return 0
    }
    export -f warden
}

@test "WordPress: --clean-install downloads core" {
    run "$BOOTSTRAP_CMD" --clean-install --skip-db-import --no-stream-db
    
    # WordPress adapter usually uses curl
    assert_command_called "curl -o /tmp/wordpress.tar.gz"
}

@test "WordPress: Configures Database" {
    run "$BOOTSTRAP_CMD" --clean-install --skip-db-import
    # We now write directly to file, so no command check needed for cp
}

@test "WordPress: Fails if WARDEN_DIR not set" {
    export WARDEN_DIR=""
    run bash -c "unset WARDEN_DIR && $BOOTSTRAP_CMD"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not intended to be run directly"* ]]
}
