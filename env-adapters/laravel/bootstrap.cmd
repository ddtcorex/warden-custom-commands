#!/usr/bin/env bash
[[ ! ${WARDEN_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

START_TIME=$(date +%s)

# env-variables is already sourced by the root dispatcher

CLEAN_INSTALL=
COMPOSER_INSTALL=1
SKIP_MIGRATE=
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
        --skip-migrate)
            SKIP_MIGRATE=1
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
        if [[ -f "composer.json" ]] && command -v jq &> /dev/null; then
            DETECTED_VERSION=$(jq -r '.require["laravel/framework"] // "unknown"' composer.json 2>/dev/null | sed 's/[\^~]//g' | grep -oP '^\d+' || echo "")
        fi
        
        if [[ -n "${DETECTED_VERSION}" ]] && [[ "${DETECTED_VERSION}" != "unknown" ]]; then
            echo "Detected Laravel version: ${DETECTED_VERSION}"
            source "${SCRIPT_DIR}/fix-deps.cmd" --version="${DETECTED_VERSION}" 2>&1 | grep -v "\[DRY RUN\]\|Run without"
        else
            # Prompt user for version
            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "Laravel version not detected"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""
            echo "Available versions: 6, 7, 8, 9, 10, 11"
            read -p "Please specify the Laravel version: " USER_VERSION
            
            if [[ -n "${USER_VERSION}" ]]; then
                # Save to .env for future reference
                if ! grep -q "^LARAVEL_VERSION=" .env 2>/dev/null; then
                    echo "LARAVEL_VERSION=${USER_VERSION}" >> .env
                else
                    sed -i "s/^LARAVEL_VERSION=.*/LARAVEL_VERSION=${USER_VERSION}/" .env
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

# Clean install - create new Laravel project
if [[ $CLEAN_INSTALL ]]; then
    :: Creating new Laravel project
    
    # Backup Warden's .env
    if [[ -f .env ]]; then
        cp .env .env.warden.backup
    fi
    
    echo "Installing Laravel via composer create-project..."
    warden env exec php-fpm composer create-project --prefer-dist laravel/laravel /tmp/laravel-project
    
    # Copy all Laravel files
    warden env exec php-fpm sh -c "rsync -a /tmp/laravel-project/ /var/www/html/"
    
    # Merge Warden variables back into .env
    if [[ -f .env.warden.backup ]]; then
        :: Merging Warden configuration with Laravel .env
        # Append Warden-specific variables to Laravel's .env
        echo "" >> .env
        echo "# Warden Configuration" >> .env
        grep -E "^(WARDEN_|TRAEFIK_|MYSQL_|NODE_|COMPOSER_|PHP_|REDIS_VERSION)" .env.warden.backup >> .env || true
        rm .env.warden.backup
    fi
    
    # Update database settings for Warden
    :: Configuring database connection
    warden env exec php-fpm sed -i "s/DB_HOST=.*/DB_HOST=db/" .env
    warden env exec php-fpm sed -i "s/DB_DATABASE=.*/DB_DATABASE=laravel/" .env
    warden env exec php-fpm sed -i "s/DB_USERNAME=.*/DB_USERNAME=laravel/" .env
    warden env exec php-fpm sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=laravel/" .env
fi

if [[ $COMPOSER_INSTALL ]] && [[ ! $CLEAN_INSTALL ]]; then
    :: Installing dependencies
    warden env exec php-fpm composer install
fi

# Ensure .env exists
if ! warden env exec php-fpm test -f .env; then
    if warden env exec php-fpm test -f .env.example; then
        warden env exec php-fpm cp .env.example .env
    fi
fi

# Configure database if not already done
if warden env exec php-fpm grep -q "DB_HOST=127.0.0.1" .env 2>/dev/null; then
    :: Configuring database connection
    warden env exec php-fpm sed -i "s/DB_HOST=.*/DB_HOST=db/" .env
    warden env exec php-fpm sed -i "s/DB_DATABASE=.*/DB_DATABASE=laravel/" .env
    warden env exec php-fpm sed -i "s/DB_USERNAME=.*/DB_USERNAME=laravel/" .env  
    warden env exec php-fpm sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=laravel/" .env
fi

# Generate application key if missing
if ! warden env exec php-fpm grep -q "APP_KEY=base64:" .env 2>/dev/null; then
    :: Generating application key
    warden env exec php-fpm php artisan key:generate
fi

if [[ ! $SKIP_MIGRATE ]]; then
    :: Running migrations
    warden env exec php-fpm php artisan migrate --force
fi

warden set-config

echo "=========== THE APPLICATION HAS BEEN INSTALLED SUCCESSFULLY ==========="
echo "Frontend: https://${TRAEFIK_SUBDOMAIN:-app}.${TRAEFIK_DOMAIN:-test.test}/"

END_TIME=$(date +%s)
echo "Total build time: $((END_TIME - START_TIME)) seconds"
