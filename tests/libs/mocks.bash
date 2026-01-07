# tests/libs/mocks.bash

# Define where we capture commands
export MOCK_LOG="${BATS_TMPDIR}/mock_log"

setup_mocks() {
    export WARDEN_ENV_PATH="${BATS_TMPDIR}/warden-env"
    export WARDEN_HOME_DIR="${BATS_TMPDIR}/warden-home"
    export TRAEFIK_DOMAIN="test.localhost"
    export TRAEFIK_SUBDOMAIN="app"
    export WARDEN_WEB_ROOT="${BATS_TMPDIR}/warden-web-root"
    
    mkdir -p "$WARDEN_ENV_PATH"
    mkdir -p "$WARDEN_HOME_DIR"
    mkdir -p "$WARDEN_WEB_ROOT"
    
    # Reset log
    echo "" > "$MOCK_LOG"
    
    # Mock warden
    function warden() {
        echo "warden $*" >> "$MOCK_LOG"
        
        # Mock printenv output for Symfony tests
        if [[ "$*" == *"printenv MYSQL_"* ]]; then
            echo "test_db_value"
            return 0
        fi

        # Simulate success for specific commands if validation depends on them
        if [[ "$*" == *"svc up"* ]] || [[ "$*" == *"env up"* ]] || [[ "$*" == *"test -f"* ]]; then
            return 0
        fi
    }
    
    # Mock docker
    function docker() {
        echo "docker $*" >> "$MOCK_LOG"
    }

    # Mock version check utility if not present
    if ! type version &>/dev/null; then
        function version() {
            echo "$1"
        }
    fi
    
    # Mock specific helpers that might be called
    function fatal() {
        echo "FATAL: $*" >&2
        exit 1
    }
    
    function warning() {
        echo "WARNING: $*" >&2
    }
    
    function error() {
        echo "ERROR: $*" >&2
    }

    export -f warden docker version fatal warning error
}

assert_command_called() {
    local cmd="$1"
    if ! grep -F -- "$cmd" "$MOCK_LOG"; then
        echo "Expected command not called: $cmd"
        echo "Log content:"
        cat "$MOCK_LOG"
        return 1
    fi
}

assert_command_not_called() {
    local cmd="$1"
    if grep -q "$cmd" "$MOCK_LOG"; then
        echo "Unexpected command called: $cmd"
        return 1
    fi
}
