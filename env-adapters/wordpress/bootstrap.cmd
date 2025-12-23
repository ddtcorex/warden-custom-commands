#!/usr/bin/env bash
set -u
[[ ! "${WARDEN_DIR:-}" ]] && >&2 printf "\033[31mThis script is not intended to be run directly!\033[0m\n" && exit 1

START_TIME=$(date +%s)

# env-variables is already sourced by the root dispatcher

## configure command defaults
CLEAN_INSTALL=
COMPOSER_INSTALL=1
SKIP_WP_INSTALL=
FIX_DEPS=
DOWNLOAD_SOURCE=
DB_DUMP=
DB_IMPORT=1
ENV_REQUIRED=

## argument parsing
while (( "$#" )); do
    case "$1" in
        --clean-install)
            CLEAN_INSTALL=1
            COMPOSER_INSTALL=
            DB_IMPORT=
            shift
            ;;
        --fix-deps)
            FIX_DEPS=1
            shift
            ;;
        --download-source)
            DOWNLOAD_SOURCE=1
            COMPOSER_INSTALL=
            ENV_REQUIRED=1
            shift
            ;;
        --db-dump)
            DB_DUMP="$2"
            ENV_REQUIRED=1
            shift 2
            ;;
        --db-dump=*)
            DB_DUMP="${1#*=}"
            ENV_REQUIRED=1
            shift
            ;;
        --skip-db-import)
            DB_IMPORT=
            shift
            ;;
        --skip-composer-install)
            COMPOSER_INSTALL=
            shift
            ;;
        --skip-wp-install)
            SKIP_WP_INSTALL=1
            shift
            ;;
        --no-stream-db)
            STREAM_DB=
            shift
            ;;
        *)
            shift
            ;;
    esac
done

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
fi

