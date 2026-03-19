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
SKIP_MIGRATE=
FIX_DEPS=
DB_DUMP=
DB_IMPORT=1
STREAM_DB=1
ENV_REQUIRED=
DB_FLAGS=""

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
        --no-migrate|--skip-migrate)
            SKIP_MIGRATE=1
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
        -N|--no-noise)
            DB_FLAGS="${DB_FLAGS} --no-noise"
            shift
            ;;
        -S|--no-pii)
            DB_FLAGS="${DB_FLAGS} --no-pii"
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

## Auto-detect clean install if composer.json is missing
if [[ ! -f "composer.json" ]] && [[ -z "${DOWNLOAD_SOURCE:-}" ]] && [[ -z "${CLEAN_INSTALL:-}" ]] && [[ -z "${DB_DUMP:-}" ]] && [[ -z "${DB_IMPORT:-}" ]]; then
    echo "No composer.json found. Assuming --clean-install mode."
    CLEAN_INSTALL=1
    COMPOSER_INSTALL=
    DB_IMPORT=
    SKIP_MIGRATE=1 # Don't migrate on empty
fi

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
        
        # Try to detect from remote
        if [[ -z "${DETECTED_VERSION}" ]] && [[ -n "${CLONE_MODE}" ]] && [[ -n "${ENV_SOURCE}" ]]; then
             echo "Auto-detecting Laravel version from remote '${ENV_SOURCE}'..."
             DETECTED_VERSION=$(detect_remote_version "laravel" "${ENV_SOURCE}")
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
warden env exec -T php-fpm sh -c "while ! nc -z db 3306 </dev/null; do sleep 2; done"

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
    
    # Clean up generated files for fresh start
    warden env exec php-fpm sh -c "
        rm -rf storage/framework/cache/* storage/framework/views/* bootstrap/cache/*.php 2>/dev/null || true
    " || true
fi

# Clean install - create new Laravel project
if [[ "${CLEAN_INSTALL:-}" ]]; then
    :: Creating new Laravel project
    
    # Backup Warden's .env
    if [[ -f .env ]]; then
        cp .env .env.warden.backup
    fi
    
    echo "Installing Laravel via composer create-project..."
    warden env exec php-fpm rm -rf /tmp/laravel-project
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
    
    # Get actual database credentials from the db container
    DB_USER=$(warden env exec -T db printenv MYSQL_USER 2>/dev/null)
    DB_PASS=$(warden env exec -T db printenv MYSQL_PASSWORD 2>/dev/null)
    DB_NAME=$(warden env exec -T db printenv MYSQL_DATABASE 2>/dev/null)

    # Use defaults if not available
    DB_USER=${DB_USER:-laravel}
    DB_PASS=${DB_PASS:-laravel}
    DB_NAME=${DB_NAME:-laravel}

    # Determine database host
    DB_HOST_NAME="db"
    
    # Update database settings for Warden
    :: Configuring database connection
    warden env exec -T php-fpm sed -i "s/^DB_CONNECTION=.*/DB_CONNECTION=mysql/" .env
    
    # Handle commented or uncommented DB configuration
    warden env exec -T php-fpm sed -i "s/^#\?[[:space:]]*DB_HOST=.*/DB_HOST=${DB_HOST_NAME}/" .env
    warden env exec -T php-fpm sed -i "s/^#\?[[:space:]]*DB_PORT=.*/DB_PORT=3306/" .env
    warden env exec -T php-fpm sed -i "s/^#\?[[:space:]]*DB_DATABASE=.*/DB_DATABASE=${DB_NAME}/" .env
    warden env exec -T php-fpm sed -i "s/^#\?[[:space:]]*DB_USERNAME=.*/DB_USERNAME=${DB_USER}/" .env
    warden env exec -T php-fpm sed -i "s/^#\?[[:space:]]*DB_PASSWORD=.*/DB_PASSWORD=${DB_PASS}/" .env
fi

# Run composer install without scripts to avoid issues before DB is configured
if [[ "${COMPOSER_INSTALL:-}" ]] && [[ ! "${CLEAN_INSTALL:-}" ]]; then
    :: Installing dependencies - skipping scripts
    warden env exec -T php-fpm composer install --no-scripts
fi

## import database only if --skip-db-import is not specified
if [[ "${DB_IMPORT:-}" ]] && [[ ! "${CLEAN_INSTALL:-}" ]]; then
    if [[ "${STREAM_DB:-}" ]] && [[ -z "${DB_DUMP}" ]] && [[ -n "${ENV_SOURCE_HOST+x}" ]]; then
        warden db-import --stream-db -e "$ENV_SOURCE" ${DB_FLAGS}
    else
        if [[ -z "$DB_DUMP" ]] && [[ -n "${ENV_SOURCE_HOST+x}" ]]; then
            DUMP_DIR="storage"
            if [[ ! -d "storage" ]] && [[ -d "app/storage" ]]; then
                DUMP_DIR="app/storage"
            elif [[ ! -d "storage" ]]; then
                mkdir -p "var"
                DUMP_DIR="var"
            fi
            DB_DUMP="${DUMP_DIR}/${WARDEN_ENV_NAME}_${ENV_SOURCE}-$(date +%Y%m%dT%H%M%S).sql.gz"
            :: "Downloading database from ${ENV_SOURCE}"
            warden db-dump --local --file="${DB_DUMP}" -e "$ENV_SOURCE" ${DB_FLAGS}
        fi

        if [[ -n "$DB_DUMP" ]] && [[ -f "$DB_DUMP" ]]; then
            :: "Importing database"
            warden db-import --file="${DB_DUMP}" ${DB_FLAGS}
        fi
    fi
