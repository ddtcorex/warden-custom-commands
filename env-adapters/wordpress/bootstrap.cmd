#!/usr/bin/env bash
[[ ! ${WARDEN_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

START_TIME=$(date +%s)

source "${WARDEN_HOME_DIR:-~/.warden}/commands/env-variables"

CLEAN_INSTALL=
COMPOSER_INSTALL=1
SKIP_WP_INSTALL=
FIX_DEPS=

while (( "$#" )); do
    case "$1" in
        --clean-install)
            CLEAN_INSTALL=1
            shift
            ;;
        --fix-deps)
            FIX_DEPS=1
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
if [[ $CLEAN_INSTALL ]]; then
    :: Downloading WordPress
    
    # Download and extract WordPress
    warden env exec php-fpm curl -o /tmp/wordpress.tar.gz https://wordpress.org/latest.tar.gz
    warden env exec php-fpm tar -xzf /tmp/wordpress.tar.gz -C /tmp/
    warden env exec php-fpm sh -c "cp -r /tmp/wordpress/* /var/www/html/"
    warden env exec php-fpm rm -rf /tmp/wordpress /tmp/wordpress.tar.gz
    
    echo "✅ WordPress core downloaded"
fi

# Run composer install if composer.json exists
if [[ $COMPOSER_INSTALL ]] && warden env exec php-fpm test -f composer.json; then
    :: Installing composer dependencies
    warden env exec php-fpm composer install
fi

# Create wp-config.php
if ! warden env exec php-fpm test -f wp-config.php; then
    if warden env exec php-fpm test -f wp-config-sample.php; then
        :: Creating wp-config.php
        
        # Copy sample and configure
        warden env exec php-fpm cp wp-config-sample.php wp-config.php
        
        # Update database credentials
        warden env exec php-fpm sed -i "s/database_name_here/wordpress/" wp-config.php
        warden env exec php-fpm sed -i "s/username_here/wordpress/" wp-config.php
        warden env exec php-fpm sed -i "s/password_here/wordpress/" wp-config.php
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

# Configure Redis if enabled
if [[ "${WARDEN_REDIS}" == "1" ]] && warden env exec php-fpm test -f wp-config.php; then
    :: Configuring Redis
    
    # Add Redis configuration before wp-settings.php
    warden env exec php-fpm sh -c "grep -q 'WP_REDIS_HOST' wp-config.php || sed -i \"/require_once.*wp-settings.php/i define('WP_REDIS_HOST', 'redis');\ndefine('WP_REDIS_PORT', 6379);\" wp-config.php"
fi

# Install WordPress if not already installed
if [[ ! $SKIP_WP_INSTALL ]] && warden env exec php-fpm test -f wp-config.php; then
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

echo "=========== THE APPLICATION HAS BEEN INSTALLED SUCCESSFULLY ==========="
echo "Frontend: https://${TRAEFIK_SUBDOMAIN:-app}.${TRAEFIK_DOMAIN:-test.test}/"
echo "Admin: https://${TRAEFIK_SUBDOMAIN:-app}.${TRAEFIK_DOMAIN:-test.test}/wp-admin/"

END_TIME=$(date +%s)
echo "Total build time: $((END_TIME - START_TIME)) seconds"
