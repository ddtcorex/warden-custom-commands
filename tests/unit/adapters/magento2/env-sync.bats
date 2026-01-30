#!/usr/bin/env bats

load "../../../libs/mocks.bash"

setup() {
    setup_mocks
    
    export TEST_SCRIPT_DIR="${TEST_TMP_DIR}/magento2-sync"
    mkdir -p "${TEST_SCRIPT_DIR}"
    
    cp "${BATS_TEST_DIRNAME}/../../../../env-adapters/magento2/env-sync.cmd" "${TEST_SCRIPT_DIR}/env-sync.cmd"
    cp "${BATS_TEST_DIRNAME}/../../../../env-adapters/magento2/utils.sh" "${TEST_SCRIPT_DIR}/utils.sh"
    chmod +x "${TEST_SCRIPT_DIR}/env-sync.cmd"
    
    BOOTSTRAP_CMD="${TEST_SCRIPT_DIR}/env-sync.cmd"
    
    export WARDEN_ENV_NAME="magento2-test"
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
    export SYNC_REMOTE_TO_REMOTE="0"
    export SYNC_INCLUDE_PRODUCT="0"
    export SYNC_BACKUP="0"
    export SYNC_BACKUP_DIR="~/backup"
    
    export MOCK_BIN="${TEST_TMP_DIR}/mock-bin"
    mkdir -p "${MOCK_BIN}"
    
    function warden() {
        echo "warden $*" >> "$MOCK_LOG"
        if [[ "$1" == "remote-exec" ]]; then
            shift 4
            echo "warden-remote-exec $*" >> "$MOCK_LOG"
            if [[ "$*" == *"php -r"* ]] && [[ "$*" == *"json_encode"* ]]; then
                 # Return base64 json for db info
                 echo "eyJob3N0IjoicmVtb3RlLWRiOjMzMDYiLCJ1c2VybmFtZSI6InJlbW90ZV91c2VyIiwicGFzc3dvcmQiOiJyZW1vdGVfcGFzcyIsImRibmFtZSI6InJlbW90ZV9kYiJ9"
            fi
            return 0
        fi

        if [[ "$*" == *"printenv MYSQL_USER"* ]]; then
            echo "local_user"
        elif [[ "$*" == *"printenv MYSQL_PASSWORD"* ]]; then
            echo "local_pass"
        elif [[ "$*" == *"printenv MYSQL_DATABASE"* ]]; then
            echo "local_db"
        elif [[ "$*" == *"db-dump"* ]] && [[ "$*" == *"-f"* ]]; then
            # Extract filename and create a dummy dump file for upload tests
            local dump_file=$(echo "$*" | grep -oE '[^ ]+\.sql\.gz' | head -1)
            if [[ -n "${dump_file}" ]]; then
                mkdir -p "$(dirname "${dump_file}")"
                echo "dummy dump" | gzip > "${dump_file}"
            fi
        fi
        return 0
    }
    export -f warden

    # Mock lsof
    cat > "${MOCK_BIN}/lsof" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
    chmod +x "${MOCK_BIN}/lsof"
    
    cat > "${MOCK_BIN}/ssh" << 'EOF'
#!/usr/bin/env bash
echo "ssh $*" >> "${MOCK_LOG}"
if [[ "$*" == *"rsync"* ]]; then
    echo "Remote rsync triggered"
fi
EOF
    chmod +x "${MOCK_BIN}/ssh"

    # Mock php to decode
    cat > "${MOCK_BIN}/php" << 'EOF'
#!/usr/bin/env bash
code="$2"
if echo "$code" | grep -q "3306"; then
    echo "3306"
elif echo "$code" | grep -q "host"; then
    echo "remote-db"
elif echo "$code" | grep -q "dbname"; then
    echo "remote_db"
elif echo "$code" | grep -q "username"; then
    echo "remote_user"
elif echo "$code" | grep -q "password"; then
    echo "remote_pass"
fi
EOF
    chmod +x "${MOCK_BIN}/php"

    export PATH="${MOCK_BIN}:${PATH}"
    
    cd "${TEST_SCRIPT_DIR}"
}

