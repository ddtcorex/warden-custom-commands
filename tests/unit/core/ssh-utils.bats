#!/usr/bin/env bats

load "../test_helper/bats-support/load"
load "../test_helper/bats-assert/load"

setup() {
    source "${BATS_TEST_DIRNAME}/../../../lib/ssh-utils.sh"
}

@test "build_ssh_opts: returns default secure options" {
    unset SSH_AUTH_SOCK
    unset WARDEN_SSH_IDENTITIES_ONLY
    unset WARDEN_SSH_IDENTITY_FILE
    
    run build_ssh_opts
    
    assert_output --partial "-o StrictHostKeyChecking=no"
    assert_output --partial "-o UserKnownHostsFile=/dev/null"
    assert_output --partial "-o LogLevel=ERROR"
    assert_output --partial "-o BatchMode=yes"
    refute_output --partial "-A"
    refute_output --partial "-i"
}

@test "build_ssh_opts: adds forwarding agent if SSH_AUTH_SOCK is present" {
    export SSH_AUTH_SOCK="/tmp/ssh-agent.sock"
    
    run build_ssh_opts
    
    assert_output --partial "-A"
}

@test "build_ssh_opts: adds identities only if enabled" {
    export WARDEN_SSH_IDENTITIES_ONLY=1
    
    run build_ssh_opts
    
    assert_output --partial "-o IdentitiesOnly=yes"
}

@test "build_ssh_opts: adds identity file if provided" {
    export WARDEN_SSH_IDENTITY_FILE="/path/to/key.pem"
    
    run build_ssh_opts
    
    assert_output --partial "-i /path/to/key.pem"
}

@test "normalize_env_name: maps aliases correctly" {
    run normalize_env_name "production"
    assert_output "PROD"
    
    run normalize_env_name "stag"
    assert_output "STAGING"
    
    run normalize_env_name "preprod"
    assert_output "STAGING"
    
    run normalize_env_name "develop"
    assert_output "DEV"

    run normalize_env_name "custom"
    assert_output "CUSTOM"
}

@test "get_remote_env: exports variables when host is set" {
    export REMOTE_TEST_HOST="example.com"
    export REMOTE_TEST_USER="user"
    export REMOTE_TEST_PORT="2222"
    
    run get_remote_env "TEST"
    
    assert_output --partial "export ENV_SOURCE_HOST='example.com'"
    assert_output --partial "export ENV_SOURCE_USER='user'"
    assert_output --partial "export ENV_SOURCE_PORT='2222'"
}

@test "get_remote_env: returns failure for invalid prefix" {
    run get_remote_env "NONEXISTENT"
    [ "$status" -eq 1 ]
}

@test "get_remote_env: uses custom variable prefix" {
    export REMOTE_TEST_HOST="host"
    
    run get_remote_env "TEST" "CUSTOM_VAR"
    
    assert_output --partial "export CUSTOM_VAR_HOST='host'"
}
