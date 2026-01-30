#!/usr/bin/env bash
# Strict mode inherited from env-variables
[[ ! "${WARDEN_DIR:-}" ]] && >&2 printf "\033[31mThis script is not intended to be run directly!\033[0m\n" && exit 1

START_TIME=$(date +%s)

# env-variables is already sourced by the root dispatcher

## configure command defaults
FRESH_INSTALL=
CLONE_MODE=
CODE_ONLY=
COMPOSER_INSTALL=1
SKIP_WP_INSTALL=
FIX_DEPS=
DB_DUMP=
DB_IMPORT=1
STREAM_DB=1
ENV_REQUIRED=

## argument parsing
while (( "$#" )); do
    case "$1" in
        # Primary Features
        -c|--clone)
            CLONE_MODE=1
            ENV_REQUIRED=1
            shift
            ;;
        --code-only)
            CODE_ONLY=1
            shift
            ;;
        --fresh|--clean-install|--fresh-install)
            FRESH_INSTALL=1
            COMPOSER_INSTALL=
            DB_IMPORT=
            shift
            ;;

        # Disable/Skip Options
        --no-db|--skip-db-import)
            DB_IMPORT=
            shift
            ;;
        --no-composer|--skip-composer-install)
            COMPOSER_INSTALL=
            shift
            ;;
        --no-wp-install|--skip-wp-install)
            SKIP_WP_INSTALL=1
            shift
            ;;
        --no-stream-db)
            STREAM_DB=
            shift
            ;;

        # Presets & Legacy
        --download-source)
            CLONE_MODE=1
            CODE_ONLY=1
            ENV_REQUIRED=1
            shift
            ;;

        # Database Configuration
        --db-dump|--db-dump=*)
            [[ "$1" == *=* ]] && DB_DUMP="${1#*=}" || { DB_DUMP="${2:-}"; shift; }
            shift
            ;;

        # Internal / Flags
        --fix-deps)
            FIX_DEPS=1
            shift
            ;;
        -y|--yes)
            export YES_TO_ALL=1
            shift
            ;;
        *)
            shift
            ;;
    esac
done

# Clone mode with --code-only disables DB sync
if [[ -n "${CLONE_MODE}" ]] && [[ -n "${CODE_ONLY}" ]]; then
    DB_IMPORT=
fi

# For backward compatibility
CLEAN_INSTALL="${FRESH_INSTALL}"
DOWNLOAD_SOURCE="${CLONE_MODE}"

## Auto-detect clean install if wp-config.php and index.php are missing
if [[ ! -f "wp-config.php" ]] && [[ ! -f "index.php" ]] && [[ -z "${DOWNLOAD_SOURCE:-}" ]] && [[ -z "${CLEAN_INSTALL:-}" ]] && [[ -z "${DB_DUMP:-}" ]] && [[ -z "${DB_IMPORT:-}" ]]; then
    echo "No WordPress installation found. Assuming --clean-install mode."
    CLEAN_INSTALL=1
    COMPOSER_INSTALL=
    DB_IMPORT=
fi


## Run fix-deps if flag is set
if [[ -n "${FIX_DEPS}" ]]; then
    :: Running fix-deps to set correct dependency versions
    
    SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
    if [[ -f "${SCRIPT_DIR}/fix-deps.cmd" ]]; then
        # Try to detect version first
        DETECTED_VERSION=""
        if [[ -f "wp-includes/version.php" ]]; then
            DETECTED_VERSION=$(grep "\$wp_version = " wp-includes/version.php | grep -oP "'\K[^']+" | grep -oP '^\d+\.\d+' || echo "")
        fi
        
        # Try to detect from remote
        if [[ -z "${DETECTED_VERSION}" ]] && [[ -n "${CLONE_MODE}" ]] && [[ -n "${ENV_SOURCE}" ]]; then
             echo "Auto-detecting WordPress version from remote '${ENV_SOURCE}'..."
             DETECTED_VERSION=$(detect_remote_version "wordpress" "${ENV_SOURCE}")
        fi
        
        if [[ -n "${DETECTED_VERSION}" ]]; then
            echo "Detected WordPress version: ${DETECTED_VERSION}"
            source "${SCRIPT_DIR}/fix-deps.cmd" --version="${DETECTED_VERSION}" 2>&1 | grep -v "\[DRY RUN\]\|Run without"
        else
            # Prompt user for version
            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "WordPress version not detected"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""
            echo "Available versions: 5.7, 5.8, 5.9, 6.0, 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 6.7"
            read -p "Please specify the WordPress version: " USER_VERSION
            
            if [[ -n "${USER_VERSION}" ]]; then
                # Save to .env for future reference
                if ! grep -q "^WORDPRESS_VERSION=" .env 2>/dev/null; then
                    echo "WORDPRESS_VERSION=${USER_VERSION}" >> .env
                else
                    sed -i "s/^WORDPRESS_VERSION=.*/WORDPRESS_VERSION=${USER_VERSION}/" .env
                fi
                
                source "${SCRIPT_DIR}/fix-deps.cmd" --version="${USER_VERSION}" 2>&1 | grep -v "\[DRY RUN\]\|Run without"
            else
                echo "⚠ No version specified. Using default (latest) dependency versions."
                source "${SCRIPT_DIR}/fix-deps.cmd" 2>&1 | grep -v "\[DRY RUN\]\|Run without"
            fi
        fi
        
        # Reload env-variables to pick up changes made by fix-deps
        source "${WARDEN_HOME_DIR:-~/.warden}/commands/env-variables"
    else
        echo "⚠ fix-deps command not found, skipping dependency version correction"
    fi
