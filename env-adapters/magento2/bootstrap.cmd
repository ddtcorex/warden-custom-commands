#!/usr/bin/env bash
[[ ! ${WARDEN_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

START_TIME=$(date +%s)

# Ensure .env exists before sourcing env-variables
if [[ ! -f "$(pwd)/.env" ]]; then
    echo "No .env file found. Creating minimal configuration..."
    ENV_NAME=$(basename "$(pwd)")
    cat > "$(pwd)/.env" <<ENVEOF
WARDEN_ENV_NAME=${ENV_NAME}
WARDEN_ENV_TYPE=magento2
WARDEN_WEB_ROOT=/

TRAEFIK_DOMAIN=${ENV_NAME}.test
TRAEFIK_SUBDOMAIN=app
ENVEOF
    sed -i "s/\${ENV_NAME}/${ENV_NAME}/g" .env
    echo "Created .env for ${ENV_NAME}"
fi

source "${WARDEN_HOME_DIR:-~/.warden}/commands/env-variables"

## configure command defaults
REQUIRED_FILES=("${WARDEN_ENV_PATH}/auth.json")
CLEAN_INSTALL=
META_PACKAGE="magento/project-community-edition"
META_VERSION=""
INCLUDE_SAMPLE=
DOWNLOAD_SOURCE=
DB_DUMP=
DB_IMPORT=1
MEDIA_SYNC=1
COMPOSER_INSTALL=1
ADMIN_CREATE=1
ENV_REQUIRED=
FIX_DEPS=

## argument parsing
while (( "$#" )); do
    case "$1" in
        --clean-install)
            CLEAN_INSTALL=1
            COMPOSER_INSTALL=
            DB_IMPORT=
            MEDIA_SYNC=
            shift
            ;;
        --fix-deps)
            FIX_DEPS=1
            shift
            ;;
        --meta-package=*)
            META_PACKAGE="${1#*=}"
            shift
            ;;
        --meta-version=*|--version=*)
            META_VERSION="${1#*=}"
            if
                ! test $(version "${META_VERSION}") -ge "$(version 2.0.0)" \
                && [[ ! "${META_VERSION}" =~ ^2\.[0-9]+\.x$ ]]
            then
                fatal "Invalid version ${META_VERSION} specified (valid values are 2.0.0 or later)"
            fi
            shift
            ;;
        --include-sample)
            INCLUDE_SAMPLE=1
            shift
            ;;
        --download-source)
            DOWNLOAD_SOURCE=1
            COMPOSER_INSTALL=
            ENV_REQUIRED=1
            shift
            ;;
        --skip-db-import)
            DB_IMPORT=
            shift
            ;;
        --skip-media-sync)
            MEDIA_SYNC=
            shift
            ;;
        --skip-composer-install)
            COMPOSER_INSTALL=
            shift
            ;;
        --skip-admin-create)
            ADMIN_CREATE=
            shift
            ;;
        --db-dump=*)
            DB_DUMP="${1#*=}"
            ENV_REQUIRED=1
            shift
            ;;
        *)
            shift
            ;;
    esac
done

## Run fix-deps if flag is set (when .env was just created)
if [[ -n "${FIX_DEPS}" ]]; then
    :: Running fix-deps to set correct dependency versions
    
    SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
    if [[ -f "${SCRIPT_DIR}/fix-deps.cmd" ]]; then
        # Run fix-deps (it will auto-detect version or use META_VERSION)
        if [[ -n "${META_VERSION:-}" ]]; then
            source "${SCRIPT_DIR}/fix-deps.cmd" --version="${META_VERSION}" 2>&1 | grep -v "\[DRY RUN\]\|Run without"
        else
            # Prompt user for version if not set
            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "Magento version not specified"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""
            echo "Please specify the Magento version (e.g., 2.4.8, 2.4.6-p1):"
            read -p "Version: " USER_VERSION
            
            if [[ -n "${USER_VERSION}" ]]; then
                # Save to .env
                if ! grep -q "^META_VERSION=" .env 2>/dev/null; then
                    echo "META_VERSION=${USER_VERSION}" >> .env
                else
                    sed -i "s/^META_VERSION=.*/META_VERSION=${USER_VERSION}/" .env
                fi
                # Also update META_VERSION variable for later use in this script
                META_VERSION="${USER_VERSION}"
                
                # Run fix-deps with specified version
                source "${SCRIPT_DIR}/fix-deps.cmd" --version="${USER_VERSION}" 2>&1 | grep -v "\[DRY RUN\]\|Run without"
            else
                echo "⚠ No version specified. Using default dependency versions."
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
if [[ $ENV_REQUIRED ]] && [ -z ${!ENV_SOURCE_HOST_VAR+x} ]; then
    echo "Invalid environment '${ENV_SOURCE}'"
    exit 2
fi

