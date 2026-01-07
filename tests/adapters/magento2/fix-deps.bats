#!/usr/bin/env bats

load "../../libs/mocks.bash"

setup() {
    setup_mocks
    
    # Copy script
    export TEST_SCRIPT_DIR="${BATS_TMPDIR}/magento2-fix-deps"
    mkdir -p "${TEST_SCRIPT_DIR}"
    cp "${BATS_TEST_DIRNAME}/../../../env-adapters/magento2/fix-deps.cmd" "${TEST_SCRIPT_DIR}/fix-deps.cmd"
    chmod +x "${TEST_SCRIPT_DIR}/fix-deps.cmd"
    
    BOOTSTRAP_CMD="${TEST_SCRIPT_DIR}/fix-deps.cmd"
    
    # Create sample version file
    cat << EOF > "${TEST_SCRIPT_DIR}/magento-versions.json"
{
  "2.4.6": {
    "php_default": "8.1",
    "mysql": "8.0",
    "mariadb_default": "10.6",
    "opensearch": "2.5",
    "elasticsearch": "7.17",
    "redis": "7.0",
    "composer": "2.2",
    "rabbitmq": "3.9",
    "varnish": "7.1"
  },
  "2.4.5": {
    "php_default": "8.1",
    "mysql": "8.0",
    "mariadb_default": "10.4",
        "opensearch": "null",
        "elasticsearch": "7.16",
        "redis": "6.0",
        "composer": "2.2",
        "rabbitmq": "3.9",
        "varnish": "7.0"
  }
}
EOF

    # Mock .env file
    touch .env
    
    # Ensure jq is available (BATS env usually has it, but if not we might need to skip or mock)
    # We assume usage of real jq since complex logic is tested
}

@test "Fix-Deps: Parses version from argument" {
    run "$BOOTSTRAP_CMD" --version=2.4.6 --dry-run
    
    [[ "$output" == *"Using Magento version: 2.4.6"* ]]
    [[ "$output" == *"PHP_VERSION=8.1"* ]]
}

@test "Fix-Deps: Fallback to latest minor if patch missing" {
    # 2.4.6 is in file, allow user to request 2.4.6-p1 (which isn't) -> fallback to 2.4.6?
    # Logic: grep -P -m 1 "^[[:space:]]*\"${ESCAPED_BASE}(?:-[^\"]+)?\"\s*:"
    # If we request 2.4.6-p99 (doesn't exist), base is 2.4.6
    # The grep finds "2.4.6" key.
    
    # Let's request 2.4.5-p1. Should find 2.4.5.
    
    run "$BOOTSTRAP_CMD" --version=2.4.5-p1 --dry-run
    
    [[ "$output" == *"Enforcing latest available version '2.4.5'"* ]]
    [[ "$output" == *"Using Magento version: 2.4.5"* ]]
}

@test "Fix-Deps: Updates .env file" {
    echo "PHP_VERSION=7.4" > .env
    
    run "$BOOTSTRAP_CMD" --version=2.4.6
    
    run cat .env
    [[ "$output" == *"PHP_VERSION=8.1"* ]]
}

@test "Fix-Deps: Switches Search Engine" {
    # 2.4.5 uses Elasticsearch
    run "$BOOTSTRAP_CMD" --version=2.4.5
    run cat .env
    [[ "$output" == *"WARDEN_ELASTICSEARCH=1"* ]]
    [[ "$output" == *"WARDEN_OPENSEARCH=0"* ]]
    
    # 2.4.6 uses OpenSearch
    run "$BOOTSTRAP_CMD" --version=2.4.6
    run cat .env
    [[ "$output" == *"WARDEN_ELASTICSEARCH=0"* ]]
    [[ "$output" == *"WARDEN_OPENSEARCH=1"* ]]
}
