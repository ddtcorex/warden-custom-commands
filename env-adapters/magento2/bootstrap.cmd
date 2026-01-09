#!/usr/bin/env bash
set -u
[[ ! "${WARDEN_DIR:-}" ]] && >&2 printf "\033[31mThis script is not intended to be run directly!\033[0m\n" && exit 1

START_TIME=$(date +%s)

# env-variables is already sourced by the root dispatcher

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
HYVA_INSTALL=
HYVA_TOKEN=


## argument parsing
while [[ "$#" -gt 0 ]]; do
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
        -p|--meta-package)
            META_PACKAGE="$2"
            shift 2
            ;;
        -p=*|--meta-package=*)
            META_PACKAGE="${1#*=}"
            shift
            ;;
        -v|--meta-version|--version)
            META_VERSION="$2"
            if ! test $(version "${META_VERSION}") -ge "$(version 2.0.0)" && [[ ! "${META_VERSION}" =~ ^2\.[0-9]+\.x$ ]]; then
                fatal "Invalid version ${META_VERSION} specified (valid values are 2.0.0 or later)"
            fi
            shift 2
            ;;
        -v=*|--meta-version=*|--version=*)
            META_VERSION="${1#*=}"
            if ! test $(version "${META_VERSION}") -ge "$(version 2.0.0)" && [[ ! "${META_VERSION}" =~ ^2\.[0-9]+\.x$ ]]; then
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
        --no-stream-db)
            STREAM_DB=
            shift
            ;;

        --hyva-install)
            HYVA_INSTALL=1
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
                # Run fix-deps with specified version
                META_VERSION="${USER_VERSION}"
                source "${SCRIPT_DIR}/fix-deps.cmd" --version="${META_VERSION}" 2>&1 | grep -v "\[DRY RUN\]\|Run without"
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
if [[ "${ENV_REQUIRED:-}" ]] && [[ -z "${!ENV_SOURCE_HOST_VAR+x}" ]]; then
    printf "Invalid environment '%s'\n" "${ENV_SOURCE}" >&2
    exit 2
fi

## create an auth.json file in case it is missing during a clean installation
if [[ ! -f "${WARDEN_ENV_PATH}/auth.json" ]] && [[ "${CLEAN_INSTALL:-}" ]]; then
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

if [[ "${DOWNLOAD_SOURCE:-}" ]]; then
    ## download files from the remote
    warden sync --file --source="${ENV_SOURCE}"
    
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
if [[ "${OSTYPE}" =~ ^darwin ]] && ! command -v mutagen >/dev/null 2>&1 && command -v brew >/dev/null 2>&1; then
    warning "Mutagen could not be found; attempting install via brew."
    brew install havoc-io/mutagen/mutagen
fi

## check for presence of host machine dependencies
for DEP_NAME in warden mutagen pv; do
    if [[ "${DEP_NAME}" = "mutagen" ]] && [[ ! $OSTYPE =~ ^darwin ]]; then
        continue
    fi

    if ! command -v "${DEP_NAME}" >/dev/null 2>&1; then
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

if [[ "${COMPOSER_INSTALL:-}" ]]; then
    :: Installing dependencies
    warden env exec php-fpm composer install
fi

## import database only if --skip-db-import is not specified
if [[ "${DB_IMPORT:-}" ]]; then
    if [[ "${STREAM_DB:-}" ]]; then
        warden db-import --stream-db -e "$ENV_SOURCE"
    elif [[ -z "$DB_DUMP" ]]; then
        DB_DUMP="var/${WARDEN_ENV_NAME}_${ENV_SOURCE}-`date +%Y%m%dT%H%M%S`.sql.gz"
        :: Get database
        warden db-dump --file="${DB_DUMP}" -e "$ENV_SOURCE"
        
        if [[ "$DB_DUMP" ]]; then
            :: Importing database
            warden db-import --file="${DB_DUMP}"
        fi
    else
        :: Importing database
        warden db-import --file="${DB_DUMP}"
    fi
fi

if [ -z ${WARDEN_ENCRYPT_KEY+x} ]; then
    ENCRYPT_KEY=00000000000000000000000000000000
else
    ENCRYPT_KEY="$WARDEN_ENCRYPT_KEY"
fi

# Get actual database credentials from the db container
DB_USER=$(warden env exec -T db printenv MYSQL_USER 2>/dev/null)
DB_PASS=$(warden env exec -T db printenv MYSQL_PASSWORD 2>/dev/null)
DB_NAME=$(warden env exec -T db printenv MYSQL_DATABASE 2>/dev/null)

# Use defaults if not available
DB_USER=${DB_USER:-magento}
DB_PASS=${DB_PASS:-magento}
DB_NAME=${DB_NAME:-magento}

# Determine database host
DB_HOST_NAME="db"

