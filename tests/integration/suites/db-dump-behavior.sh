#!/usr/bin/env bash
header "DB Dump Behavior Tests"

test_db_dump_no_warnings() {
    cd "${LOCAL_ENV}"
    
    # Run db dump and capture stderr
    local dump_output
    
    # Check local dump warnings
    dump_output=$(warden db-dump -e local --force 2>&1) || true
    
    if echo "${dump_output}" | grep -q "Deprecated program name"; then
        fail "db-dump warnings" "Found deprecated program warning (local)"
    else
        pass "db-dump (local) suppressed deprecated warnings"
    fi
    
    # Check remote dump warnings
    setup_mock_env "${DEV_PHP}"
    dump_output=$(warden db-dump -e dev --force 2>&1) || true
     if echo "${dump_output}" | grep -q "Deprecated program name"; then
        fail "db-dump warnings" "Found deprecated program warning (remote)"
    else
        pass "db-dump (remote) suppressed deprecated warnings"
    fi
}

test_db_dump_local_default() {
    cd "${LOCAL_ENV}"
    
    mkdir -p var
    rm -f var/*.sql.gz
    
    local dump_output
    dump_output=$(warden db-dump -e local 2>&1)
    
    if ls var/*_local-*.sql.gz >/dev/null 2>&1; then
         pass "db-dump -e local (default) created file in var/ with correct name"
    else
         fail "db-dump -e local" "File with pattern *_local-*.sql.gz not found in var/. Output: ${dump_output}"
    fi
}

test_db_dump_remote_default() {
    # 1. Run db-dump on remote (dev), expect file on remote ~/backup
    local dump_output
    cd "${LOCAL_ENV}"
    
    # Ensure Dev environment is up
    if ! docker ps | grep -q "${DEV_PHP}"; then
         fail "Dev environment not running"
         return
    fi
    
    local remote_path="~/backup"
    
    # Clean remote storage
    docker exec "${DEV_PHP}" bash -c "rm -rf ~/backup"
    
    # Ensure remote .env exists for DB detection
    setup_mock_env "${DEV_PHP}"
    
    dump_output=$(warden db-dump -e dev 2>&1)
    
    if echo "${dump_output}" | grep -q "Database dump complete! File:"; then
        # Check if file exists on remote
        if docker exec "${DEV_PHP}" bash -c "ls -1 ${remote_path}/*.sql.gz" >/dev/null 2>&1; then
            pass "db-dump -e dev (default) stored file on remote ${remote_path}"
            
            # Check filename format (should include _dev-)
            local files=$(docker exec "${DEV_PHP}" bash -c "ls -1 ${remote_path}/*.sql.gz")
            if echo "$files" | grep -q "_dev-"; then
                  pass "db-dump filename format correct (contains _dev-)"
            else
                  fail "db-dump filename format" "File $files does not contain '_dev-'"
            fi
        else
            fail "db-dump -e dev (default)" "File not found on remote ${remote_path}/"
        fi
    else
        fail "db-dump -e dev (default)" "Command failed: ${dump_output}"
    fi
}

test_db_dump_remote_local() {
    # 2. Run db-dump -e dev --local, expect file on local host
    cd "${LOCAL_ENV}"
    
    # Ensure var/ exists locally
    mkdir -p var
    rm -f var/*.sql.gz
    
    # Ensure remote .env exists for DB detection
    setup_mock_env "${DEV_PHP}"

    local dump_output
    dump_output=$(warden db-dump -e dev --local 2>&1)
    
    # Check for local file existence with correct name
    if ls var/*_dev-*.sql.gz >/dev/null 2>&1; then
         pass "db-dump -e dev --local downloaded file to local var/ with correct name"
    else
         fail "db-dump -e dev --local" "File with pattern *_dev-*.sql.gz not found in local var/. Output: ${dump_output}"
    fi
}

test_db_dump_no_warnings
test_db_dump_local_default
test_db_dump_remote_default
test_db_dump_remote_local
