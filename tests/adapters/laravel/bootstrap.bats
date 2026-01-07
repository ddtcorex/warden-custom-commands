#!/usr/bin/env bats

load "../../libs/mocks.bash"

setup() {
    setup_mocks
    
    export WARDEN_DIR="/tmp/warden"
    export ENV_SOURCE="laravel"
    export WARDEN_ENV_NAME="laravel-test"
    export TRAEFIK_DOMAIN="test.localhost"
    
    # Mock .env for duplicate check
    touch ".env"
    echo "WARDEN_TEST=1" > ".env"

    # Copy script
    export TEST_SCRIPT_DIR="${BATS_TMPDIR}/laravel-adapter"
    mkdir -p "${TEST_SCRIPT_DIR}"
    cp "${BATS_TEST_DIRNAME}/../../../env-adapters/laravel/bootstrap.cmd" "${TEST_SCRIPT_DIR}/bootstrap.cmd"
    chmod +x "${TEST_SCRIPT_DIR}/bootstrap.cmd"
    
    BOOTSTRAP_CMD="${TEST_SCRIPT_DIR}/bootstrap.cmd"
    
    echo "# mock fix-deps" > "${TEST_SCRIPT_DIR}/fix-deps.cmd"
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

@test "Laravel: Fails if WARDEN_DIR not set" {
    export WARDEN_DIR=""
    run bash -c "unset WARDEN_DIR && $BOOTSTRAP_CMD"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not intended to be run directly"* ]]
}
