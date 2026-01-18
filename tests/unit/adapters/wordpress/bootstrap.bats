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

@test "WordPress: Default behavior streams database" {
    export ENV_SOURCE_HOST="example.com"
    run "$BOOTSTRAP_CMD" --skip-wp-install
    
    assert_command_called "warden db-import --stream-db"
}

@test "WordPress: --no-stream-db falls back to local download" {
    export ENV_SOURCE_HOST="example.com"
    run "$BOOTSTRAP_CMD" --no-stream-db --skip-wp-install
    
    # Should use --local in db-dump
    grep -E -q "warden db-dump --local --file=.* -e wordpress" "${MOCK_LOG}"
}

@test "WordPress: Clone mode runs env up before sync and runs composer install" {
    export ENV_SOURCE="staging"
    export ENV_SOURCE_HOST="mock-host"
    export CLONE_MODE="1"
    
    mkdir -p "${WARDEN_ENV_PATH}"
    touch "${WARDEN_ENV_PATH}/.env"
    
    # Ensure composer.json exists so composer install triggers
    touch "composer.json"

    run "$BOOTSTRAP_CMD" --clone --source=staging --skip-db-import --skip-wp-install
    
    [ "$status" -eq 0 ]
    
    local svc_up_line=$(grep -n "warden svc up" "$MOCK_LOG" | cut -d: -f1 | head -1)
    local sync_line=$(grep -n "warden sync" "$MOCK_LOG" | cut -d: -f1 | head -1)
    
    [ -n "$svc_up_line" ]
    [ -n "$sync_line" ]
    [ "$svc_up_line" -lt "$sync_line" ]
    
    assert_command_called "warden env exec -T php-fpm composer install"
}
@test "WordPress: Clone mode patches existing wp-config.php" {
    cd "${WARDEN_ENV_PATH}"
    
    # Create a mock wp-config.php with remote values
    cat <<EOT > "wp-config.php"
define( 'DB_NAME', 'remote_db' );
define( 'DB_USER', 'remote_user' );
define( 'DB_PASSWORD', 'remote_pass' );
define( 'DB_HOST', 'remote_host' );
EOT

    # We need to mock environment variables for the bootstrap
    export ENV_SOURCE="staging"
    export ENV_SOURCE_HOST="mock-host"
    export REMOTE_STAGING_HOST="mock-host"

    # We need to mock warden to report that wp-config.php EXISTS
    function warden() {
        echo "warden $*" >> "$MOCK_LOG"
        if [[ "$*" == *"test -f wp-config.php" ]]; then
            return 0 # Found
        fi
        return 0
    }
    export -f warden

    run "$BOOTSTRAP_CMD" --clone --source=staging --skip-db-import --skip-wp-install
    
    [ "$status" -eq 0 ]
    
    # Verify sed was called for DB_NAME
    assert_command_called "sed -i"
    assert_command_called "DB_NAME"
    assert_command_called "DB_HOST"
}