## create an auth.json file in case it is missing during a clean installation
if [ ! -f "${WARDEN_ENV_PATH}/auth.json" ] && [ $CLEAN_INSTALL ]; then
    echo "Creating auth.json since it’s missing..."
    cat << EOT > "${WARDEN_ENV_PATH}/auth.json"
{
    "http-basic": {
        "repo.magento.com": {
            "username": "b5f6ec5124c74fac2776b140628592f4",
            "password": "bbeaea9cdaecaa3f4805e2fc622d8058"
        }
    }
}
EOT
fi

## download files from the remote
if [[ $DOWNLOAD_SOURCE ]]; then
    warden download-source -e=${ENV_SOURCE}
    
    # Combined file operations to reduce container exec overhead
    warden env exec php-fpm sh -c "
        rm -rf /var/www/html/app/etc/env.php && \
        mkdir -p /var/www/html/generated \
                 /var/www/html/pub/media \
                 /var/www/html/pub/static \
                 /var/www/html/var
    " || true
fi

## include check for DB_DUMP file only when database import is expected
[[ ${DB_IMPORT} ]] && [[ "$DB_DUMP" ]] && REQUIRED_FILES+=("${DB_DUMP}")

:: Verifying configuration
INIT_ERROR=

## attempt to install mutagen if not already present
if [[ $OSTYPE =~ ^darwin ]] && ! which mutagen >/dev/null 2>&1 && which brew >/dev/null 2>&1; then
    warning "Mutagen could not be found; attempting install via brew."
    brew install havoc-io/mutagen/mutagen
fi

## check for presence of host machine dependencies
for DEP_NAME in warden mutagen pv; do
    if [[ "${DEP_NAME}" = "mutagen" ]] && [[ ! $OSTYPE =~ ^darwin ]]; then
        continue
    fi

    if ! which "${DEP_NAME}" 2>/dev/null >/dev/null; then
        error "Command '${DEP_NAME}' not found. Please install."
        INIT_ERROR=1
    fi
done

## verify mutagen version constraint
MUTAGEN_VERSION=$(mutagen version 2>/dev/null) || true
MUTAGEN_REQUIRE=0.11.4
if [[ $OSTYPE =~ ^darwin ]] && ! test $(version ${MUTAGEN_VERSION}) -ge $(version ${MUTAGEN_REQUIRE}); then
    error "Mutagen ${MUTAGEN_REQUIRE} or greater is required (version ${MUTAGEN_VERSION} is installed)"
    INIT_ERROR=1
fi

## check for presence of local configuration files to ensure they exist
for REQUIRED_FILE in ${REQUIRED_FILES[@]}; do
    if [[ ! -f "${REQUIRED_FILE}" ]]; then
        error "Missing local file: ${REQUIRED_FILE}"
        INIT_ERROR=1
    fi
done

## exit script if there are any missing dependencies or configuration files
[[ ${INIT_ERROR} ]] && exit 1

:: Starting Warden
warden svc up
if [[ ! -f ${WARDEN_HOME_DIR}/ssl/certs/${TRAEFIK_DOMAIN}.crt.pem ]]; then
    warden sign-certificate ${TRAEFIK_DOMAIN}
fi

:: Initializing environment
warden env up

## wait for mariadb to start listening for connections
warden shell -c "while ! nc -z db 3306 </dev/null; do sleep 2; done"

if [[ $COMPOSER_INSTALL ]]; then
    :: Installing dependencies
    warden env exec php-fpm composer install
fi

## import database only if --skip-db-import is not specified
if [[ ${DB_IMPORT} ]]; then
    if [[ -z "$DB_DUMP" ]]; then
        DB_DUMP="var/${WARDEN_ENV_NAME}_${ENV_SOURCE}-`date +%Y%m%dT%H%M%S`.sql.gz"
        :: Get database
        warden db-dump --file="${DB_DUMP}" -e "$ENV_SOURCE"
    fi

    if [[ "$DB_DUMP" ]]; then
        :: Importing database
        warden db-import --file="${DB_DUMP}"
    fi
fi

if [ -z ${WARDEN_ENCRYPT_KEY+x} ]; then
    ENCRYPT_KEY=00000000000000000000000000000000
else
    ENCRYPT_KEY="$WARDEN_ENCRYPT_KEY"
fi

if [ ! -f "${WARDEN_ENV_PATH}/app/etc/env.php" ] && [ ! $CLEAN_INSTALL ]; then
    cat << EOT > "${WARDEN_ENV_PATH}/app/etc/env.php"
