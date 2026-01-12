#!/usr/bin/env bats

load "../../libs/mocks.bash"

setup() {
    export WARDEN_DIR="/tmp/warden-mock"
    export SUBCOMMAND_DIR="/tmp/warden-cmd-mock"
    mkdir -p "$WARDEN_DIR" "$SUBCOMMAND_DIR"
    
    # Path to the script under test
    SETUP_REMOTES_CMD="${BATS_TEST_DIRNAME}/../../../setup-remotes.cmd"
    
    # Create a dummy .env file
    touch .env
}

teardown() {
    rm -rf "$WARDEN_DIR"
    rm -f .env
}

@test "setup-remotes.cmd: aborts if .env is missing" {
    rm .env
    run "${SETUP_REMOTES_CMD}"
    
    # Expect error output
    [[ "$output" =~ "Error: .env file not found" ]]
    [ "$status" -eq 1 ]
}

@test "setup-remotes.cmd: does nothing if user says no" {
    # Simulate "n" as input
    run bash -c "printf 'n\n' | ${SETUP_REMOTES_CMD}"
    
    [ "$status" -eq 0 ]
    
    # Should not find REMOTE_STAGING_HOST in .env
    run grep "REMOTE_STAGING_HOST" .env
    [ "$status" -eq 1 ]
}

@test "setup-remotes.cmd: configures staging correctly" {
    # Inputs:
    # 1. y (Yes, I want to configure)
    # 2. staging.host (Host)
    # 3. user (User)
    # 4. 2222 (Port)
    # 5. /var/www (Path)
    # 6. https://staging.com (URL)
    # 7. (Empty for production host -> skip)
    # 8. (Empty for development host -> skip)
    
    run bash -c "printf 'y\nstaging.host\nuser\n2222\n/var/www\nhttps://staging.com\n\n\n' | ${SETUP_REMOTES_CMD}"
    
    [ "$status" -eq 0 ]
    
    # Check .env content
    grep "REMOTE_STAGING_HOST=staging.host" .env
    grep "REMOTE_STAGING_USER=user" .env
    grep "REMOTE_STAGING_PORT=2222" .env
    grep "REMOTE_STAGING_PATH=/var/www" .env
    grep "REMOTE_STAGING_URL=https://staging.com" .env
    
    # Should NOT have production or dev variables
    ! grep "REMOTE_PROD_HOST=" .env
}

@test "setup-remotes.cmd: skips existing variables" {
    # Pre-populate .env
    echo "REMOTE_STAGING_HOST=existing.host" >> .env
    
    # Inputs: y, tries to enter staging.host again
    run bash -c "printf 'y\nstaging.new\n\n\n\n\n\n' | ${SETUP_REMOTES_CMD}"
    
    # Should NOT update to staging.new because it checks for REMOTE_STAGING_HOST
    # Note: The script logic is `if grep -q ... return`.
    
    grep "REMOTE_STAGING_HOST=existing.host" .env
    ! grep "REMOTE_STAGING_HOST=staging.new" .env
}