@test "Magento2 Sync: File Download" {
    export ENV_SOURCE="dev"
    export ENV_SOURCE_HOST="example.com"
    export ENV_SOURCE_PORT="22"
    export ENV_SOURCE_USER="user"
    export ENV_SOURCE_DIR="/var/www/remote"
    export ENV_SOURCE_HOST_VAR="REMOTE_DEV_HOST"
    export REMOTE_DEV_HOST="dummy"
    
    export DIRECTION="download"
    export SYNC_TYPE_FILE=1
    
    run "$BOOTSTRAP_CMD"
    
    if [[ "$status" -ne 0 ]]; then
        echo "Command failed with status $status"
        echo "Output: $output"
    fi

    # Expect warden remote-exec for download using direct rsync
    # Since we switched to running rsync on host, we won't see "warden env exec -T php-fpm rsync"
    
    if grep -q "warden env exec -T php-fpm rsync" "$MOCK_LOG"; then
         echo "FAIL: Found old rsync invocation"
         return 1
    fi
}

@test "Magento2 Sync: DB Download" {
    export ENV_SOURCE="dev"
    export ENV_SOURCE_HOST="example.com"
    export ENV_SOURCE_PORT="22"
    export ENV_SOURCE_USER="user"
    export ENV_SOURCE_DIR="/var/www/remote"
    export ENV_SOURCE_HOST_VAR="REMOTE_DEV_HOST"
    export REMOTE_DEV_HOST="dummy"
    
    export DIRECTION="download"
    export SYNC_TYPE_DB=1
    
    run "$BOOTSTRAP_CMD"
    
    # Check for mysqldump with --force flag and db host (use -E for extended regex)
    grep -q "warden-remote-exec.*\\\$(command -v mariadb" "$MOCK_LOG"
    grep -Fq 'export MYSQL_PWD="$MYSQL_PASSWORD"' "$MOCK_LOG"
    grep -Fq 'SET FOREIGN_KEY_CHECKS=0' "$MOCK_LOG"
    grep -Fq 'mariadb || echo mysql' "$MOCK_LOG"
}

@test "Magento2 Sync: DB Download with Backup" {
    export ENV_SOURCE="dev"
    export ENV_SOURCE_HOST="example.com"
    export ENV_SOURCE_PORT="22"
    export ENV_SOURCE_USER="user"
    export ENV_SOURCE_DIR="/var/www/remote"
    export ENV_SOURCE_HOST_VAR="REMOTE_DEV_HOST"
    export REMOTE_DEV_HOST="dummy"
    
    export DIRECTION="download"
    export SYNC_TYPE_DB=1
    export SYNC_BACKUP=1
    export SYNC_BACKUP_DIR="${TEST_TMP_DIR}/backup"
    
    run "$BOOTSTRAP_CMD"
    
    # Expect warden db-dump call without --file
    grep -q "warden db-dump -e local" "$MOCK_LOG"
    if grep -q "warden db-dump -e local --file" "$MOCK_LOG"; then
        echo "FAIL: Found --file argument"
        return 1
    fi
}

@test "Magento2 Sync: DB Upload with Backup" {
    export ENV_SOURCE="dev"
    export ENV_SOURCE_HOST="example.com"
    export ENV_SOURCE_PORT="22"
    export ENV_SOURCE_USER="user"
    export ENV_SOURCE_DIR="/var/www/remote"
    export ENV_SOURCE_HOST_VAR="REMOTE_DEV_HOST"
    export REMOTE_DEV_HOST="dummy"
    
    export DIRECTION="upload"
    export SYNC_DESTINATION="remote-test"
    export SYNC_TYPE_DB=1
    export SYNC_BACKUP=1
    export SYNC_BACKUP_DIR="~/backup"
    
    run "$BOOTSTRAP_CMD"
    
    # Expect warden db-dump call for destination backup
    grep -q "warden db-dump -e remote-test" "$MOCK_LOG"
}

@test "Magento2 Sync: DB Upload resets destination database" {
    export ENV_SOURCE="dev"
    export ENV_SOURCE_HOST="example.com"
    export ENV_SOURCE_PORT="22"
    export ENV_SOURCE_USER="user"
    export ENV_SOURCE_DIR="/var/www/remote"
    export ENV_SOURCE_HOST_VAR="REMOTE_DEV_HOST"
    export REMOTE_DEV_HOST="dummy"
    
    export DIRECTION="upload"
    export SYNC_DESTINATION="remote-test"
    export SYNC_TYPE_DB=1
    export SYNC_BACKUP=0
    
    run "$BOOTSTRAP_CMD"
    
    # Expect warden remote-exec call with DROP DATABASE and CREATE DATABASE
    grep -q "warden-remote-exec.*DROP DATABASE IF EXISTS" "$MOCK_LOG"
    grep -q "warden-remote-exec.*CREATE DATABASE" "$MOCK_LOG"
}
