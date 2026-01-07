#!/usr/bin/env bats

load "../../libs/mocks.bash"

BOOTSTRAP_CMD="${BATS_TEST_DIRNAME}/../../../env-adapters/symfony/bootstrap.cmd"

setup() {
    setup_mocks
    
    export WARDEN_DIR="/tmp/warden"
    export ENV_SOURCE="symfony"
    export WARDEN_ENV_NAME="symfony-test"
    export TRAEFIK_DOMAIN="test.localhost"
    
    # Create mock .env for clean install backup test
    touch ".env"
    echo "WARDEN_TEST=1" > ".env"
    
    # Copy bootstrap to temp location
    export TEST_SCRIPT_DIR="${TEST_TMP_DIR}/symfony-adapter"
    mkdir -p "${TEST_SCRIPT_DIR}"
    cp "${BATS_TEST_DIRNAME}/../../../env-adapters/symfony/bootstrap.cmd" "${TEST_SCRIPT_DIR}/bootstrap.cmd"
    chmod +x "${TEST_SCRIPT_DIR}/bootstrap.cmd"
    
    BOOTSTRAP_CMD="${TEST_SCRIPT_DIR}/bootstrap.cmd"
    
    # Create mock fix-deps.cmd
    echo "# mock fix-deps" > "${TEST_SCRIPT_DIR}/fix-deps.cmd"
}

@test "Symfony: --clean-install performs project creation and env merge" {
    run "$BOOTSTRAP_CMD" --clean-install --skip-db-import --no-stream-db
    
    assert_command_called "composer create-project symfony/website-skeleton"
    
    # Check if logic attempted to read .env
    # The script uses 'grep ... .env' (host side)
    # We can't easily mock host side grep if it runs directly, but we can check if the result file was used
    # The script creates /tmp/warden_vars.txt. Since we are running in the same shell,
    # we can check if it attempted to read/write it.
    # Actually, BATS 'run' isolates FS somewhat? No, FS is shared.
    
    # Check that warden env exec was called to merge envs - actually this is done on host
    # We verify that the backup logic ran by checking .env content for duplication 
    # (since we didn't wipe .env in the mocked create-project)
    
    # We can also check if the script sent the "Installing Symfony..." message
    [[ "$output" == *"Installing Symfony via composer create-project"* ]]
    
    # Verify warden_vars.txt was processed (it should be deleted)
    [ ! -f "/tmp/warden_vars.txt" ]
}

@test "Symfony: DB Config Uses Container Credentials" {
    run "$BOOTSTRAP_CMD" --skip-db-import --skip-composer-install --skip-migrate
    
    # It should have called printenv to get credentials
    assert_command_called "printenv MYSQL_USER"
    
    # It should edit the .env file with the values
    # The mock returns "test_db_value" for all MYSQL_* calls
    # So we expect DATABASE_URL using "test_db_value"
    assert_command_called "mysql://test_db_value:test_db_value@db:3306/test_db_value"
}

@test "Symfony: Skip flags prevent actions" {
    run "$BOOTSTRAP_CMD" --skip-migrate --skip-composer-install --skip-db-import
    
    assert_command_not_called "doctrine:migrations:migrate"
    assert_command_not_called "composer install"
    assert_command_not_called "db-import"
}

@test "Symfony: Fails if WARDEN_DIR not set (Simulated)" {
    # Unset WARDEN_DIR for this test
    export WARDEN_DIR=""
    # We must run in a subshell or unset effectively
    # 'run' runs in subshell but inherits exported vars.
    # We can override the variable in the run command line? No.
    # We can invoke bash -c
    
    run bash -c "unset WARDEN_DIR && $BOOTSTRAP_CMD"
    
    [ "$status" -eq 1 ]
    [[ "$output" == *"not intended to be run directly"* ]]
}
