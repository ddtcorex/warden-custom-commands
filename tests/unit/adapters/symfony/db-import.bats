#!/usr/bin/env bats

load "../../../libs/mocks.bash"

setup() {
    setup_mocks
    
    # Copy script
    export TEST_SCRIPT_DIR="${TEST_TMP_DIR}/symfony-db-import"
    mkdir -p "${TEST_SCRIPT_DIR}"
    cp "${BATS_TEST_DIRNAME}/../../../../env-adapters/symfony/db-import.cmd" "${TEST_SCRIPT_DIR}/db-import.cmd"
    cp "${BATS_TEST_DIRNAME}/../../../../env-adapters/symfony/utils.sh" "${TEST_SCRIPT_DIR}/utils.sh"
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

@test "Symfony DB Import: Import from file" {
    run "$BOOTSTRAP_CMD" --file=dump.sql.gz
    grep -Fq 'export MYSQL_PWD="$MYSQL_PASSWORD"' "$MOCK_LOG"
    grep -Fq 'SET FOREIGN_KEY_CHECKS=0' "$MOCK_LOG"
    grep -Fq 'mariadb || echo mysql' "$MOCK_LOG"
}
