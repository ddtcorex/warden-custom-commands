#!/usr/bin/env bats

load "../../libs/mocks.bash"

setup() {
    setup_mocks
    
    export WARDEN_DIR="${TEST_TMP_DIR}/warden-mock"
    REMOTE_EXEC_CMD="${BATS_TEST_DIRNAME}/../../../remote-exec.cmd"
    
    # Create required WARDEN_DIR structure
    mkdir -p "${WARDEN_DIR}/utils"
    
    # Mock env.sh
    cat > "${WARDEN_DIR}/utils/env.sh" <<EOF
locateEnvPath() {
    echo "${WARDEN_ENV_PATH}"
}
loadEnvConfig() {
    return 0
}
assertDockerRunning() {
    return 0
}
EOF
    
    # Mock .env in WARDEN_ENV_PATH
    cat > "${WARDEN_ENV_PATH}/.env" <<EOF
REMOTE_STAGING_HOST=staging.host
REMOTE_STAGING_USER=user
REMOTE_STAGING_PORT=22
REMOTE_STAGING_PATH=/var/www
REMOTE_PROD_HOST=prod.host
REMOTE_PROD_USER=produser
REMOTE_PROD_PORT=222
REMOTE_PROD_PATH=/var/www/prod
EOF
}

teardown() {
    rm -rf "${TEST_TMP_DIR}"
}

@test "remote-exec.cmd: aborts if no command specified" {
    run "${REMOTE_EXEC_CMD}"
    [[ "$output" =~ "Error: No command specified" ]]
    [ "$status" -eq 1 ]
}

@test "remote-exec.cmd: runs command on default staging" {
    function ssh() {
        echo "ssh $*"
    }
    export -f ssh
    
    run "${REMOTE_EXEC_CMD}" -v ls -la
    
    echo "Output: $output"
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Running on staging" ]]
    [[ "$output" =~ "staging.host" ]]
    [[ "$output" =~ "ls -la" ]]
    [[ "$output" =~ "user@staging.host" ]]
    [[ "$output" =~ "source ~/.bash_profile" ]]
    [[ "$output" =~ "cd /var/www" ]]
    [[ "$output" =~ "ls" ]]
    [[ "$output" =~ "-la" ]]
}

@test "remote-exec.cmd: runs command on production with -e" {
    function ssh() {
        echo "ssh $*"
    }
    export -f ssh
    
    run "${REMOTE_EXEC_CMD}" -v -e production echo hello
    
    echo "Output: $output"
    
    [ "$status" -eq 0 ]
    # 'production' argument is normalized to 'prod' by env-variables script
    [[ "$output" =~ "Running on prod" ]]
    [[ "$output" =~ "prod.host" ]]
    [[ "$output" =~ "echo hello" ]]
    [[ "$output" =~ "produser@prod.host" ]]
    [[ "$output" =~ "-p 222" ]]
    [[ "$output" =~ "echo" ]]
    [[ "$output" =~ "hello" ]]
}

@test "remote-exec.cmd: handles complex arguments" {
    function ssh() {
        echo "ssh $*"
    }
    export -f ssh
    
    run "${REMOTE_EXEC_CMD}" sh -c 'echo "hello world"'
    
    echo "Output: $output"
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "sh" ]]
    [[ "$output" =~ "-c" ]]
    # Quote escaping verification
    # Output matches what we expect from proper escaping: echo\ \"hello\ world\"
    [[ "$output" =~ "hello" ]]
    [[ "$output" =~ "world" ]]
}

@test "remote-exec.cmd: silent by default (no verbose)" {
    function ssh() {
        echo "ssh $*"
    }
    export -f ssh
    
    run "${REMOTE_EXEC_CMD}" ls -la
    
    echo "Output: $output"
    
    [ "$status" -eq 0 ]
    [[ ! "$output" =~ "Running on staging" ]]
    [[ "$output" =~ "ssh" ]]
}
