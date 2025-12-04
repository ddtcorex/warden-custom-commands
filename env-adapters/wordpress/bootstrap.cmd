
START_TIME=$(date +%s)

CLEAN_INSTALL=
COMPOSER_INSTALL=1
SKIP_WP_INSTALL=

while (( "$#" )); do
    case "$1" in
        --clean-install)
            CLEAN_INSTALL=1
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
