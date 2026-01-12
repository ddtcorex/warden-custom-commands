#!/usr/bin/env bats

load "../../../libs/mocks.bash"

setup() {
    setup_mocks
    export WARDEN_DIR="/tmp/warden"
    
    export TEST_SCRIPT_DIR="${TEST_TMP_DIR}/magento2-fix-deps"
    mkdir -p "${TEST_SCRIPT_DIR}"
    cp "${BATS_TEST_DIRNAME}/../../../../env-adapters/magento2/fix-deps.cmd" "${TEST_SCRIPT_DIR}/fix-deps.cmd"
    chmod +x "${TEST_SCRIPT_DIR}/fix-deps.cmd"
    
    BOOTSTRAP_CMD="${TEST_SCRIPT_DIR}/fix-deps.cmd"
    
    # Mock versions.json with correct structure matching real file
    printf '{\n  "2.4.6": {\n    "php": ["8.2", "8.1"],\n    "php_default": "8.2",\n    "mysql": "8.0",\n    "mariadb": ["10.6"],\n    "mariadb_default": "10.6",\n    "opensearch": "2.5",\n    "elasticsearch": "7.17",\n    "redis": "7.0",\n    "composer": "2.2",\n    "rabbitmq": "3.9",\n    "varnish": "7.1"\n  },\n  "2.4.5": {\n    "php": ["8.1"],\n    "php_default": "8.1",\n    "mysql": "8.0",\n    "mariadb": ["10.4"],\n    "mariadb_default": "10.4",\n    "opensearch": "1.2",\n    "elasticsearch": "7.17",\n    "redis": "6.2",\n    "composer": "2.2",\n    "rabbitmq": "3.9",\n    "varnish": "7.0"\n  }\n}' > "${TEST_SCRIPT_DIR}/magento-versions.json"
    
    # Create .env in temp dir (change to temp dir for tests)
    cd "${TEST_SCRIPT_DIR}"
    touch .env
}

@test "Fix-Deps: Parses version from argument" {
    run "$BOOTSTRAP_CMD" --version=2.4.6 --dry-run
    [[ "$output" == *"Using Magento version: 2.4.6"* ]]
}

@test "Fix-Deps: Fallback to latest minor if patch missing" {
    run "$BOOTSTRAP_CMD" --version=2.4.5-p1 --dry-run
    [[ "$output" == *"Enforcing latest available version '2.4.5'"* ]]
}

@test "Fix-Deps: Updates .env file" {
    echo "PHP_VERSION=7.4" > .env
    run "$BOOTSTRAP_CMD" --version=2.4.6
    
    # Check .env directly
    result=$(cat .env)
    [[ "$result" == *"PHP_VERSION=8.2"* ]]
}

@test "Fix-Deps: Sets Search Engine based on version" {
    # For 2.4.6, opensearch should be set (not null in json)
    echo "" > .env
    run "$BOOTSTRAP_CMD" --version=2.4.6
    
    result=$(cat .env)
    # OpenSearch is preferred when available
    [[ "$result" == *"WARDEN_OPENSEARCH=1"* ]]
}
