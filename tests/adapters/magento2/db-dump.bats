#!/usr/bin/env bats

load "../../libs/mocks.bash"

setup() {
    setup_mocks
    
    export WARDEN_ENV_NAME="magento2-test"
    export ENV_SOURCE="local"
    export DB_PREFIX="mage_"
    
    # Copy script
    export TEST_SCRIPT_DIR="${BATS_TMPDIR}/magento2-db-dump"
    mkdir -p "${TEST_SCRIPT_DIR}"
    cp "${BATS_TEST_DIRNAME}/../../../env-adapters/magento2/db-dump.cmd" "${TEST_SCRIPT_DIR}/db-dump.cmd"
    chmod +x "${TEST_SCRIPT_DIR}/db-dump.cmd"
    
    BOOTSTRAP_CMD="${TEST_SCRIPT_DIR}/db-dump.cmd"
    
    # Override Warden to split output for credential gathering vs execution
    function warden() {
        if [[ "$*" == *"printenv MYSQL_"* ]]; then
            echo "test_cred"
            return 0
        fi
        echo "warden $*" >> "$MOCK_LOG"
    }
    export -f warden
    
    # Mock date for predictable filename
    function date() { echo "20230101"; }
    export -f date
}

@test "DB Dump: Default local dump" {
    run "$BOOTSTRAP_CMD"
    
    # It should look up credentials
    # It should run mysqldump
    assert_command_called "mysqldump"
    
    # Check default filename usage
    [[ "$output" == *"File: var/magento2-test_local-20230101.sql.gz"* ]]
}

@test "DB Dump: Exclude sensitive data adds ignore-table options" {
    # Check if ignore-table is used (default behaviour)
    run "$BOOTSTRAP_CMD"
    assert_command_called "--ignore-table=test_cred.mage_admin_user"
    
    # Standard Sensitive Data
    run "$BOOTSTRAP_CMD" --exclude-sensitive-data
    assert_command_called "--ignore-table=test_cred.mage_sales_order"
}

@test "DB Dump: Full dump removes ignore-table options" {
    # We can't strictly check absence easily with grep in log, but we can verify the command string
    # Mocking mysqldump output isn't easy here as it happens inside docker exec
    # We check if the constructed command in the log lacks ignored tables
    
    run "$BOOTSTRAP_CMD" --full
    
    # The command should NOT contain --ignore-table because FULL_DUMP=1 clears it
    # But wait, the script iterates IGNORED_TABLES only if FULL_DUMP=0
    
    # So we check if the LOG contains a call withOUT ignore-table? 
    # That's hard because the log lines are long.
    # Let's rely on the fact that ignore-tables make the command very long.
    # Actually, we can check for table names. "admin_user" should NOT be ignored in full dump
    
    # Wait, existing code: if FULL_DUMP=0, then loop ignored tables.
    # So if FULL_DUMP=1, "admin_user" is NOT ignored (it is included in dump).
    # The arguments --ignore-table wont be present.
    
    # We assert that the command string in the log does NOT contain "ignore-table"
    run grep "ignore-table" "$MOCK_LOG"
    [ "$status" -eq 1 ]
}

@test "DB Dump: Remote premise via SSH" {
    export ENV_SOURCE="production"
    export ENV_SOURCE_HOST="example.com"
    export ENV_SOURCE_USER="user"
    export ENV_SOURCE_PORT="22"
    export ENV_SOURCE_DIR="/var/www/html"
    
    # We need to mock ssh
    function ssh() {
        # Return dummy php array for the config check
        if [[ "$*" == *"php -r"* ]]; then
             echo "array ( 'host' => 'db-host', 'username' => 'db-user', 'password' => 'db-pass', 'dbname' => 'db-name' )"
             return 0
        fi
        echo "ssh $*" >> "$MOCK_LOG"
    }
    export -f ssh
    
    run "$BOOTSTRAP_CMD"
    
    # Should attempt SSH connection
    assert_command_called "ssh -o BatchMode=yes -o StrictHostKeyChecking=no -p 22 user@example.com"
}