fi

## validate the selected environment
if [[ "${ENV_REQUIRED:-}" ]] && [[ -z "${ENV_SOURCE_HOST+x}" ]]; then
    printf "Invalid environment '%s' or missing REMOTE_*_HOST configuration\n" "${ENV_SOURCE}" >&2
    exit 2
    exit 2
fi

:: Starting Warden
warden svc up
if [[ ! -f ${WARDEN_HOME_DIR}/ssl/certs/${TRAEFIK_DOMAIN}.crt.pem ]]; then
    warden sign-certificate ${TRAEFIK_DOMAIN}
fi

:: Initializing environment
warden env up --remove-orphans

## wait for database to start
warden shell -c "while ! nc -z db 3306 </dev/null; do sleep 2; done"

## download files from the remote
if [[ "${CLONE_MODE:-}" ]]; then
    # Backup local .env to prevent overwrite
    cp .env .env.warden-local
    
    warden env-sync --file --source="${ENV_SOURCE}"
    
    # If remote had .env, save it as reference
    if [[ -f .env ]] && ! cmp -s .env .env.warden-local; then
        mv .env .env.remote-source
        printf "ℹ️  Remote .env saved as .env.remote-source\n"
    fi
    
    # Restore local .env
    mv .env.warden-local .env
    
    # Clean up for fresh start
    warden env exec -T php-fpm sh -c "
        rm -rf wp-content/cache/* 2>/dev/null || true
    " || true
fi

# Clean install - download WordPress
if [[ "${CLEAN_INSTALL:-}" ]]; then
    :: Downloading WordPress
    
    # Download and extract WordPress
    rm -f wp-config.php  # Remove from host (bind mount)
    warden env exec -T php-fpm rm -f wp-config.php  # Ensure removed in container
    warden env exec -T php-fpm curl -o /tmp/wordpress.tar.gz https://wordpress.org/latest.tar.gz
    warden env exec -T php-fpm tar -xzf /tmp/wordpress.tar.gz -C /tmp/
    warden env exec -T php-fpm sh -c "cp -r /tmp/wordpress/* /var/www/html/"
    warden env exec -T php-fpm rm -rf /tmp/wordpress /tmp/wordpress.tar.gz
    
    echo "✅ WordPress core downloaded"
fi

# Run composer install if composer.json exists
if [[ "${COMPOSER_INSTALL:-}" ]] && [[ ! "${CLEAN_INSTALL:-}" ]]; then
    if warden env exec -T php-fpm test -f composer.json 2>/dev/null; then
        :: Installing root composer dependencies
        warden env exec -T php-fpm composer install --no-interaction --no-dev --optimize-autoloader --no-scripts
    fi

    # Also check for composer.json in plugins/themes (typical for many WordPress sites)
    :: Checking for nested composer dependencies
    # We use find . and filter for wp-content to be more robust, filtering out everything else
    COMPOSER_DIRS=$(warden env exec -T php-fpm find . -maxdepth 5 -name composer.json -not -path "*/vendor/*" | grep "^./wp-content" | xargs -r dirname | sed 's|^\./||' | sort -u || true)
    
    if [[ -n "${COMPOSER_DIRS}" ]]; then
        for comp_dir in ${COMPOSER_DIRS}; do
            if [[ -n "${comp_dir}" && "${comp_dir}" != "." ]]; then
                echo "➜ Installing dependencies in ${comp_dir}"
                warden env exec -T php-fpm composer install -d "${comp_dir}" --no-interaction --no-dev --optimize-autoloader --no-scripts < /dev/null || echo "⚠ Failed to install dependencies in ${comp_dir}"
            fi
        done
    fi

    # Fallback: Many plugins have a vendor folder in Git but it might be incomplete (ignored files)
    # If we have an environment source, we can try to rsync the vendor folder for plugins that use it
    if [[ -n "${ENV_SOURCE_HOST+x}" ]]; then
        :: Checking for plugins needing vendor sync fallback
        # Find plugins that have a vendor/autoload.php but no composer.json, or where composer install failed
        PLUGINS_WITH_VENDOR=$(warden env exec -T php-fpm find wp-content/plugins -mindepth 2 -maxdepth 2 -name "vendor" -type d | cut -d/ -f3 || true)
        
        for plugin in ${PLUGINS_WITH_VENDOR}; do
            # If it doesn't have a composer.json, it's a good candidate for sync fallback
            if ! warden env exec -T php-fpm test -f "wp-content/plugins/${plugin}/composer.json" 2>/dev/null; then
                echo "➜ Syncing vendor fallback for ${plugin}"
                warden env-sync --path="wp-content/plugins/${plugin}/vendor/" --source="${ENV_SOURCE}" || true
            fi
        done
    fi
fi

## import database only if --skip-db-import is not specified
if [[ "${DB_IMPORT:-}" ]] && [[ ! "${CLEAN_INSTALL:-}" ]]; then
    if [[ "${STREAM_DB:-}" ]] && [[ -z "${DB_DUMP}" ]] && [[ -n "${ENV_SOURCE_HOST+x}" ]]; then
        warden db-import --stream-db -e "$ENV_SOURCE"
    else
        if [[ -z "$DB_DUMP" ]] && [[ -n "${ENV_SOURCE_HOST+x}" ]]; then
            DB_DUMP="wp-content/${WARDEN_ENV_NAME}_${ENV_SOURCE}-$(date +%Y%m%dT%H%M%S).sql.gz"
            :: Downloading database from ${ENV_SOURCE}
            warden db-dump --local --file="${DB_DUMP}" -e "$ENV_SOURCE"
        fi

        if [[ -n "$DB_DUMP" ]] && [[ -f "$DB_DUMP" ]]; then
            :: Importing database
            warden db-import --file="${DB_DUMP}"
        fi
    fi
fi

# Get actual database credentials from the db container
DB_USER=$(warden env exec -T db printenv MYSQL_USER 2>/dev/null)
DB_PASS=$(warden env exec -T db printenv MYSQL_PASSWORD 2>/dev/null)
DB_NAME=$(warden env exec -T db printenv MYSQL_DATABASE 2>/dev/null)

# Use defaults if not available
DB_USER=${DB_USER:-wordpress}
DB_PASS=${DB_PASS:-wordpress}
DB_NAME=${DB_NAME:-wordpress}

# Create or Update wp-config.php
if ! warden env exec -T php-fpm test -f wp-config.php; then
    if warden env exec -T php-fpm test -f wp-config-sample.php; then
        :: Creating wp-config.php
        
        # Generate keys
        SALT=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/)
        
        # Fallback if SALT is empty
        if [[ -z "$SALT" ]]; then
            echo "⚠️  Failed to fetch salts from WordPress.org, using fallback."
            SALT="define('AUTH_KEY',         'put your unique phrase here');
define('SECURE_AUTH_KEY',  'put your unique phrase here');
define('LOGGED_IN_KEY',    'put your unique phrase here');
define('NONCE_KEY',        'put your unique phrase here');
define('AUTH_SALT',        'put your unique phrase here');
define('SECURE_AUTH_SALT', 'put your unique phrase here');
define('LOGGED_IN_SALT',   'put your unique phrase here');
define('NONCE_SALT',       'put your unique phrase here');"
        fi

        # Determine database host
        DB_HOST_NAME="db"
        
        # Create config file directly to ensure correctness
        cat > wp-config.php <<EOF
<?php
define( 'DB_NAME', '${DB_NAME}' );
define( 'DB_USER', '${DB_USER}' );
define( 'DB_PASSWORD', '${DB_PASS}' );
define( 'DB_HOST', '${DB_HOST_NAME}' );
define( 'DB_CHARSET', 'utf8' );
define( 'DB_COLLATE', '' );

${SALT}

\$table_prefix = 'wp_';

define( 'WP_DEBUG', false );

if ( ! defined( 'ABSPATH' ) ) {
    define( 'ABSPATH', __DIR__ . '/' );
}

require_once ABSPATH . 'wp-settings.php';
EOF
        
        echo "✅ wp-config.php created with database credentials"
    fi
elif [[ -n "${CLONE_MODE}" ]]; then
    :: Patching existing wp-config.php for Warden
    # Use sed to update values while preserving other settings. Handles ' and " quotes.
    DB_HOST_NAME="db"
    warden env exec -T php-fpm sed -i "s/define( *['\"]DB_NAME['\"] *, *['\"][^'\"]*['\"] *);/define( 'DB_NAME', '${DB_NAME}' );/" wp-config.php
    warden env exec -T php-fpm sed -i "s/define( *['\"]DB_USER['\"] *, *['\"][^'\"]*['\"] *);/define( 'DB_USER', '${DB_USER}' );/" wp-config.php
    warden env exec -T php-fpm sed -i "s/define( *['\"]DB_PASSWORD['\"] *, *['\"][^'\"]*['\"] *);/define( 'DB_PASSWORD', '${DB_PASS}' );/" wp-config.php
    warden env exec -T php-fpm sed -i "s/define( *['\"]DB_HOST['\"] *, *['\"][^'\"]*['\"] *);/define( 'DB_HOST', '${DB_HOST_NAME}' );/" wp-config.php
    
    echo "✅ wp-config.php patched with Warden database credentials"
fi

# Ensure database is empty for clean install
if [[ "${CLEAN_INSTALL:-}" ]] && warden env exec -T php-fpm test -f wp-config.php 2>/dev/null; then
    echo "ℹ️  Clearing database for clean install..."
    # Get DB credentials if not already set
    DB_USER="${DB_USER:-$(warden env exec -T db printenv MYSQL_USER 2>/dev/null || echo 'wordpress')}"
    DB_PASS="${DB_PASS:-$(warden env exec -T db printenv MYSQL_PASSWORD 2>/dev/null || echo 'wordpress')}"
    DB_NAME="${DB_NAME:-$(warden env exec -T db printenv MYSQL_DATABASE 2>/dev/null || echo 'wordpress')}"
    # Use mysql/mariadb directly as wp-cli might be missing
    DB_BIN="mysql"
    if [[ "${MYSQL_DISTRIBUTION:-}" == *"mariadb"* ]]; then
        DB_BIN="mariadb"
    fi
    warden env exec -T db ${DB_BIN} -u"${DB_USER}" -p"${DB_PASS}" -e "DROP DATABASE IF EXISTS ${DB_NAME}; CREATE DATABASE ${DB_NAME};" 2>/dev/null || true
fi

# Update wp-config.php for local environment if DB was imported
if [[ ${DB_IMPORT} ]] && warden env exec -T php-fpm test -f wp-config.php 2>/dev/null; then
    # Get actual database credentials from the db container
    DB_USER=$(warden env exec -T db printenv MYSQL_USER 2>/dev/null)
    DB_PASS=$(warden env exec -T db printenv MYSQL_PASSWORD 2>/dev/null)
    DB_NAME=$(warden env exec -T db printenv MYSQL_DATABASE 2>/dev/null)
    
    # Use defaults if not available
    DB_USER=${DB_USER:-wordpress}
    DB_PASS=${DB_PASS:-wordpress}
    DB_NAME=${DB_NAME:-wordpress}
    
    :: Updating wp-config.php for local environment
    warden env exec -T php-fpm sed -i "s/define([[:space:]]*'DB_NAME'[[:space:]]*,[[:space:]]*'[^']*'/define( 'DB_NAME', '${DB_NAME}'/" wp-config.php
    warden env exec -T php-fpm sed -i "s/define([[:space:]]*'DB_USER'[[:space:]]*,[[:space:]]*'[^']*'/define( 'DB_USER', '${DB_USER}'/" wp-config.php
    warden env exec -T php-fpm sed -i "s/define([[:space:]]*'DB_PASSWORD'[[:space:]]*,[[:space:]]*'[^']*'/define( 'DB_PASSWORD', '${DB_PASS}'/" wp-config.php
    warden env exec -T php-fpm sed -i "s/define([[:space:]]*'DB_HOST'[[:space:]]*,[[:space:]]*'[^']*'/define( 'DB_HOST', 'db'/" wp-config.php
fi

# Configure Redis if enabled
if [[ "${WARDEN_REDIS}" == "1" ]] && warden env exec -T php-fpm test -f wp-config.php; then
    :: Configuring Redis
    
    # Add Redis configuration before wp-settings.php
    warden env exec -T php-fpm sh -c "grep -q 'WP_REDIS_HOST' wp-config.php || sed -i \"/require_once.*wp-settings.php/i define('WP_REDIS_HOST', 'redis');\ndefine('WP_REDIS_PORT', 6379);\" wp-config.php"
fi

# Install WordPress if not already installed and not cloning from remote
if [[ ! $SKIP_WP_INSTALL ]] && [[ ! ${DOWNLOAD_SOURCE} ]] && warden env exec -T php-fpm test -f wp-config.php; then
    # Check if WordPress is already installed
    # Check if we should install
    SHOULD_INSTALL=0
    if [[ "${CLEAN_INSTALL:-}" ]]; then
        SHOULD_INSTALL=1
    elif ! warden env exec -T php-fpm php -r "define('WP_USE_THEMES', false); require 'wp-load.php'; exit(is_blog_installed() ? 0 : 1);" 2>/dev/null; then
        SHOULD_INSTALL=1
    fi

    if [[ "${SHOULD_INSTALL}" -eq 1 ]]; then
        :: Installing WordPress
        
        SITE_TITLE="${WARDEN_ENV_NAME:-WordPress Site}"
        ADMIN_USER="admin"
        ADMIN_PASS="admin123"
        ADMIN_EMAIL="admin@${TRAEFIK_DOMAIN:-test.test}"
        SITE_URL="https://${TRAEFIK_SUBDOMAIN:-app}.${TRAEFIK_DOMAIN:-test.test}"
        
        # Run WordPress installation
        if ! warden env exec -T php-fpm php -r "
            ini_set('display_errors', 1);
            error_reporting(E_ALL);

            // Set HTTP_HOST for CLI context
            \$_SERVER['HTTP_HOST'] = '${TRAEFIK_SUBDOMAIN:-app}.${TRAEFIK_DOMAIN:-test.test}';
            \$_SERVER['REQUEST_URI'] = '/';
            
            define('WP_USE_THEMES', false);
            define('WP_INSTALLING', true);
            
            // Suppress header warnings during CLI
            ob_start();
            require 'wp-load.php';
            require_once ABSPATH . 'wp-admin/includes/upgrade.php';
            
            \$result = wp_install('$SITE_TITLE', '$ADMIN_USER', '$ADMIN_EMAIL', 1, '', '$ADMIN_PASS');
            ob_end_clean();
            
            if (is_wp_error(\$result)) {
                echo 'ERROR: ' . \$result->get_error_message() . PHP_EOL;
                exit(1);
            }
            
            // Update site URL and home
            update_option('siteurl', '$SITE_URL');
            update_option('home', '$SITE_URL');
            
            echo 'WordPress installed successfully!' . PHP_EOL;
        "; then
            echo "❌ WordPress installation failed."
            exit 1
        fi
        
        echo ""
        echo "════════════════════════════════════════════════════════════"
        echo "WordPress Admin Credentials:"
        echo "  Username: $ADMIN_USER"
        echo "  Password: $ADMIN_PASS"
        echo "  Email: $ADMIN_EMAIL"
        echo "════════════════════════════════════════════════════════════"
        echo ""
    else
        echo "ℹ️  WordPress is already installed"
    fi
fi

# Update site URL after DB import for local development
if [[ ${DB_IMPORT} ]] && warden env exec -T php-fpm test -f wp-config.php 2>/dev/null; then
    :: Updating site URLs for local development
    SITE_URL="https://${TRAEFIK_SUBDOMAIN:-app}.${TRAEFIK_DOMAIN:-test.test}"
    warden env exec -T php-fpm php -r "
        require 'wp-load.php';
        update_option('siteurl', '$SITE_URL');
        update_option('home', '$SITE_URL');
        echo 'Site URLs updated to $SITE_URL' . PHP_EOL;
    " 2>/dev/null || echo "Note: Could not update site URLs. You may need to update them manually."
fi

echo "=========== THE APPLICATION HAS BEEN INSTALLED SUCCESSFULLY ==========="
echo "Frontend: https://${TRAEFIK_SUBDOMAIN:-app}.${TRAEFIK_DOMAIN:-test.test}/"
echo "Admin: https://${TRAEFIK_SUBDOMAIN:-app}.${TRAEFIK_DOMAIN:-test.test}/wp-admin/"

END_TIME=$(date +%s)
echo "Total build time: $((END_TIME - START_TIME)) seconds"
