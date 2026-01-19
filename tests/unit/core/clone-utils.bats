#!/usr/bin/env bats

load "../../libs/mocks.bash"

setup() {
    setup_mocks
    
    # Source the clone-utils library
    export WARDEN_DIR="/path/to/warden"
    source "${BATS_TEST_DIRNAME}/../../../lib/clone-utils.sh"
}

teardown() {
    rm -rf "${TEST_TMP_DIR:?}"/*
}

@test "clone-utils: detect_env_type_from_remote returns magento2 when bin/magento exists" {
    # Mock warden remote-exec to simulate bin/magento exists
    function warden() {
        if [[ "$1" == "remote-exec" ]] && [[ "$*" == *"bin/magento"* ]]; then
            return 0
        fi
        return 1
    }
    export -f warden
    
    run detect_env_type_from_remote "staging"
    [ "$status" -eq 0 ]
    [ "$output" = "magento2" ]
}

@test "clone-utils: detect_env_type_from_remote returns laravel when artisan exists" {
    # Mock warden remote-exec to simulate artisan exists
    function warden() {
        if [[ "$1" == "remote-exec" ]] && [[ "$*" == *"artisan"* ]]; then
            return 0
        fi
        return 1
    }
    export -f warden
    
    run detect_env_type_from_remote "staging"
    [ "$status" -eq 0 ]
    [ "$output" = "laravel" ]
}

@test "clone-utils: detect_env_type_from_remote returns symfony when bin/console exists" {
    # Mock warden remote-exec to simulate bin/console exists
    function warden() {
        if [[ "$1" == "remote-exec" ]] && [[ "$*" == *"bin/console"* ]]; then
            return 0
        fi
        return 1
    }
    export -f warden
    
    run detect_env_type_from_remote "staging"
    [ "$status" -eq 0 ]
    [ "$output" = "symfony" ]
}

@test "clone-utils: detect_env_type_from_remote returns wordpress when wp-config.php exists" {
    # Mock warden remote-exec to simulate wp-config.php exists
    function warden() {
        if [[ "$1" == "remote-exec" ]] && [[ "$*" == *"wp-config.php"* ]]; then
            return 0
        fi
        return 1
    }
    export -f warden
    
    run detect_env_type_from_remote "staging"
    [ "$status" -eq 0 ]
    [ "$output" = "wordpress" ]
}

@test "clone-utils: detect_env_type_from_remote returns error when no framework detected" {
    # Mock warden remote-exec to always fail
    function warden() {
        return 1
    }
    export -f warden
    
    run detect_env_type_from_remote "staging"
    [ "$status" -eq 1 ]
}

@test "clone-utils: get_project_name returns lowercase directory name" {
    # Create a temp directory with uppercase letters
    local test_dir="${TEST_TMP_DIR}/MyProject"
    mkdir -p "${test_dir}"
    cd "${test_dir}"
    
    run get_project_name
    [ "$status" -eq 0 ]
    [ "$output" = "myproject" ]
}

@test "clone-utils: get_project_name converts underscores to hyphens" {
    # Create a temp directory with underscores
    local test_dir="${TEST_TMP_DIR}/my_project_name"
    mkdir -p "${test_dir}"
    cd "${test_dir}"
    
    run get_project_name
    [ "$status" -eq 0 ]
    [ "$output" = "my-project-name" ]
}

@test "clone-utils: validate_warden_env returns error when .env missing" {
    cd "${TEST_TMP_DIR}"
    rm -f .env
    
    run validate_warden_env
    [ "$status" -eq 1 ]
}

@test "clone-utils: validate_warden_env returns error when WARDEN_ENV_TYPE missing" {
    cd "${TEST_TMP_DIR}"
    echo "SOME_VAR=value" > .env
    
    run validate_warden_env
    [ "$status" -eq 1 ]
}

@test "clone-utils: validate_warden_env returns success when valid" {
    cd "${TEST_TMP_DIR}"
    echo "WARDEN_ENV_TYPE=magento2" > .env
    
    run validate_warden_env
    [ "$status" -eq 0 ]
}

@test "clone-utils: init_warden_env calls warden env-init" {
    # Mock warden to capture call
    function warden() {
        echo "warden $@" >> "$MOCK_LOG"
        return 0
    }
    export -f warden
    
    run init_warden_env "myproject" "magento2"
    [ "$status" -eq 0 ]
    grep -q "warden env-init myproject magento2" "$MOCK_LOG"
}

@test "clone-utils: detect_remote_version returns magento2 version" {
    function warden() {
        if [[ "$1" == "remote-exec" ]] && [[ "$*" == *"cat composer.json"* ]]; then
            echo '{'
            echo '    "require": {'
            echo '        "magento/product-community-edition": "2.4.6"'
            echo '    }'
            echo '}'
            return 0
        fi
        return 1
    }
    export -f warden
    
    run detect_remote_version "magento2" "dev"
    [ "$status" -eq 0 ]
    [ "$output" = "2.4.6" ]
}

@test "clone-utils: detect_remote_version returns laravel version" {
    function warden() {
        if [[ "$1" == "remote-exec" ]] && [[ "$*" == *"cat composer.json"* ]]; then
            echo '{"require": {"laravel/framework": "^9.0"}}'
            return 0
        fi
        return 1
    }
    export -f warden
    
    run detect_remote_version "laravel" "dev"
    [ "$status" -eq 0 ]
    [ "$output" = "9.0" ]
}

@test "clone-utils: detect_remote_version returns symfony version" {
    function warden() {
        if [[ "$1" == "remote-exec" ]] && [[ "$*" == *"cat composer.json"* ]]; then
            echo '{"require": {"symfony/framework-bundle": "6.0.*"}}'
            return 0
        fi
        return 1
    }
    export -f warden
    
    run detect_remote_version "symfony" "dev"
    [ "$status" -eq 0 ]
    [ "$output" = "6.0.*" ]
}

@test "clone-utils: detect_remote_version returns wordpress version" {
    function warden() {
        if [[ "$1" == "remote-exec" ]] && [[ "$*" == *"cat wp-includes/version.php"* ]]; then
            echo "<?php \$wp_version = '6.4.2';"
            return 0
        fi
        return 1
    }
    export -f warden
    
    run detect_remote_version "wordpress" "dev"
    [ "$status" -eq 0 ]
    [ "$output" = "6.4.2" ]
}
