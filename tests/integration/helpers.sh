#!/usr/bin/env bash
# helpers.sh - Shared functions and variables for integration tests

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Paths
TEST_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# Configuration Function
function configure_test_envs() {
    local type="${1:-magento2}"
    TEST_ENV_TYPE="$type"
    
    LOCAL_ENV="${TEST_DIR}/${type}-local"
    DEV_ENV="${TEST_DIR}/${type}-dev"
    STAGING_ENV="${TEST_DIR}/${type}-staging"

    # Container Names (calculated based on environment names)
    LOCAL_PHP="${type}-local-php-fpm-1"
    LOCAL_DB="${type}-local-db-1"
    DEV_PHP="${type}-dev-php-fpm-1"
    DEV_DB="${type}-dev-db-1"
    STAGING_PHP="${type}-staging-php-fpm-1"
    STAGING_DB="${type}-staging-db-1"
    
    # Environment IPs
    # Grab the first IP address found to avoid concatenation if multiple networks exist
    DEV_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' "${DEV_PHP}" 2>/dev/null | awk '{print $1}')
}

# Defaults (can be overridden by calling configure_test_envs)
configure_test_envs "magento2"

function get_app_root() {
    echo "/var/www/html"
}

# Check if containers are running
function check_environments() {
    # Check container status
    for container in "${LOCAL_PHP}" "${DEV_PHP}" "${STAGING_PHP}"; do
        if [[ "$(docker inspect -f '{{.State.Running}}' "${container}" 2>/dev/null)" != "true" ]]; then
            return 1
        fi
    done
    
    # Check directory existence
    for dir in "${LOCAL_ENV}" "${DEV_ENV}" "${STAGING_ENV}"; do
        if [[ ! -d "${dir}" ]]; then
            return 1
        fi
    done

    return 0
}

# Test Counters
TESTS_PASS=0
TESTS_FAIL=0

# Formatting
function header() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${YELLOW}$1${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

function pass() {
    echo -e "  ${GREEN}✓ PASS:${NC} $1"
    ((TESTS_PASS++))
}

function fail() {
    echo -e "  ${RED}✗ FAIL:${NC} $1"
    echo -e "  ${RED}Reason:${NC} $2"
    ((TESTS_FAIL++))
}

function skip() {
    echo -e "  ${YELLOW}○ SKIP:${NC} $1"
}

function test_summary() {
    header "TEST SUMMARY"
    echo -e "Passed: ${GREEN}${TESTS_PASS}${NC}"
    echo -e "Failed: ${RED}${TESTS_FAIL}${NC}"
    echo ""
    if [[ ${TESTS_FAIL} -eq 0 ]]; then
        echo -e "${GREEN}All tests passed!${NC}"
        return 0
    else
        echo -e "${RED}Some tests failed!${NC}"
        return 1
    fi
}

# File helpers
function create_test_file() {
    local container="$1"
    local path="$2"
    local content="${3:-test content}"
    # Use docker exec --workdir / to avoid warden wrapper issues
    # Added proper quoting for the inner path
    docker exec --workdir / "${container}" bash -c "mkdir -p \"$(dirname "${path}")\" && echo \"${content}\" > \"${path}\""
}

function file_exists() {
    local container="$1"
    local path="$2"
    docker exec --workdir / "${container}" [ -f "${path}" ]
}

function get_file_content() {
    local container="$1"
    local path="$2"
    docker exec --workdir / "${container}" cat "${path}" 2>/dev/null
}

function remove_file() {
    local container="$1"
    local path="$2"
    docker exec --workdir / "${container}" rm -rf "${path}" 2>/dev/null || true
}

function cleanup_test_files() {
    local media_path=$(get_media_path)
    for container in "${LOCAL_PHP}" "${DEV_PHP}" "${STAGING_PHP}"; do
        docker exec --workdir / "${container}" bash -c "rm -rf /var/www/html/test_* /var/www/html/${media_path}/test_* 2>/dev/null" || true
    done
}

# Run warden env-sync command
function run_sync() {
    (cd "${LOCAL_ENV}" && warden env-sync -y "$@")
}

function run_sync_confirmed() {
    run_sync "$@"
}

# Framework specific path/db helpers
function get_web_root() {
    case "${TEST_ENV_TYPE}" in
        magento2) echo "/var/www/html/pub" ;;
        laravel)  echo "/var/www/html/public" ;;
        symfony)  echo "/var/www/html/public" ;;
        wordpress) echo "/var/www/html" ;;
        *)        echo "/var/www/html" ;;
    esac
}

function get_media_path() {
    case "${TEST_ENV_TYPE}" in
        magento2) echo "pub/media" ;;
        laravel)  echo "storage/app/public" ;;
        symfony)  echo "public/uploads" ;;
        wordpress) echo "wp-content/uploads" ;;
        *)        echo "pub/media" ;;
    esac
}