if [ ! -f "${WARDEN_ENV_PATH}/app/etc/env.php" ] && [ ! $CLEAN_INSTALL ]; then
    :: Configuring environment variables
    printf "WARDEN_ENV_PATH: %s\n" "${WARDEN_ENV_PATH}"
    if ! mkdir -p "${WARDEN_ENV_PATH}/app/etc"; then
        printf "😮 \033[31mFailed to create directory %s/app/etc\033[0m\n" "${WARDEN_ENV_PATH}" >&2
        exit 1
    fi
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
        'table_prefix' => '${DB_PREFIX:-}',
        'connection' => [
            'default' => [
                'host' => '${DB_HOST_NAME}',
                'dbname' => '${DB_NAME}',
                'username' => '${DB_USER}',
                'password' => '${DB_PASS}',
                'active' => '1'
            ],
             'indexer' => [
                 'host' => '${DB_HOST_NAME}',
                 'dbname' => '${DB_NAME}',
                 'username' => '${DB_USER}',
                 'password' => '${DB_PASS}',
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

    if [[ "${HYVA_INSTALL:-}" ]]; then
        :: Setting up Hyvä
        
        # Check Magento version compatibility (Hyvä requires 2.4.4+)
        if [[ -n "${META_VERSION:-}" ]] && ! test $(version "${META_VERSION}") -ge "$(version 2.4.4)"; then
            warning "Hyvä requires Magento 2.4.4 or higher (detected ${META_VERSION}). Skipping Hyvä installation."
            HYVA_INSTALL=
        fi
    fi

    if [[ "${HYVA_INSTALL:-}" ]]; then
        # Use default token
        HYVA_TOKEN="2a749843f9e64f7e5f74495baafbd7422271d23933e8d00059a3072767c0"
        
        # Register Hyvä repository (using Private Packagist), set credentials and install base packages
        # We run this in a single sh -c block for consistency and to ensure credentials are found
        warden env exec php-fpm sh -c "
            composer config http-basic.hyva-themes.repo.packagist.com token \"${HYVA_TOKEN}\" && \
            composer config repositories.hyva-themes composer https://hyva-themes.repo.packagist.com/app-hyva-test-dv1dgx/ && \
            composer require -n hyva-themes/magento2-default-theme
        "
        
        # Also mirror the token to the host auth.json for persistence if it exists
        if [[ -f "${WARDEN_ENV_PATH}/auth.json" ]]; then
            warden env exec php-fpm composer config -g http-basic.hyva-themes.repo.packagist.com token "${HYVA_TOKEN}"
        fi
    fi

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
        --db-host=${DB_HOST_NAME} \
        --db-name=${DB_NAME} \
        --db-user=${DB_USER} \
        --db-password=${DB_PASS} \
        --db-prefix=${DB_PREFIX:-} \
        --search-engine=${SEARCH_ENGINE} \
        --${SEARCH_COMMAND}-host=${SEARCH_HOST} \
        --${SEARCH_COMMAND}-port=9200 \
        --${SEARCH_COMMAND}-index-prefix=magento2 \
        --${SEARCH_COMMAND}-enable-auth=0 \
        --${SEARCH_COMMAND}-timeout=15 || true
fi

warden set-config

if [[ "${CLEAN_INSTALL:-}" ]] && [[ "${INCLUDE_SAMPLE:-}" ]]; then
    :: Installing sample data
    # Chained execution for performance
    warden env exec php-fpm sh -c "
        bin/magento sample:deploy && \
        bin/magento setup:upgrade && \
        bin/magento indexer:reindex && \
        bin/magento cache:flush
    "
fi

if [[ "${CLEAN_INSTALL:-}" ]] && [[ "${HYVA_INSTALL:-}" ]]; then
    HYVA_THEME_ID=$(warden env exec -T php-fpm mysql -u "${DB_USER}" -p"${DB_PASS}" -h "${DB_HOST_NAME}" "${DB_NAME}" -N -s -e "SELECT theme_id FROM theme WHERE code = 'hyva/default'" 2>/dev/null || echo "")
    if [[ -n "${HYVA_THEME_ID}" ]]; then
        :: Activating Hyvä theme
        warden env exec php-fpm bin/magento config:set design/theme/theme_id "${HYVA_THEME_ID}" || true
        warden env exec php-fpm bin/magento cache:flush
    fi
fi

if [[ "${ADMIN_CREATE:-}" == "1" ]]; then
    :: Creating admin user
    warden env exec php-fpm bin/magento admin:user:create \
        --admin-user=admin \
        --admin-password=Admin123$ \
        --admin-firstname=Admin \
        --admin-lastname=User \
        --admin-email="admin@${TRAEFIK_SUBDOMAIN}.${TRAEFIK_DOMAIN}" || true
fi

if [[ "${MEDIA_SYNC:-}" ]]; then
    warden sync --media --source="${ENV_SOURCE}"
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
