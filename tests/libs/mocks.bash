# tests/libs/mocks.bash

# Find the root of the commands directory (parent of tests/)
MOCKS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export COMMANDS_ROOT_DIR="$(cd "${MOCKS_SCRIPT_DIR}/../.." && pwd)"

# Define test temp directory within tests folder
export TEST_TMP_DIR="${COMMANDS_ROOT_DIR}/tests/.tmp"
mkdir -p "${TEST_TMP_DIR}"

# Define where we capture commands
export MOCK_LOG="${TEST_TMP_DIR}/mock_log"

setup_mocks() {
    export WARDEN_ENV_PATH="${TEST_TMP_DIR}/warden-env"
    export WARDEN_HOME_DIR="${TEST_TMP_DIR}/warden-home"
    export TRAEFIK_DOMAIN="test.localhost"
    export TRAEFIK_SUBDOMAIN="app"
    export WARDEN_WEB_ROOT="${TEST_TMP_DIR}/warden-web-root"
    
    # Common Warden environment variables (with defaults for set -u compliance)
    export WARDEN_ENV_NAME="${WARDEN_ENV_NAME:-test-project}"
    export WARDEN_ENV_TYPE="${WARDEN_ENV_TYPE:-magento2}"
    export WARDEN_ELASTICSEARCH="${WARDEN_ELASTICSEARCH:-0}"
    export WARDEN_OPENSEARCH="${WARDEN_OPENSEARCH:-1}"
    export WARDEN_VARNISH="${WARDEN_VARNISH:-0}"
    export WARDEN_REDIS="${WARDEN_REDIS:-1}"
    export DB_PREFIX="${DB_PREFIX:-}"
    export MYSQL_DISTRIBUTION="${MYSQL_DISTRIBUTION:-mariadb}"
    export OSTYPE="${OSTYPE:-linux-gnu}"
    export VERBOSE="${VERBOSE:-0}"
    
    mkdir -p "$WARDEN_ENV_PATH"
    mkdir -p "$WARDEN_HOME_DIR/commands/lib"
    mkdir -p "$WARDEN_WEB_ROOT"
    
    # Copy error-handling library to mock commands directory
    # This is needed because env-variables now sources it
    if [[ -f "${COMMANDS_ROOT_DIR}/lib/error-handling.sh" ]]; then
        cp "${COMMANDS_ROOT_DIR}/lib/error-handling.sh" "${WARDEN_HOME_DIR}/commands/lib/"
    fi
    
    # Reset log
    echo "" > "$MOCK_LOG"
    
    # Mock warden
    function warden() {
        echo "warden $*" >> "$MOCK_LOG"
        
        # Handle DB info query (Magento 2 db-dump uses single bash -c call)
        if [[ "$*" == *"MYSQL_USER="* ]]; then
            echo "MYSQL_USER=db_user"
            echo "MYSQL_PASSWORD=db_pass"
            echo "MYSQL_DATABASE=test_db"
            return 0
        fi
        
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
    
    function info() {
        echo "INFO: $*"
    }
    
    # Mock section header function
    function ::() {
        echo ":: $*"
    }

    export -f warden docker version fatal warning error info ::
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