function run_db_query() {
    local container="$1"
    local query="$2"
    local db_container=""
    
    case "${container}" in
        "${LOCAL_PHP}") db_container="${LOCAL_DB}" ;;
        "${DEV_PHP}") db_container="${DEV_DB}" ;;
        "${STAGING_PHP}") db_container="${STAGING_DB}" ;;
        *) db_container="${container}" ;;
    esac

    local db_user="magento"
    local db_pass="magento"
    local db_name="magento"

    if [[ "${TEST_ENV_TYPE}" == "wordpress" ]]; then
        db_user="wordpress"; db_pass="wordpress"; db_name="wordpress"
    elif [[ "${TEST_ENV_TYPE}" == "laravel" ]]; then
        db_user="laravel"; db_pass="laravel"; db_name="laravel"
    elif [[ "${TEST_ENV_TYPE}" == "symfony" ]]; then
        db_user="symfony"; db_pass="symfony"; db_name="symfony"
    fi

    docker exec --workdir / "${db_container}" bash -c '$(command -v mariadb || echo mysql) -u "$1" -p"$2" "$3" -N -s -r -e "$4"' -- "${db_user}" "${db_pass}" "${db_name}" "${query}"
}

# Mock env setups
function setup_mock_env() {
    local container="$1"
    case "${TEST_ENV_TYPE}" in
        magento2) setup_mock_magento_env "$@" ;;
        laravel)  setup_mock_laravel_env "$@" ;;
        symfony)  setup_mock_symfony_env "$@" ;;
        wordpress) setup_mock_wordpress_env "$@" ;;
    esac
}

function setup_mock_magento_env() {
    local container="$1"
    # Create app/etc/env.php for DB extraction tests
    docker exec --workdir / "${container}" bash -c "mkdir -p /var/www/html/app/etc && cat > /var/www/html/app/etc/env.php <<'EOF'
<?php
return [
    'db' => [
        'connection' => [
            'default' => [
                'host' => 'db',
                'dbname' => 'magento',
                'username' => 'magento',
                'password' => 'magento',
                'active' => '1',
            ]
        ]
    ]
];
EOF"
}

function setup_mock_laravel_env() {
    local container="$1"
    local db_host="$(echo "${container}" | sed 's/-php-fpm-1$/-db-1/')"

    docker exec -i --workdir / "${container}" bash -c "cat >> /var/www/html/.env <<EOF
DB_HOST=${db_host}
DB_DATABASE=laravel
DB_USERNAME=laravel
DB_PASSWORD=laravel
EOF"
}

function setup_mock_symfony_env() {
    local container="$1"
    local db_host="$(echo "${container}" | sed 's/-php-fpm-1$/-db-1/')"

    docker exec -i --workdir / "${container}" bash -c "cat > /var/www/html/.env.local <<EOF
DATABASE_URL=\"mysql://symfony:symfony@${db_host}:3306/symfony?serverVersion=8.0\"
EOF"
}

function setup_mock_wordpress_env() {
    local container="$1"
    # Derive DB host from PHP container name (replace -php-fpm-1 with -db-1)
    local db_host="$(echo "${container}" | sed 's/-php-fpm-1$/-db-1/')"

    # Create valid wp-config.php
    docker exec -i "${container}" bash -c "cat > /var/www/html/wp-config.php" <<EOF
<?php
define( 'DB_NAME', 'wordpress' );
define( 'DB_USER', 'wordpress' );
define( 'DB_PASSWORD', 'wordpress' );
define( 'DB_HOST', '${db_host}' );
define( 'DB_CHARSET', 'utf8' );
define( 'DB_COLLATE', '' );

define('AUTH_KEY',         'test-auth-key-1234567890abcdefghijklmnop');
define('SECURE_AUTH_KEY',  'test-secure-auth-key-1234567890abcdefgh');
define('LOGGED_IN_KEY',    'test-logged-in-key-1234567890abcdefghij');
define('NONCE_KEY',        'test-nonce-key-1234567890abcdefghijklmn');
define('AUTH_SALT',        'test-auth-salt-1234567890abcdefghijklmn');
define('SECURE_AUTH_SALT', 'test-secure-auth-salt-1234567890abcdefg');
define('LOGGED_IN_SALT',   'test-logged-in-salt-1234567890abcdefgh');
define('NONCE_SALT',       'test-nonce-salt-1234567890abcdefghijklm');

\$table_prefix = 'wp_';

define( 'WP_DEBUG', false );

if ( ! defined( 'ABSPATH' ) ) {
    define( 'ABSPATH', __DIR__ . '/' );
}

require_once ABSPATH . 'wp-settings.php';
EOF
}

function modify_config_file() {
    local container="$1"
    local path="$2"
    local content="$3"
    
    if [[ "${path}" == *".env"* ]]; then
        # Append to avoid breaking Warden variables
        docker exec "${container}" bash -c "echo '' >> ${path} && echo '${content}' >> ${path}"
    else
        docker exec "${container}" bash -c "echo '${content}' > ${path}"
    fi
}
