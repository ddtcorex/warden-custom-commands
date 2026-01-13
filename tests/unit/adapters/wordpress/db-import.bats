#!/usr/bin/env bats

load "../../../libs/mocks.bash"

setup() {
    setup_mocks
    
    # Copy script
    export TEST_SCRIPT_DIR="${TEST_TMP_DIR}/wordpress-db-import"
    mkdir -p "${TEST_SCRIPT_DIR}"
    cp "${BATS_TEST_DIRNAME}/../../../../env-adapters/wordpress/db-import.cmd" "${TEST_SCRIPT_DIR}/db-import.cmd"
    cp "${BATS_TEST_DIRNAME}/../../../../env-adapters/wordpress/utils.sh" "${TEST_SCRIPT_DIR}/utils.sh"
    chmod +x "${TEST_SCRIPT_DIR}/db-import.cmd"
    
    BOOTSTRAP_CMD="${TEST_SCRIPT_DIR}/db-import.cmd"
    
    # Mock warden to simulate running DB container
    function warden() {
        if [[ "$*" == *"env ps"* ]]; then
            echo "db_container_id_123"
            return 0
        fi
        echo "warden $*" >> "$MOCK_LOG"
    }
    export -f warden
    
    # Create test artifacts in test directory
    cd "${TEST_SCRIPT_DIR}"
    touch "dump.sql.gz"
}

@test "WordPress DB Import: Import from file" {
    run "$BOOTSTRAP_CMD" --file=dump.sql.gz
    grep -Fq "warden env exec -T db bash -c \$(command -v mariadb || echo mysql) -hdb -u\"\$MYSQL_USER\" -p\"\$MYSQL_PASSWORD\" \"\$MYSQL_DATABASE\" -f" "$MOCK_LOG"
}
