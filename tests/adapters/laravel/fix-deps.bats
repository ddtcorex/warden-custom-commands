#!/usr/bin/env bats

load "../../libs/mocks.bash"

setup() {
    setup_mocks
    export WARDEN_DIR="/tmp/warden"
    export TEST_SCRIPT_DIR="${BATS_TMPDIR}/laravel-fix-deps"
    mkdir -p "${TEST_SCRIPT_DIR}"
    cp "${BATS_TEST_DIRNAME}/../../../env-adapters/laravel/fix-deps.cmd" "${TEST_SCRIPT_DIR}/fix-deps.cmd"
    chmod +x "${TEST_SCRIPT_DIR}/fix-deps.cmd"
    
    BOOTSTRAP_CMD="${TEST_SCRIPT_DIR}/fix-deps.cmd"
    
    printf '{\n  "10": {\n    "php_default": "8.2",\n    "mysql": "8.0",\n    "mariadb_default": "10.10",\n    "redis": "7.0",\n    "composer": "2.5"\n  }\n}' > "${TEST_SCRIPT_DIR}/laravel-versions.json"
    touch .env
}

@test "Laravel Fix-Deps: Updates .env" {
    echo "PHP_VERSION=7.4" > .env
    run "$BOOTSTRAP_CMD" --version=10
    
    run cat .env
    [[ "$output" == *"PHP_VERSION=8.2"* ]]
}
