#!/usr/bin/env bats

load "../../libs/mocks.bash"

setup() {
    setup_mocks
    export WARDEN_DIR="/tmp/warden"
    export TEST_SCRIPT_DIR="${TEST_TMP_DIR}/wordpress-fix-deps"
    mkdir -p "${TEST_SCRIPT_DIR}"
    cp "${BATS_TEST_DIRNAME}/../../../env-adapters/wordpress/fix-deps.cmd" "${TEST_SCRIPT_DIR}/fix-deps.cmd"
    chmod +x "${TEST_SCRIPT_DIR}/fix-deps.cmd"
    
    BOOTSTRAP_CMD="${TEST_SCRIPT_DIR}/fix-deps.cmd"
    
    printf '{\n  "6.4": {\n    "php_default": "8.1",\n    "mysql": "8.0",\n    "mariadb_default": "10.6"\n  }\n}' > "${TEST_SCRIPT_DIR}/wordpress-versions.json"
    touch .env
}

@test "WordPress Fix-Deps: Updates .env" {
    echo "PHP_VERSION=7.4" > .env
    run "$BOOTSTRAP_CMD" --version=6.4
    
    run cat .env
    [[ "$output" == *"PHP_VERSION=8.1"* ]]
}
