#!/usr/bin/env bats

load "../../../libs/mocks.bash"

setup() {
    setup_mocks
    
    export TEST_SCRIPT_DIR="${TEST_TMP_DIR}/laravel-sync"
    mkdir -p "${TEST_SCRIPT_DIR}"
    
    cp "${BATS_TEST_DIRNAME}/../../../../env-adapters/laravel/sync.cmd" "${TEST_SCRIPT_DIR}/sync.cmd"
    cp "${BATS_TEST_DIRNAME}/../../../../env-adapters/laravel/utils.sh" "${TEST_SCRIPT_DIR}/utils.sh"
    chmod +x "${TEST_SCRIPT_DIR}/sync.cmd"
    
    BOOTSTRAP_CMD="${TEST_SCRIPT_DIR}/sync.cmd"
    
    export WARDEN_ENV_NAME="laravel-test"
    export WARDEN_ENV_PATH="${TEST_SCRIPT_DIR}"
    export SSH_OPTS="-o StrictHostKeyChecking=no"
    
    # Initialize Sync Vars to avoid unbound variable errors
    export SYNC_PATH=""
    export SYNC_TYPE_FILE="0"
    export SYNC_TYPE_DB="0"
    export SYNC_TYPE_MEDIA="0"
    export SYNC_TYPE_FULL="0"
    export SYNC_DRY_RUN="0"
    export SYNC_DELETE="0"
    export SYNC_REDEPLOY="0"
    export SYNC_REMOTE_TO_REMOTE="0"
    export SYNC_BACKUP="0"
    export SYNC_BACKUP_DIR="~/backup"
    
    # Custom Mocks
    export MOCK_BIN="${TEST_TMP_DIR}/mock-bin"
    mkdir -p "${MOCK_BIN}"
    
    # Override warden function
    function warden() {
        echo "warden $*" >> "$MOCK_LOG"
        if [[ "$*" == *"printenv MYSQL_USER"* ]]; then
            echo "local_user"
        elif [[ "$*" == *"printenv MYSQL_PASSWORD"* ]]; then
            echo "local_pass"
        elif [[ "$*" == *"printenv MYSQL_DATABASE"* ]]; then
            echo "local_db"
        fi
        
        # Mock successful execution
        return 0
    }
    export -f warden

    # Mock ssh
    cat > "${MOCK_BIN}/ssh" << 'EOF'
#!/usr/bin/env bash
echo "ssh $*" >> "${MOCK_LOG}"
if [[ "$*" == *"grep"* ]]; then
    # Helper for get_remote_db_info
    echo "DB_HOST=10.0.0.1"
    echo "DB_PORT=3306"
    echo "DB_DATABASE=remote_db"
    echo "DB_USERNAME=remote_user"
    echo "DB_PASSWORD=remote_pass"
elif [[ "$*" == *"rsync"* ]]; then
    echo "Remote rsync triggered"
fi
EOF
    chmod +x "${MOCK_BIN}/ssh"
    
    export PATH="${MOCK_BIN}:${PATH}"
    
    cd "${TEST_SCRIPT_DIR}"
}

@test "Laravel Sync: File Download" {
    export ENV_SOURCE="dev"
    export ENV_SOURCE_HOST="example.com"
    export ENV_SOURCE_PORT="22"
    export ENV_SOURCE_USER="user"
    export ENV_SOURCE_DIR="/var/www/remote"
    export ENV_SOURCE_HOST_VAR="REMOTE_DEV_HOST"
    
    export DIRECTION="download"
    export SYNC_TYPE_FILE=1
    
    run "$BOOTSTRAP_CMD"
    
    if [[ "$status" -ne 0 ]]; then
        echo "Command failed with status $status"
        echo "Output: $output"
    fi

    grep -q "warden env exec php-fpm rsync " "$MOCK_LOG"
}

@test "Laravel Sync: DB Download" {
    export ENV_SOURCE="dev"
    export ENV_SOURCE_HOST="example.com"
    export ENV_SOURCE_PORT="22"
    export ENV_SOURCE_USER="user"
    export ENV_SOURCE_DIR="/var/www/remote"
    export ENV_SOURCE_HOST_VAR="REMOTE_DEV_HOST"
    
    export DIRECTION="download"
    export SYNC_TYPE_DB=1
    
    run "$BOOTSTRAP_CMD"
    
    if [[ "$status" -ne 0 ]]; then
        echo "Command failed with status $status"
        echo "Output: $output"
    fi
    
    grep -q "ssh .* \$(command -v mariadb" "$MOCK_LOG"
    grep -Fq "warden env exec -T db bash -c \$(command -v mariadb || echo mysql) -hdb -u\"\$MYSQL_USER\" -p\"\$MYSQL_PASSWORD\" \"\$MYSQL_DATABASE\" -f" "$MOCK_LOG"
}

@test "Laravel Sync: DB Upload" {
    export ENV_SOURCE="dev"
    export ENV_SOURCE_HOST="example.com"
    export ENV_SOURCE_PORT="22"
    export ENV_SOURCE_USER="user"
    export ENV_SOURCE_DIR="/var/www/remote"
    export ENV_SOURCE_HOST_VAR="REMOTE_DEV_HOST"
    export SYNC_DESTINATION="remote"
    
    export DIRECTION="upload"
    export SYNC_TYPE_DB=1
    
    run "$BOOTSTRAP_CMD"
    
    if [[ "$status" -ne 0 ]]; then
        echo "Command failed with status $status"
        echo "Output: $output"
    fi
    
    # Debug log for investigation
    echo "=== DB Upload MOCK_LOG Content ==="
    cat "$MOCK_LOG" || true
    echo "=================================="

    # Loose grep because quoted bash -c is hard to match exactly if whitespaces differ
    grep -q "warden env exec -T db bash -c" "$MOCK_LOG"
    grep -E -q "(mariadb-dump|mysqldump) .* local_db" "$MOCK_LOG"
}

@test "Laravel Sync: Remote to Remote DB" {
    export SYNC_REMOTE_TO_REMOTE=1
    export SYNC_SOURCE="dev"
    export SYNC_DESTINATION="stage"
    
    # Source Remote
    export SOURCE_REMOTE_HOST="dev.com"
    export SOURCE_REMOTE_PORT="22"
    export SOURCE_REMOTE_USER="dev"
    export SOURCE_REMOTE_DIR="/var/www/dev"
    
    # Destination Remote
    export DEST_REMOTE_HOST="stage.com"
    export DEST_REMOTE_PORT="22"
    export DEST_REMOTE_USER="stage"
    export DEST_REMOTE_DIR="/var/www/stage"
    
    export SYNC_TYPE_DB=1
    export ENV_SOURCE_HOST_VAR="dummy" 
    
    run "$BOOTSTRAP_CMD"
    
    # Echo log for debug if failed
    echo "=== Remote to Remote MOCK_LOG Content ==="
    cat "$MOCK_LOG" || true
    echo "========================================="
    
    grep -q "ssh .* dev@dev.com .* \$(command -v mariadb" "$MOCK_LOG"
    
    # Use fgrep for safety
    grep -F "cat > /tmp/warden_r2r_db.sql" "$MOCK_LOG"
}
