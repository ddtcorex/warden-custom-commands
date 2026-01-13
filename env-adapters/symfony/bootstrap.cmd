#!/usr/bin/env bash
set -u
[[ ! "${WARDEN_DIR:-}" ]] && >&2 printf "\033[31mThis script is not intended to be run directly!\033[0m\n" && exit 1

START_TIME=$(date +%s)

# env-variables is already sourced by the root dispatcher

## configure command defaults
CLEAN_INSTALL=
COMPOSER_INSTALL=1
SKIP_MIGRATE=
FIX_DEPS=
DOWNLOAD_SOURCE=
DB_DUMP=
DB_IMPORT=1
STREAM_DB=1
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
        --skip-migrate)
            SKIP_MIGRATE=1
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
        if [[ -f "composer.json" ]] && command -v jq &> /dev/null; then
            DETECTED_VERSION=$(jq -r '.require["symfony/framework-bundle"] // .require["symfony/symfony"] // "unknown"' composer.json 2>/dev/null | sed 's/[\^~]//g' | grep -oP '^\d+\.\d+' || echo "")
        fi
        
        if [[ -n "${DETECTED_VERSION}" ]] && [[ "${DETECTED_VERSION}" != "unknown" ]]; then
            echo "Detected Symfony version: ${DETECTED_VERSION}"
            source "${SCRIPT_DIR}/fix-deps.cmd" --version="${DETECTED_VERSION}" 2>&1 | grep -v "\[DRY RUN\]\|Run without"
        else
            # Prompt user for version
            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "Symfony version not detected"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""
            echo "Available versions: 5.2, 5.3, 5.4, 6.0, 6.1, 6.2, 6.3, 6.4, 7.0, 7.1, 7.2"
            read -p "Please specify the Symfony version: " USER_VERSION
            
            if [[ -n "${USER_VERSION}" ]]; then
                # Save to .env for future reference
                if ! grep -q "^SYMFONY_VERSION=" .env 2>/dev/null; then
                    echo "SYMFONY_VERSION=${USER_VERSION}" >> .env
                else
                    sed -i "s/^SYMFONY_VERSION=.*/SYMFONY_VERSION=${USER_VERSION}/" .env
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
    
    # Clean up generated files for fresh start
    warden env exec php-fpm sh -c "
        rm -rf var/cache/* var/log/* 2>/dev/null || true
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

# Clean install - create new Symfony project
if [[ "${CLEAN_INSTALL:-}" ]]; then
    :: Creating new Symfony project
    
    # Backup Warden's .env variables BEFORE creating project
    if [[ -f .env ]]; then
        # Extract just the Warden-specific variables
        grep -E "^(WARDEN_|TRAEFIK_|MYSQL_|NODE_|COMPOSER_|PHP_|REDIS_VERSION)" .env > /tmp/warden_vars.txt || true
    fi
    
    echo "Installing Symfony via composer create-project..."
    # Skip Docker configuration prompts and clean up in one command
    warden env exec -e SYMFONY_SKIP_DOCKER=1 php-fpm sh -c "
        composer create-project symfony/website-skeleton /tmp/symfony-project --no-interaction && \
        cp -r /tmp/symfony-project/. /var/www/html/ && \
        rm -rf /tmp/symfony-project
    "
    
    # Wait for file sync
    sleep 3
    
    # Merge Warden variables back into Symfony's .env
    if [[ -f /tmp/warden_vars.txt ]]; then
        :: Merging Warden configuration with Symfony .env
        echo "" >> .env
        echo "# Warden Configuration" >> .env
        cat /tmp/warden_vars.txt >> .env
        rm /tmp/warden_vars.txt
    fi
    
    echo "✅ Symfony project created"
fi

# Run composer install if composer.json exists and not a clean install
# Use --no-scripts to avoid cache:clear before database is configured
if [[ "${COMPOSER_INSTALL:-}" ]] && [[ ! "${CLEAN_INSTALL:-}" ]] && warden env exec php-fpm test -f composer.json 2>/dev/null; then
    :: Installing dependencies - skipping scripts
    warden env exec php-fpm composer install --no-scripts
fi

## import database only if --skip-db-import is not specified
if [[ "${DB_IMPORT:-}" ]] && [[ ! "${CLEAN_INSTALL:-}" ]]; then
    if [[ "${STREAM_DB:-}" ]] && [[ -z "${DB_DUMP}" ]] && [[ -n "${ENV_SOURCE_HOST+x}" ]]; then
        warden db-import --stream-db -e "$ENV_SOURCE"
    else
        if [[ -z "$DB_DUMP" ]] && [[ -n "${ENV_SOURCE_HOST+x}" ]]; then
            DB_DUMP="var/${WARDEN_ENV_NAME}_${ENV_SOURCE}-$(date +%Y%m%dT%H%M%S).sql.gz"
            :: Downloading database from ${ENV_SOURCE}
            warden db-dump --local --file="${DB_DUMP}" -e "$ENV_SOURCE"
        fi

        if [[ -n "$DB_DUMP" ]] && [[ -f "$DB_DUMP" ]]; then
            :: Importing database
            warden db-import --file="${DB_DUMP}"
        fi
    fi
fi

# Ensure .env exists
if ! warden env exec php-fpm test -f .env 2>/dev/null; then
    if warden env exec php-fpm test -f .env.local 2>/dev/null; then
        warden env exec php-fpm cp .env.local .env
    fi
fi

# Configure database if using Doctrine - do this INSIDE the container
# Symfony uses .env.local for local overrides (takes precedence over .env)
if warden env exec php-fpm test -f config/packages/doctrine.yaml 2>/dev/null; then
    # Get actual database credentials from the db container
    DB_USER=$(warden env exec -T db printenv MYSQL_USER 2>/dev/null)
    DB_PASS=$(warden env exec -T db printenv MYSQL_PASSWORD 2>/dev/null)
    DB_NAME=$(warden env exec -T db printenv MYSQL_DATABASE 2>/dev/null)
    
    # Use defaults if not available
    DB_USER=${DB_USER:-symfony}
    DB_PASS=${DB_PASS:-symfony}
    DB_NAME=${DB_NAME:-symfony}

    # Determine database host
    DB_HOST_NAME="db"

    :: Configuring database connection
    
    # Configure database using a single shell command to avoid nesting issues
    DATABASE_URL="mysql://${DB_USER}:${DB_PASS}@${DB_HOST_NAME}:3306/${DB_NAME}"
    warden env exec php-fpm sh -c "
        ENV_FILE='.env'
        if [ -f '.env.local' ]; then
            ENV_FILE='.env.local'
        fi
        sed -i '/DATABASE_URL/d' \"\$ENV_FILE\"
        echo \"DATABASE_URL='${DATABASE_URL}'\" >> \"\$ENV_FILE\"
    "
fi

# Configure Redis if enabled - do this INSIDE the container
if [[ "${WARDEN_REDIS}" == "1" ]]; then
    :: Configuring Redis
    warden env exec php-fpm sh -c "
        ENV_FILE='.env'
        if [ -f '.env.local' ]; then
            ENV_FILE='.env.local'
        fi
        
        if ! grep -q '^REDIS_URL=' \"\$ENV_FILE\" 2>/dev/null; then
            echo 'REDIS_URL=redis://redis:6379' >> \"\$ENV_FILE\"
        fi
    "
fi

# Run composer auto-scripts now that database is configured
# This runs cache:clear and other post-install scripts
if [[ $COMPOSER_INSTALL ]] && warden env exec php-fpm test -f composer.json 2>/dev/null; then
    :: Running composer scripts
    warden env exec php-fpm composer run-script auto-scripts 2>/dev/null || true
fi

if [[ ! $SKIP_MIGRATE ]]; then
    :: Running migrations
    warden env exec php-fpm php bin/console doctrine:migrations:migrate --no-interaction --allow-no-migration 2>/dev/null || true
fi

# Clear cache after migrations
:: Clearing cache
warden env exec php-fpm php bin/console cache:clear 2>/dev/null || true

echo "=========== THE APPLICATION HAS BEEN INSTALLED SUCCESSFULLY ============="
echo "Frontend: https://${TRAEFIK_SUBDOMAIN:-app}.${TRAEFIK_DOMAIN:-test.test}/"

END_TIME=$(date +%s)
echo "Total build time: $((END_TIME - START_TIME)) seconds"
