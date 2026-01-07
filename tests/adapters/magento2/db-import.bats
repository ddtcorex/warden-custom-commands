#!/usr/bin/env bats

load "../../libs/mocks.bash"

setup() {
    setup_mocks
    
    # Copy script
    export TEST_SCRIPT_DIR="${BATS_TMPDIR}/magento2-db-import"
    mkdir -p "${TEST_SCRIPT_DIR}"
    cp "${BATS_TEST_DIRNAME}/../../../env-adapters/magento2/db-import.cmd" "${TEST_SCRIPT_DIR}/db-import.cmd"
    chmod +x "${TEST_SCRIPT_DIR}/db-import.cmd"
    
    BOOTSTRAP_CMD="${TEST_SCRIPT_DIR}/db-import.cmd"
    
    # Mock pv/gzip/sed/gunzip in one go if needed, but they are usually present.
    # We really need to verify "warden db import" calls.
    
    # Create dummy dump file
    touch "dump.sql.gz"
}

@test "DB Import: Fails without file or stream" {
    run "$BOOTSTRAP_CMD"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Please specify a dump file"* ]]
}

@test "DB Import: Ensures DB Container is running" {
    # Mock warden env ps to return empty first, then id
    # This is tricky with simple mocks.
    # Let's assume the mock warden simulates success "env up db"
    
    run "$BOOTSTRAP_CMD" --file=dump.sql.gz
    
    assert_command_called "warden env up db"
    assert_command_called "warden db connect"
}

@test "DB Import: Import from file" {
    run "$BOOTSTRAP_CMD" --file=dump.sql.gz
    
    # Should call warden db import --force
    assert_command_called "warden db import --force"
    
    # Should check if gzip
    # pv should be used if available
}

@test "DB Import: Stop DB if started by script" {
    # If we started it, we stop it.
    # Mock "warden env ps" returning empty (so it starts it)
    
    function warden() {
        if [[ "$*" == *"env ps"* ]]; then
             # Return empty to simulate not running
             echo ""
             return 0
        fi
        echo "warden $*" >> "$MOCK_LOG"
    }
    export -f warden
    
    run "$BOOTSTRAP_CMD" --file=dump.sql.gz
    
    assert_command_called "warden env stop db"
}