## download files from the remote
if [[ "${DOWNLOAD_SOURCE:-}" ]]; then
    warden sync --file --source="${ENV_SOURCE}" --path="./"
    
    # Clean up for fresh start
    warden env exec php-fpm sh -c "
        rm -rf wp-content/cache/* 2>/dev/null || true
    " || true
fi

:: Starting Warden
warden svc up
if [[ ! -f ${WARDEN_HOME_DIR:-~/.warden}/ssl/certs/${TRAEFIK_DOMAIN:-test.test}.crt.pem ]]; then
    warden sign-certificate ${TRAEFIK_DOMAIN:-test.test}
fi

:: Initializing environment
warden env up

## wait for database to start
warden shell -c "while ! nc -z db 3306 </dev/null; do sleep 2; done"

# Clean install - download WordPress
if [[ "${CLEAN_INSTALL:-}" ]]; then
    :: Downloading WordPress
    
    # Download and extract WordPress
    warden env exec php-fpm curl -o /tmp/wordpress.tar.gz https://wordpress.org/latest.tar.gz
    warden env exec php-fpm tar -xzf /tmp/wordpress.tar.gz -C /tmp/
    warden env exec php-fpm sh -c "cp -r /tmp/wordpress/* /var/www/html/"
    warden env exec php-fpm rm -rf /tmp/wordpress /tmp/wordpress.tar.gz
    
    echo "✅ WordPress core downloaded"
fi

# Run composer install if composer.json exists
if [[ "${COMPOSER_INSTALL:-}" ]] && [[ ! "${CLEAN_INSTALL:-}" ]] && warden env exec php-fpm test -f composer.json 2>/dev/null; then
    :: Installing composer dependencies
    warden env exec php-fpm composer install
fi

## import database only if --skip-db-import is not specified
if [[ "${DB_IMPORT:-}" ]] && [[ ! "${CLEAN_INSTALL:-}" ]]; then
    if [[ "${STREAM_DB:-}" ]] && [[ -z "${DB_DUMP}" ]] && [[ -n "${ENV_SOURCE_HOST+x}" ]]; then
        warden db-import --stream-db -e "$ENV_SOURCE"
    else
        if [[ -z "$DB_DUMP" ]] && [[ -n "${ENV_SOURCE_HOST+x}" ]]; then
            DB_DUMP="wp-content/${WARDEN_ENV_NAME}_${ENV_SOURCE}-$(date +%Y%m%dT%H%M%S).sql.gz"
            :: Downloading database from ${ENV_SOURCE}
            warden db-dump --file="${DB_DUMP}" -e "$ENV_SOURCE"
        fi

        if [[ -n "$DB_DUMP" ]] && [[ -f "$DB_DUMP" ]]; then
            :: Importing database
            warden db-import --file="${DB_DUMP}"
        fi
    fi
fi

# Create wp-config.php
if ! warden env exec php-fpm test -f wp-config.php; then
    if warden env exec php-fpm test -f wp-config-sample.php; then
        :: Creating wp-config.php
        
        # Copy sample and configure
        warden env exec php-fpm cp wp-config-sample.php wp-config.php
        
        # Get actual database credentials from the db container
        DB_USER=$(warden env exec -T db printenv MYSQL_USER 2>/dev/null)
        DB_PASS=$(warden env exec -T db printenv MYSQL_PASSWORD 2>/dev/null)
        DB_NAME=$(warden env exec -T db printenv MYSQL_DATABASE 2>/dev/null)
        
        # Use defaults if not available
        DB_USER=${DB_USER:-wordpress}
        DB_PASS=${DB_PASS:-wordpress}
        DB_NAME=${DB_NAME:-wordpress}
        
        # Update database credentials
        warden env exec php-fpm sed -i "s/database_name_here/${DB_NAME}/" wp-config.php
        warden env exec php-fpm sed -i "s/username_here/${DB_USER}/" wp-config.php
        warden env exec php-fpm sed -i "s/password_here/${DB_PASS}/" wp-config.php
        warden env exec php-fpm sed -i "s/localhost/db/" wp-config.php
        
        # Generate keys on host and copy to container
        SALT=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/)
        echo "$SALT" > /tmp/wp-keys.txt
        warden env cp /tmp/wp-keys.txt php-fpm:/tmp/wp-keys.txt
        rm /tmp/wp-keys.txt
        
        # Replace the security keys section
        warden env exec php-fpm sed -i "/AUTH_KEY/,/NONCE_SALT/d" wp-config.php
        warden env exec php-fpm sed -i "/put your unique phrase here/r /tmp/wp-keys.txt" wp-config.php
        warden env exec php-fpm rm /tmp/wp-keys.txt
        
        echo "✅ wp-config.php created with database credentials"
    fi
fi

# Update wp-config.php for local environment if DB was imported
if [[ ${DB_IMPORT} ]] && warden env exec php-fpm test -f wp-config.php 2>/dev/null; then
    # Get actual database credentials from the db container
    DB_USER=$(warden env exec -T db printenv MYSQL_USER 2>/dev/null)
    DB_PASS=$(warden env exec -T db printenv MYSQL_PASSWORD 2>/dev/null)
    DB_NAME=$(warden env exec -T db printenv MYSQL_DATABASE 2>/dev/null)
    
    # Use defaults if not available
    DB_USER=${DB_USER:-wordpress}
    DB_PASS=${DB_PASS:-wordpress}
    DB_NAME=${DB_NAME:-wordpress}
    
    :: Updating wp-config.php for local environment
    warden env exec php-fpm sed -i "s/define([[:space:]]*'DB_NAME'[[:space:]]*,[[:space:]]*'[^']*'/define( 'DB_NAME', '${DB_NAME}'/" wp-config.php
    warden env exec php-fpm sed -i "s/define([[:space:]]*'DB_USER'[[:space:]]*,[[:space:]]*'[^']*'/define( 'DB_USER', '${DB_USER}'/" wp-config.php
    warden env exec php-fpm sed -i "s/define([[:space:]]*'DB_PASSWORD'[[:space:]]*,[[:space:]]*'[^']*'/define( 'DB_PASSWORD', '${DB_PASS}'/" wp-config.php
    warden env exec php-fpm sed -i "s/define([[:space:]]*'DB_HOST'[[:space:]]*,[[:space:]]*'[^']*'/define( 'DB_HOST', 'db'/" wp-config.php
fi

# Configure Redis if enabled
if [[ "${WARDEN_REDIS}" == "1" ]] && warden env exec php-fpm test -f wp-config.php; then
    :: Configuring Redis
    
    # Add Redis configuration before wp-settings.php
    warden env exec php-fpm sh -c "grep -q 'WP_REDIS_HOST' wp-config.php || sed -i \"/require_once.*wp-settings.php/i define('WP_REDIS_HOST', 'redis');\ndefine('WP_REDIS_PORT', 6379);\" wp-config.php"
fi

# Install WordPress if not already installed and not cloning from remote
if [[ ! $SKIP_WP_INSTALL ]] && [[ ! ${DOWNLOAD_SOURCE} ]] && warden env exec php-fpm test -f wp-config.php; then
    # Check if WordPress is already installed
    if ! warden env exec php-fpm php -r "require 'wp-config.php'; require 'wp-includes/version.php'; exit(is_blog_installed() ? 0 : 1);" 2>/dev/null; then
        :: Installing WordPress
        
        SITE_TITLE="${WARDEN_ENV_NAME:-WordPress Site}"
        ADMIN_USER="admin"
        ADMIN_PASS="admin123"
        ADMIN_EMAIL="admin@${TRAEFIK_DOMAIN:-test.test}"
        SITE_URL="https://${TRAEFIK_SUBDOMAIN:-app}.${TRAEFIK_DOMAIN:-test.test}"
        
        # Run WordPress installation
        warden env exec php-fpm php -r "
            require 'wp-load.php';
            require 'wp-admin/includes/upgrade.php';
            wp_install('$SITE_TITLE', '$ADMIN_USER', '$ADMIN_EMAIL', 1, '', '$ADMIN_PASS');
            
            // Update site URL and home
            update_option('siteurl', '$SITE_URL');
            update_option('home', '$SITE_URL');
            
            echo 'WordPress installed successfully!' . PHP_EOL;
        "
        
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
if [[ ${DB_IMPORT} ]] && warden env exec php-fpm test -f wp-config.php 2>/dev/null; then
    :: Updating site URLs for local development
    SITE_URL="https://${TRAEFIK_SUBDOMAIN:-app}.${TRAEFIK_DOMAIN:-test.test}"
    warden env exec php-fpm php -r "
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