fi

# Ensure .env exists
if ! warden env exec -T php-fpm test -f .env; then
    if warden env exec -T php-fpm test -f .env.example; then
        warden env exec -T php-fpm cp .env.example .env
    fi
fi

# Get actual database credentials from the db container
DB_USER=$(warden env exec -T db printenv MYSQL_USER 2>/dev/null)
DB_PASS=$(warden env exec -T db printenv MYSQL_PASSWORD 2>/dev/null)
DB_NAME=$(warden env exec -T db printenv MYSQL_DATABASE 2>/dev/null)

# Use defaults if not available
DB_USER=${DB_USER:-laravel}
DB_PASS=${DB_PASS:-laravel}
DB_NAME=${DB_NAME:-laravel}
DB_HOST_NAME="db"

# Configure .env if it exists and uses localhost
if warden env exec -T php-fpm grep -q "DB_HOST=127.0.0.1" .env 2>/dev/null; then
    :: "Configuring database connection (.env)"
    warden env exec -T php-fpm sed -i "s/^DB_CONNECTION=.*/DB_CONNECTION=mysql/" .env
    warden env exec -T php-fpm sed -i "s/^#\?[[:space:]]*DB_HOST=.*/DB_HOST=${DB_HOST_NAME}/" .env
    warden env exec -T php-fpm sed -i "s/^#\?[[:space:]]*DB_PORT=.*/DB_PORT=3306/" .env
    warden env exec -T php-fpm sed -i "s/^#\?[[:space:]]*DB_DATABASE=.*/DB_DATABASE=${DB_NAME}/" .env
    warden env exec -T php-fpm sed -i "s/^#\?[[:space:]]*DB_USERNAME=.*/DB_USERNAME=${DB_USER}/" .env
    warden env exec -T php-fpm sed -i "s/^#\?[[:space:]]*DB_PASSWORD=.*/DB_PASSWORD=${DB_PASS}/" .env
fi

# Support for older Laravel versions using .env.php
if warden env exec -T php-fpm test -f .env.php; then
    :: "Configuring database connection (.env.php)"
    # Standard keys
    warden env exec -T php-fpm sed -i "s/['\"]DB_HOST['\"][[:space:]]*=>.*/'DB_HOST' => '${DB_HOST_NAME}',/" .env.php
    warden env exec -T php-fpm sed -i "s/['\"]DB_PORT['\"][[:space:]]*=>.*/'DB_PORT' => '3306',/" .env.php
    warden env exec -T php-fpm sed -i "s/['\"]DB_DATABASE['\"][[:space:]]*=>.*/'DB_DATABASE' => '${DB_NAME}',/" .env.php
    warden env exec -T php-fpm sed -i "s/['\"]DB_USERNAME['\"][[:space:]]*=>.*/'DB_USERNAME' => '${DB_USER}',/" .env.php
    warden env exec -T php-fpm sed -i "s/['\"]DB_PASSWORD['\"][[:space:]]*=>.*/'DB_PASSWORD' => '${DB_PASS}',/" .env.php

    # Alternate keys (DATABASE_*)
    warden env exec -T php-fpm sed -i "s/['\"]DATABASE_HOST['\"][[:space:]]*=>.*/'DATABASE_HOST' => '${DB_HOST_NAME}',/" .env.php
    warden env exec -T php-fpm sed -i "s/['\"]DATABASE_PORT['\"][[:space:]]*=>.*/'DATABASE_PORT' => 3306,/" .env.php
    warden env exec -T php-fpm sed -i "s/['\"]DATABASE_NAME['\"][[:space:]]*=>.*/'DATABASE_NAME' => '${DB_NAME}',/" .env.php
    warden env exec -T php-fpm sed -i "s/['\"]DATABASE_USER['\"][[:space:]]*=>.*/'DATABASE_USER' => '${DB_USER}',/" .env.php
    warden env exec -T php-fpm sed -i "s/['\"]DATABASE_PASSWORD['\"][[:space:]]*=>.*/'DATABASE_PASSWORD' => '${DB_PASS}',/" .env.php
fi

# Ensure dependencies are installed before running artisan
if ! warden env exec -T php-fpm test -f "vendor/autoload.php"; then
    :: "Missing vendor/autoload.php - Installing dependencies"
    warden env exec -T php-fpm composer install
fi

# Generate application key if missing
if ! warden env exec -T php-fpm grep -q "APP_KEY=base64:" .env 2>/dev/null; then
    :: Generating application key
    warden env exec -T php-fpm php artisan key:generate || true
fi

if [[ ! $SKIP_MIGRATE ]]; then
    :: Running migrations
    # Force migration run (ignore failure)
    warden env exec -T php-fpm php artisan migrate --force || true
fi

warden set-config

echo "=========== THE APPLICATION HAS BEEN INSTALLED SUCCESSFULLY ==========="
echo "Frontend: https://${TRAEFIK_SUBDOMAIN:-app}.${TRAEFIK_DOMAIN:-test.test}/"

END_TIME=$(date +%s)
echo "Total build time: $((END_TIME - START_TIME)) seconds"