<?php
return [
    'backend' => [
        'frontName' => 'admin'
    ],
    'crypt' => [
        'key' => '${ENCRYPT_KEY}'
    ],
    'db' => [
        'table_prefix' => '${DB_PREFIX}',
        'connection' => [
            'default' => [
                'host' => 'db',
                'dbname' => 'magento',
                'username' => 'magento',
                'password' => 'magento',
                'active' => '1'
            ],
             'indexer' => [
                 'host' => 'db',
                 'dbname' => 'magento',
                 'username' => 'magento',
                 'password' => 'magento',
             ]
        ]
    ],
    'resource' => [
        'default_setup' => [
            'connection' => 'default'
        ]
    ],
    'x-frame-options' => 'SAMEORIGIN',
    'MAGE_MODE' => 'developer',
    'session' => [
        'save' => 'files'
    ],
    'cache_types' => [
        'config' => 1,
        'layout' => 1,
        'block_html' => 0,
        'collections' => 1,
        'reflection' => 1,
        'db_ddl' => 1,
        'compiled_config' => 1,
        'eav' => 1,
        'customer_notification' => 1,
        'config_integration' => 1,
        'config_integration_api' => 1,
        'full_page' => 0,
        'config_webservice' => 1,
        'translate' => 1
    ],
    'install' => [
        'date' => 'Mon, 01 May 2023 00:00:00 +0000'
    ]
];

EOT
fi

if [[ ${CLEAN_INSTALL} ]] && [[ ! -f "${WARDEN_WEB_ROOT}/composer.json" ]]; then
    :: Installing Magento website
    
    # Clean up and prepare directory in one go
    warden env exec php-fpm sh -c "
        rsync -a auth.json /home/www-data/.composer/ && \
        rm -rf /tmp/create-project && \
        composer create-project -q -n --repository-url=https://repo.magento.com/ \"${META_PACKAGE}\" /tmp/create-project \"${META_VERSION}\" && \
        rsync -a /tmp/create-project/ /var/www/html/ && \
        rm -rf /tmp/create-project
    "

    # Magento version-specific search engine configuration
    # Default to OpenSearch (Magento 2.4.8+ or unknown)
    SEARCH_ENGINE="opensearch"
    SEARCH_HOST="opensearch"
    SEARCH_COMMAND="opensearch"
    
    # Determine version-specific overrides
    if [[ -n "${META_VERSION}" ]]; then
        if test "$(version "${META_VERSION}")" -lt "$(version "2.4.8")"; then
            # Pre-2.4.8: Uses "elasticsearch7" engine name (even for OpenSearch connection in 2.4.6/7)
            SEARCH_ENGINE="elasticsearch7"
            SEARCH_COMMAND="elasticsearch"
            
            # Use Elasticsearch host if OpenSearch is not enabled
            if [[ "${WARDEN_OPENSEARCH:-0}" -ne "1" ]]; then
                SEARCH_HOST="elasticsearch"
            fi
        fi
    elif [[ "${WARDEN_OPENSEARCH:-0}" -eq "1" ]]; then
         # Pre-2.4.8 fallback with explicit OpenSearch enabled
         SEARCH_ENGINE="elasticsearch7"
         SEARCH_COMMAND="elasticsearch"
    fi

    warden env exec php-fpm bin/magento setup:install \
        --backend-frontname=admin \
        --db-host=db \
        --db-name=magento \
        --db-user=magento \
        --db-password=magento \
        --db-prefix=${DB_PREFIX} \
        --search-engine=${SEARCH_ENGINE} \
        --${SEARCH_COMMAND}-host=${SEARCH_HOST} \
        --${SEARCH_COMMAND}-port=9200 \
        --${SEARCH_COMMAND}-index-prefix=magento2 \
        --${SEARCH_COMMAND}-enable-auth=0 \
        --${SEARCH_COMMAND}-timeout=15 || true
fi

warden set-config

if [[ ${CLEAN_INSTALL} ]] && [[ $INCLUDE_SAMPLE ]]; then
    :: Installing sample data
    # Chained execution for performance
    warden env exec php-fpm sh -c "
        bin/magento sample:deploy && \
        bin/magento setup:upgrade && \
        bin/magento indexer:reindex && \
        bin/magento cache:flush
    "
fi

if [[ $MEDIA_SYNC ]]; then
    :: Syncing media from remote server
    warden sync-media -e "$ENV_SOURCE"
fi

if [[ $ADMIN_CREATE -eq "1" ]]; then
    :: Creating admin user
    warden env exec php-fpm bin/magento admin:user:create \
        --admin-user=admin \
        --admin-password=Admin123$ \
        --admin-firstname=Admin \
        --admin-lastname=User \
        --admin-email="admin@${TRAEFIK_SUBDOMAIN}.${TRAEFIK_DOMAIN}" || true
fi

echo "=========== THE APPLICATION HAS BEEN INSTALLED SUCCESSFULLY ==========="
echo "Frontend: https://${TRAEFIK_SUBDOMAIN}.${TRAEFIK_DOMAIN}/"
echo "Admin:    https://${TRAEFIK_SUBDOMAIN}.${TRAEFIK_DOMAIN}/admin"

if [[ $ADMIN_CREATE -eq "1" ]]; then
    echo "Username: admin"
    echo "Password: Admin123$"
fi

END_TIME=$(date +%s)

echo "Total build time: $((END_TIME - START_TIME)) seconds"
