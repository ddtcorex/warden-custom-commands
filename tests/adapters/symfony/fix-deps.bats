#!/usr/bin/env bats

load "../../libs/mocks.bash"

setup() {
    setup_mocks
    export WARDEN_DIR="/tmp/warden"
    
    # Copy script
    export TEST_SCRIPT_DIR="${TEST_TMP_DIR}/symfony-fix-deps"
    mkdir -p "${TEST_SCRIPT_DIR}"
    cp "${BATS_TEST_DIRNAME}/../../../env-adapters/symfony/fix-deps.cmd" "${TEST_SCRIPT_DIR}/fix-deps.cmd"
    chmod +x "${TEST_SCRIPT_DIR}/fix-deps.cmd"
    
    BOOTSTRAP_CMD="${TEST_SCRIPT_DIR}/fix-deps.cmd"
    
    # Create sample version file
    printf '{\n  "6.4": {\n    "php_default": "8.1",\n    "mysql": "8.0",\n    "mariadb_default": "10.6",\n    "redis": "7.0",\n    "composer": "2.6"\n  }\n}' > "${TEST_SCRIPT_DIR}/symfony-versions.json"
    touch .env
}

@test "Symfony Fix-Deps: Updates .env" {
    echo "PHP_VERSION=7.4" > .env
    
    run "$BOOTSTRAP_CMD" --version=6.4
    
    run cat .env
    [[ "$output" == *"PHP_VERSION=8.1"* ]]
    [[ "$output" == *"COMPOSER_VERSION=2.6"* ]]
}
