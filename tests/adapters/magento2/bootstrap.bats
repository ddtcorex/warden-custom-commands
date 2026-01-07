#!/usr/bin/env bats

load "../../libs/mocks.bash"

BOOTSTRAP_CMD="${BATS_TEST_DIRNAME}/../../../env-adapters/magento2/bootstrap.cmd"

setup() {
    setup_mocks
    
    # Required for the script to believe it's in a valid environment context
    export ENV_SOURCE="magento2"
    export ENV_SOURCE_HOST_VAR="127.0.0.1" 
    export WARDEN_ENV_NAME="test-env"
    
    # Copy bootstrap to temp location to allow safe mocking of siblings
    export TEST_SCRIPT_DIR="${BATS_TMPDIR}/magento2-adapter"
    mkdir -p "${TEST_SCRIPT_DIR}"
    cp "${BATS_TEST_DIRNAME}/../../../env-adapters/magento2/bootstrap.cmd" "${TEST_SCRIPT_DIR}/bootstrap.cmd"
    chmod +x "${TEST_SCRIPT_DIR}/bootstrap.cmd"
    
    BOOTSTRAP_CMD="${TEST_SCRIPT_DIR}/bootstrap.cmd"
    
    # Create a mock fix-deps.cmd because the script sources it
    echo "# mock fix-deps" > "${TEST_SCRIPT_DIR}/fix-deps.cmd"
}

@test "Magento2: --clean-install creates auth.json if missing" {
    # Ensure auth.json does not exist
    rm -f "${WARDEN_ENV_PATH}/auth.json"
    
    run "$BOOTSTRAP_CMD" --clean-install --skip-admin-create --skip-composer-install --skip-db-import --skip-media-sync
    
    [ "$status" -eq 0 ]
    [ -f "${WARDEN_ENV_PATH}/auth.json" ]
    run cat "${WARDEN_ENV_PATH}/auth.json"
    [[ "$output" == *"repo.magento.com"* ]]
}

@test "Magento2: --hyva-install sets up Hyva repositories" {
    run "$BOOTSTRAP_CMD" --clean-install --hyva-install --skip-admin-create --skip-composer-install --skip-db-import
    
    assert_command_called "composer config http-basic.hyva-themes.repo.packagist.com"
}

@test "Magento2: Standard install runs warden services" {
    run "$BOOTSTRAP_CMD" --skip-db-import --skip-composer-install --skip-admin-create
    
    assert_command_called "warden svc up"
    assert_command_called "warden env up"
}

@test "Magento2: Invalid version fails" {
    run "$BOOTSTRAP_CMD" --version=1.9.0
    
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid version"* ]]
}
