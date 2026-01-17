#!/usr/bin/env bats

load "../../libs/mocks.bash"

setup() {
    setup_mocks
    export WARDEN_DIR="${TEST_TMP_DIR}/warden"
    export WARDEN_HOME_DIR="${TEST_TMP_DIR}/warden_home"
    mkdir -p "${WARDEN_DIR}/commands" "${WARDEN_HOME_DIR}/commands/patches"
    
    SELF_UPDATE_CMD="${BATS_TEST_DIRNAME}/../../../self-update.cmd"
    
    # Mock git
    function git() {
        if [[ "$*" =~ "status --porcelain" ]]; then
            return 0 
        fi
        
        if [[ "$*" =~ "rev-parse --abbrev-ref HEAD" ]]; then
            echo "master"
            return 0
        fi

        echo "git-mock: $*"
    }
    export -f git
    
    function warden() { echo "warden-mock: $*"; }
    export -f warden
    
    function patch() { echo "patch-mock: $*"; }
    export -f patch
    
    # Create dummy patch file
    touch "${WARDEN_HOME_DIR}/commands/patches/warden-fix-file-permissions.patch"
}

teardown() {
    rm -rf "${TEST_TMP_DIR}"
}

@test "self-update: stops if dirty" {
    function git() {
        echo "git-mock: $*"
        if [[ "$*" =~ "status --porcelain" ]]; then
            echo "M file"
            return 0
        fi
    }
    export -f git
    
    run "${SELF_UPDATE_CMD}"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "repository has local changes" ]]
}

@test "self-update: full flow success" {
    run "${SELF_UPDATE_CMD}"
    
    echo "$output"
    [ "$status" -eq 0 ]
    
    # Verify Warden Update
    [[ "$output" =~ "git-mock: -C ${WARDEN_DIR} fetch origin" ]]
    [[ "$output" =~ "git-mock: -C ${WARDEN_DIR} reset --hard origin/master" ]]
    
    # Verify Custom Commands Update
    [[ "$output" =~ "git-mock: -C ${WARDEN_HOME_DIR}/commands fetch origin" ]]
    
    # Verify Services
    [[ "$output" =~ "warden-mock: svc pull" ]]
    [[ "$output" =~ "warden-mock: svc up --remove-orphans" ]]
    
    # Verify Patching
    # The dry-run is silenced, so we can only see the actual application
    [[ "$output" =~ "patch-mock: -N -s" ]]
}
