#!/usr/bin/env bash
# helpers.sh - Common utilities for integration tests

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0

# Test environment paths
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ROOT="$(cd "${TEST_DIR}/.." && pwd)"
LOCAL_ENV="${TEST_DIR}/project-local"
DEV_ENV="${TEST_DIR}/project-dev"
STAGING_ENV="${TEST_DIR}/project-staging"

# Container names
LOCAL_PHP="project-local-php-fpm-1"
DEV_PHP="project-dev-php-fpm-1"
STAGING_PHP="project-staging-php-fpm-1"

LOCAL_DB="project-local-db-1"
DEV_DB="project-dev-db-1"
STAGING_DB="project-staging-db-1"

# Print test result
function pass() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
    ((TESTS_PASSED++))
}

function fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    echo -e "  ${YELLOW}Reason${NC}: $2"
    ((TESTS_FAILED++))
}

function skip() {
    echo -e "${YELLOW}○ SKIP${NC}: $1"
}

function header() {
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}$1${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

function summary() {
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}TEST SUMMARY${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Passed${NC}: ${TESTS_PASSED}"
    echo -e "${RED}Failed${NC}: ${TESTS_FAILED}"
    echo ""
    if [[ ${TESTS_FAILED} -gt 0 ]]; then
        echo -e "${RED}Some tests failed!${NC}"
        return 1
    else
        echo -e "${GREEN}All tests passed!${NC}"
        return 0
    fi
}

# Execute command in container
function exec_in_local() {
    docker exec "${LOCAL_PHP}" bash -c "$1"
}

function exec_in_dev() {
    docker exec "${DEV_PHP}" bash -c "$1"
}

function exec_in_staging() {
    docker exec "${STAGING_PHP}" bash -c "$1"
}

# Create test file in container
function create_test_file() {
    local container="$1"
    local path="$2"
    local content="${3:-test content}"
    docker exec "${container}" bash -c "mkdir -p \$(dirname '${path}') && echo '${content}' > '${path}'"
}

# Check if file exists in container
function file_exists() {
    local container="$1"
    local path="$2"
    docker exec "${container}" test -e "${path}"
}

# Get file content from container
function get_file_content() {
    local container="$1"
    local path="$2"
    docker exec "${container}" cat "${path}" 2>/dev/null
}

# Remove file from container
function remove_file() {
    local container="$1"
    local path="$2"
    docker exec "${container}" rm -rf "${path}" 2>/dev/null || true
}

# Clean up test artifacts from all containers
function cleanup_test_files() {
    for container in "${LOCAL_PHP}" "${DEV_PHP}" "${STAGING_PHP}"; do
        docker exec "${container}" bash -c "rm -rf /var/www/html/test_* /var/www/html/pub/media/test_* 2>/dev/null" || true
    done
}

# Check if environments are running
function check_environments() {
    local all_running=1
    for container in "${LOCAL_PHP}" "${DEV_PHP}" "${STAGING_PHP}"; do
        if ! docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
            echo -e "${RED}Container ${container} is not running${NC}"
            all_running=0
        fi
    done
    return $((1 - all_running))
}

# Run warden sync command in local environment
function run_sync() {
    cd "${LOCAL_ENV}" && warden sync -y "$@" 2>&1
}

# Run sync with auto-confirm (for upload/r2r prompts)
function run_sync_confirmed() {
    cd "${LOCAL_ENV}" && yes y | warden sync "$@" 2>&1
}

# Setup a mock Magento env.php file in a container
# This is required because warden sync reads DB credentials from app/etc/env.php
function setup_mock_magento_env() {
    local container="$1"
    local db_host="${2:-db}"
    local db_name="${3:-magento}"
    local db_user="${4:-magento}"
    local db_pass="${5:-magento}"

    docker exec "${container}" bash -c "mkdir -p /var/www/html/app/etc && cat > /var/www/html/app/etc/env.php <<EOF
<?php
return [
    'db' => [
        'table_prefix' => '',
        'connection' => [
            'default' => [
                'host' => '${db_host}',
                'dbname' => '${db_name}',
                'username' => '${db_user}',
                'password' => '${db_pass}',
                'model' => 'mysql4',
                'engine' => 'innodb',
                'initStatements' => 'SET NAMES utf8;',
                'active' => '1',
                'driver_options' => [
                    1014 => false
                ]
            ]
        ]
    ]
];
EOF
"
}

# Connect networks specifically for R2R testing
# project-dev needs to be able to talk to project-staging
function connect_remote_networks() {
    docker network connect project-staging_default project-dev-php-fpm-1 2>/dev/null || true
    docker network connect project-dev_default project-staging-php-fpm-1 2>/dev/null || true
}

# Run a query in a container's database
function run_db_query() {
    local container="$1"
    local query="$2"
    
    # Map PHP container to its corresponding DB container
    local db_container=""
    case "${container}" in
        "${LOCAL_PHP}") db_container="${LOCAL_DB}" ;;
        "${DEV_PHP}") db_container="${DEV_DB}" ;;
        "${STAGING_PHP}") db_container="${STAGING_DB}" ;;
        *) db_container="${container}" ;; # Fallback if passed DB container directly
    esac

    # Note: we assume default Warden credentials (magento/magento/magento)
    # Using -N (no headers), -s (silent), -r (raw) for easy parsing. 
    # Since we are in the DB container, host is localhost.
    # We filter out MySQL deprecation warnings to avoid poisoning results.
    docker exec "${db_container}" mysql -h localhost -u magento -pmagento magento -N -s -r -e "${query}" 2>&1 \
        | grep -v "Deprecated program name" | grep -v "use /usr/bin/mariadb instead"
}

