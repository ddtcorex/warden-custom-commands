#!/usr/bin/env bats

load "../../../libs/mocks.bash"

setup() {
    setup_mocks
    
    export TEST_SCRIPT_DIR="${TEST_TMP_DIR}/wordpress-sync"
    mkdir -p "${TEST_SCRIPT_DIR}"
    
    cp "${BATS_TEST_DIRNAME}/../../../../env-adapters/wordpress/sync.cmd" "${TEST_SCRIPT_DIR}/sync.cmd"
    cp "${BATS_TEST_DIRNAME}/../../../../env-adapters/wordpress/utils.sh" "${TEST_SCRIPT_DIR}/utils.sh"
    chmod +x "${TEST_SCRIPT_DIR}/sync.cmd"
    
    BOOTSTRAP_CMD="${TEST_SCRIPT_DIR}/sync.cmd"
    
    export WARDEN_ENV_NAME="wordpress-test"
    export WARDEN_ENV_PATH="${TEST_SCRIPT_DIR}"
    export SSH_OPTS="-o StrictHostKeyChecking=no"

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
    
    export MOCK_BIN="${TEST_TMP_DIR}/mock-bin"
    mkdir -p "${MOCK_BIN}"
    
    function warden() {
        echo "warden $*" >> "$MOCK_LOG"
        if [[ "$*" == *"printenv MYSQL_USER"* ]]; then
            echo "local_user"
        elif [[ "$*" == *"printenv MYSQL_PASSWORD"* ]]; then
            echo "local_pass"
        elif [[ "$*" == *"printenv MYSQL_DATABASE"* ]]; then
            echo "local_db"
        fi
        return 0
    }
    export -f warden

    cat > "${MOCK_BIN}/ssh" << 'EOF'
#!/usr/bin/env bash
echo "ssh $*" >> "${MOCK_LOG}"
if [[ "$*" == *"grep"* ]]; then
    # Helper for get_remote_db_info
    echo "define('DB_NAME', 'remote_db');"
    echo "define('DB_USER', 'remote_user');"
    echo "define('DB_PASSWORD', 'remote_pass');"
    echo "define('DB_HOST', 'remote-db:3306');"
elif [[ "$*" == *"rsync"* ]]; then
    echo "Remote rsync triggered"
fi
EOF
    chmod +x "${MOCK_BIN}/ssh"
    
    export PATH="${MOCK_BIN}:${PATH}"
    
    cd "${TEST_SCRIPT_DIR}"
}

@test "Wordpress Sync: File Download" {
    export ENV_SOURCE="dev"
    export ENV_SOURCE_HOST="example.com"
    export ENV_SOURCE_PORT="22"
    export ENV_SOURCE_USER="user"
    export ENV_SOURCE_DIR="/var/www/remote"
    export ENV_SOURCE_HOST_VAR="REMOTE_DEV_HOST"
    
    export DIRECTION="download"
    export SYNC_TYPE_FILE=1
    
    run "$BOOTSTRAP_CMD"
    
    grep -q "warden env exec php-fpm rsync" "$MOCK_LOG"
}

@test "Wordpress Sync: DB Download" {
    export ENV_SOURCE="dev"
    export ENV_SOURCE_HOST="example.com"
    export ENV_SOURCE_PORT="22"
    export ENV_SOURCE_USER="user"
    export ENV_SOURCE_DIR="/var/www/remote"
    export ENV_SOURCE_HOST_VAR="REMOTE_DEV_HOST"
    
    export DIRECTION="download"
    export SYNC_TYPE_DB=1
    
    run "$BOOTSTRAP_CMD"
    
    grep -q "ssh .* \$(command -v mariadb" "$MOCK_LOG"
    grep -Fq "warden env exec -T db bash -c \$(command -v mariadb || echo mysql) -hdb -u\"\$MYSQL_USER\" -p\"\$MYSQL_PASSWORD\" \"\$MYSQL_DATABASE\" -f" "$MOCK_LOG"
}
