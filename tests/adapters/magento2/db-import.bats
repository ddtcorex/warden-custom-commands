#!/usr/bin/env bats

load "../../libs/mocks.bash"

setup() {
    setup_mocks
    export WARDEN_DIR="/tmp/warden"
    
    export TEST_SCRIPT_DIR="${BATS_TMPDIR}/magento2-db-import"
    mkdir -p "${TEST_SCRIPT_DIR}"
    cp "${BATS_TEST_DIRNAME}/../../../env-adapters/magento2/db-import.cmd" "${TEST_SCRIPT_DIR}/db-import.cmd"
    chmod +x "${TEST_SCRIPT_DIR}/db-import.cmd"
    
    BOOTSTRAP_CMD="${TEST_SCRIPT_DIR}/db-import.cmd"
    
    touch "dump.sql.gz"
    
    # Simple mock that always returns running container
    function warden() {
        if [[ "$*" == *"env ps"* ]]; then
            echo "container_id"
            return 0
        fi
        echo "warden $*" >> "$MOCK_LOG"
    }
    export -f warden
}

@test "DB Import: Fails without file or stream" {
    run "$BOOTSTRAP_CMD"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Please specify a dump file"* ]]
}

@test "DB Import: Import from file" {
    run "$BOOTSTRAP_CMD" --file=dump.sql.gz
    assert_command_called "warden db import --force"
}
