#!/usr/bin/env bats

load "../../../libs/mocks.bash"

setup() {
    setup_mocks
    
    export WARDEN_DIR="/tmp/warden"
    export ENV_SOURCE="laravel"
    export WARDEN_ENV_NAME="laravel-test"
    export TRAEFIK_DOMAIN="test.localhost"

    # Copy script
    export TEST_SCRIPT_DIR="${TEST_TMP_DIR}/laravel-adapter"
    mkdir -p "${TEST_SCRIPT_DIR}"
    cp "${BATS_TEST_DIRNAME}/../../../../env-adapters/laravel/bootstrap.cmd" "${TEST_SCRIPT_DIR}/bootstrap.cmd"
    chmod +x "${TEST_SCRIPT_DIR}/bootstrap.cmd"
    
    BOOTSTRAP_CMD="${TEST_SCRIPT_DIR}/bootstrap.cmd"
    
    echo "# mock fix-deps" > "${TEST_SCRIPT_DIR}/fix-deps.cmd"
    
    # Create test artifacts in test directory
    cd "${TEST_SCRIPT_DIR}"
    touch ".env"
    echo "WARDEN_TEST=1" > ".env"
}

@test "Laravel: --clean-install performs project creation" {
    run "$BOOTSTRAP_CMD" --clean-install --skip-db-import --no-stream-db
    
    assert_command_called "composer create-project"
    
    # Check for rsync of files
    assert_command_called "rsync -a"
}

@test "Laravel: DB Config Updates .env" {
    run "$BOOTSTRAP_CMD" --skip-db-import --skip-composer-install --skip-migrate
    
    # The script runs warden env exec php-fpm sed on .env
    assert_command_called "sed -i"
}

@test "Laravel: DB Config Updates .env.php" {
    run "$BOOTSTRAP_CMD" --skip-db-import --skip-composer-install --skip-migrate
    
    # We expect the script to have checked for .env.php (warden mock returns 0, so 'test -f' passes)
    # And then run sed on .env.php
    grep -Fq ".env.php" "$MOCK_LOG"
}

@test "Laravel: Fails if WARDEN_DIR not set" {
    export WARDEN_DIR=""
    run bash -c "unset WARDEN_DIR && $BOOTSTRAP_CMD"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not intended to be run directly"* ]]
}

@test "Laravel: Default behavior streams database" {
    export ENV_SOURCE_HOST="example.com"
    run "$BOOTSTRAP_CMD" --skip-composer-install --skip-migrate
    
    assert_command_called "warden db-import --stream-db"
}

@test "Laravel: --no-stream-db falls back to local download" {
    export ENV_SOURCE_HOST="example.com"
    run "$BOOTSTRAP_CMD" --no-stream-db --skip-composer-install --skip-migrate
    
    # Should use --local indb-dump
    grep -E -q "warden db-dump --local --file=.* -e laravel" "${MOCK_LOG}"
}

@test "Laravel: Clone mode runs env up before sync and runs composer install" {
    export ENV_SOURCE="staging"
    export ENV_SOURCE_HOST="mock-host"
    export CLONE_MODE="1"
    
    mkdir -p "${WARDEN_ENV_PATH}"
    touch "${WARDEN_ENV_PATH}/.env"

    run "$BOOTSTRAP_CMD" --clone --source=staging --skip-db-import --skip-migrate
    
    [ "$status" -eq 0 ]
    
    local svc_up_line=$(grep -n "warden svc up" "$MOCK_LOG" | cut -d: -f1 | head -1)
    local sync_line=$(grep -n "warden sync" "$MOCK_LOG" | cut -d: -f1 | head -1)
    
    [ -n "$svc_up_line" ]
    [ -n "$sync_line" ]
    [ "$svc_up_line" -lt "$sync_line" ]
    
    assert_command_called "warden env exec -T php-fpm composer install"
}
