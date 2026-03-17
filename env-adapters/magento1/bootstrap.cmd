#!/usr/bin/env bash
set -euo pipefail

[[ ! "${WARDEN_DIR:-}" ]] && >&2 printf "\033[31mNot intended to run directly!\033[0m\n" && exit 1

START_TIME=$(date +%s)
_ADAPTER_DIR=$(dirname "${BASH_SOURCE[0]}")
source "${_ADAPTER_DIR}"/env-variables

## configure command defaults
FRESH_INSTALL=
META_PACKAGE="magento/project-community-edition"
META_VERSION=""
INCLUDE_SAMPLE=
CLONE_MODE=
CODE_ONLY=
DB_DUMP=
DB_IMPORT=1
STREAM_DB=1
MEDIA_SYNC=1
COMPOSER_INSTALL=1
ADMIN_CREATE=1
ENV_REQUIRED=
MAGE_USERNAME=
MAGE_PASSWORD=

## argument parsing
while [[ "$#" -gt 0 ]]; do
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
            MEDIA_SYNC=
            shift
            ;;
        --include-sample)
            INCLUDE_SAMPLE=1
            shift
            ;;

        # Disable/Skip Options
        --no-db|--skip-db-import)
            DB_IMPORT=
            shift
            ;;
        --no-media|--skip-media-sync)
            MEDIA_SYNC=
            shift
            ;;
        --no-composer|--skip-composer-install)
            COMPOSER_INSTALL=
            shift
            ;;
        --no-admin|--skip-admin-create)
            ADMIN_CREATE=
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

        # Valued Options (Package / Version)
        -p|--meta-package|-p=*|--meta-package=*)
            [[ "$1" == *=* ]] && META_PACKAGE="${1#*=}" || { META_PACKAGE="${2:-}"; shift; }
            shift
            ;;
        --version|--meta-version|--version=*|--meta-version=*)
            [[ "$1" == *=* ]] && META_VERSION="${1#*=}" || { META_VERSION="${2:-}"; shift; }
            shift
            ;;

        # Database Configuration
        --db-dump|--db-dump=*)
            [[ "$1" == *=* ]] && DB_DUMP="${1#*=}" || { DB_DUMP="${2:-}"; shift; }
            ENV_REQUIRED=1
            shift
            ;;
        --exclude-sensitive-data)
            # Handled via env-variables if needed, or we can keep it as a flag
            shift
            ;;

        # Credentials
        --mage-username|--mage-username=*)
            [[ "$1" == *=* ]] && MAGE_USERNAME="${1#*=}" || { MAGE_USERNAME="${2:-}"; shift; }
            shift
            ;;
        --mage-password|--mage-password=*)
            [[ "$1" == *=* ]] && MAGE_PASSWORD="${1#*=}" || { MAGE_PASSWORD="${2:-}"; shift; }
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

# Clone mode with --code-only disables DB and media sync
if [[ -n "${CLONE_MODE}" ]] && [[ -n "${CODE_ONLY}" ]]; then
    DB_IMPORT=
    MEDIA_SYNC=
fi

# Map CLEAN_INSTALL for internal logic
CLEAN_INSTALL="${FRESH_INSTALL}"

## Auto-detect clean install if local.xml is missing and not cloning
if [[ ! -f "${WARDEN_ENV_PATH}/app/etc/local.xml" ]] && [[ -z "${CLONE_MODE:-}" ]] && [[ -z "${CLEAN_INSTALL:-}" ]] && [[ -z "${DB_DUMP:-}" ]] && [[ -z "${DB_IMPORT:-}" ]]; then
    printf "No local.xml found. Assuming --clean-install mode.\n"
    CLEAN_INSTALL=1
    COMPOSER_INSTALL=
    DB_IMPORT=
    MEDIA_SYNC=
fi

## validate the selected environment
if [[ -n "${ENV_REQUIRED:-}" ]] && [ -z "${!ENV_SOURCE_HOST_VAR+x}" ]; then
    error "Invalid environment '${ENV_SOURCE:-}'"
    exit 2
fi

## include check for DB_DUMP file only when database import is expected
[[ ${DB_IMPORT} ]] && [[ "$DB_DUMP" ]] && REQUIRED_FILES+=("${DB_DUMP}")

:: Verifying configuration
INIT_ERROR=

## check for presence of host machine dependencies
for DEP_NAME in warden pv; do
    if ! command -v "${DEP_NAME}" >/dev/null 2>&1; then
        error "Command '${DEP_NAME}' not found. Please install."
        INIT_ERROR=1
    fi
done

## check for presence of local configuration files to ensure they exist
for REQUIRED_FILE in ${REQUIRED_FILES[@]}; do
    if [[ ! -f "${REQUIRED_FILE}" ]]; then
        error "Missing local file: ${REQUIRED_FILE}"
        INIT_ERROR=1
    fi
done

## exit script if there are any missing dependencies or configuration files
## count dependencies missing
[[ -n "${INIT_ERROR:-}" ]] && exit 1

:: Starting Warden
warden svc up
if [[ ! -f ${WARDEN_HOME_DIR}/ssl/certs/${TRAEFIK_DOMAIN}.crt.pem ]]; then
    warden sign-certificate "${TRAEFIK_DOMAIN}"
fi

:: Initializing environment
warden env up --remove-orphans

## wait for mariadb to start listening for connections
warden shell -c "while ! nc -z db 3306 </dev/null; do sleep 2; done"

## create an auth.json file in case it is missing
if [[ ! -f "${WARDEN_ENV_PATH}/auth.json" ]]; then
    printf "Creating auth.json since it’s missing...\n"

    if [[ -z "${MAGE_USERNAME:-}" ]] || [[ -z "${MAGE_PASSWORD:-}" ]]; then
        GLOBAL_AUTH_JSON="${HOME}/.composer/auth.json"
        if [[ -f "${GLOBAL_AUTH_JSON}" ]]; then
            if grep -q "repo.magento.com" "${GLOBAL_AUTH_JSON}"; then
                printf "Found global auth.json at %s\n" "${GLOBAL_AUTH_JSON}"
                if [[ "${YES_TO_ALL:-0}" == "1" ]]; then
                    USE_GLOBAL_AUTH="Y"
                else
                    read -p "Use credentials from global auth.json? [Y/n] " USE_GLOBAL_AUTH
                    USE_GLOBAL_AUTH=${USE_GLOBAL_AUTH:-Y}
                fi
                if [[ "${USE_GLOBAL_AUTH}" =~ ^[Yy]$ ]]; then
                    cp "${GLOBAL_AUTH_JSON}" "${WARDEN_ENV_PATH}/auth.json"
                fi
            fi
        fi
    fi

    if [[ ! -f "${WARDEN_ENV_PATH}/auth.json" ]]; then
        if [[ -z "${MAGE_USERNAME:-}" ]]; then
            printf "\nPlease enter your Magento Marketplace credentials (public/private keys):\n"
            read -p "Public Key (Username): " MAGE_USERNAME
        fi
        if [[ -z "${MAGE_PASSWORD:-}" ]]; then
             read -p "Private Key (Password): " MAGE_PASSWORD
        fi
        if [[ -n "${MAGE_USERNAME}" ]] && [[ -n "${MAGE_PASSWORD}" ]]; then
            cat << EOT > "${WARDEN_ENV_PATH}/auth.json"
{
    "http-basic": {
        "repo.magento.com": {
            "username": "${MAGE_USERNAME}",
            "password": "${MAGE_PASSWORD}"
        }
    }
}
EOT
        fi
    fi
fi

if [[ -n "${CLONE_MODE:-}" ]]; then
    :: Downloading files from remote
    warden env-sync --file --source="${ENV_SOURCE}"
    warden env exec php-fpm sh -c "mkdir -p /var/www/html/media/catalog /var/www/html/media/wysiwyg /var/www/html/media/downloadable" || true
fi

if [[ -n "${COMPOSER_INSTALL:-}" ]]; then
    :: Installing dependencies
    warden env exec php-fpm composer install || true
fi

## import database only if --skip-db-import is not specified
if [[ -n "${DB_IMPORT:-}" ]]; then
    if [[ -n "${STREAM_DB:-}" ]]; then
        warden db-import --stream-db -e "$ENV_SOURCE"
    elif [[ -z "${DB_DUMP:-}" ]]; then
        DB_DUMP="var/${WARDEN_ENV_NAME}_${ENV_SOURCE}-$(date +%Y%m%dT%H%M%S).sql.gz"
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

if [ -z "${WARDEN_ENCRYPT_KEY+x}" ]; then
    ENCRYPT_KEY=$(od -vN 16 -An -tx1 /dev/urandom | tr -d ' \n')
else
    ENCRYPT_KEY="$WARDEN_ENCRYPT_KEY"
fi

if [ ! -f "${WARDEN_ENV_PATH}/app/etc/local.xml" ] && [ -z "${CLEAN_INSTALL:-}" ]; then
    :: Configuring local.xml
    cat << EOT > "${WARDEN_ENV_PATH}/app/etc/local.xml"
<?xml version="1.0"?>
<config>
    <global>
        <install>
            <date><![CDATA[$(date -u +"%a, %d %b %Y %H:%M:%S +0000")]]></date>
        </install>
        <crypt>
            <key><![CDATA[${ENCRYPT_KEY}]]></key>
        </crypt>
        <disable_local_modules>false</disable_local_modules>
        <resources>
            <default_setup>
                <connection>
                    <host><![CDATA[db]]></host>
                    <username><![CDATA[magento]]></username>
                    <password><![CDATA[magento]]></password>
                    <dbname><![CDATA[magento]]></dbname>
                    <initStatements><![CDATA[SET NAMES utf8]]></initStatements>
                    <model><![CDATA[mysql4]]></model>
                    <type><![CDATA[pdo_mysql]]></type>
                    <pdoType></pdoType>
                    <active>1</active>
                </connection>
            </default_setup>
        </resources>
        <session_save><![CDATA[files]]></session_save>
    </global>
    <admin>
        <routers>
            <adminhtml>
                <args>
                    <frontName><![CDATA[admin]]></frontName>
                </args>
            </adminhtml>
        </routers>
    </admin>
</config>
EOT
fi

warden set-config

if [[ -n "${MEDIA_SYNC:-}" ]]; then
    :: Syncing media from remote server
    warden sync-media -e "$ENV_SOURCE"
fi

if [[ "${ADMIN_CREATE:-0}" -eq "1" ]]; then
    :: Creating admin user
    printf "INSERT IGNORE INTO ${DB_PREFIX}admin_user(username, firstname, lastname, email, password, created, lognum, reload_acl_flag, is_active, extra, rp_token, rp_token_created_at)VALUES('admin', 'Admin', 'User', 'admin@${TRAEFIK_SUBDOMAIN}.${TRAEFIK_DOMAIN}', MD5('Admin123$'), NOW(), 0, 0, 1, NULL, NULL, NOW());" | warden db connect
    USER_ID=$(printf "SELECT user_id FROM ${DB_PREFIX}admin_user WHERE username='admin'\G" | warden db connect | grep user_id | awk '{print $2}')
    if [[ -n "${USER_ID}" ]]; then
        printf "INSERT IGNORE INTO ${DB_PREFIX}admin_role (parent_id, tree_level, sort_order, role_type, user_id, role_name) VALUES (1, 2, 0, 'U', ${USER_ID}, 'Administrator');" | warden db connect
    fi
fi

:: Build Complete
printf "=========== THE APPLICATION HAS BEEN INSTALLED SUCCESSFULLY ===========\n"
printf "Frontend: https://%s.%s/\n" "${TRAEFIK_SUBDOMAIN}" "${TRAEFIK_DOMAIN}"
printf "Admin:    https://%s.%s/admin\n" "${TRAEFIK_SUBDOMAIN}" "${TRAEFIK_DOMAIN}"

if [[ "${ADMIN_CREATE:-0}" -eq "1" ]]; then
    printf "Username: admin\n"
    printf "Password: Admin123$\n"
fi

END_TIME=$(date +%s)
printf "Total build time: %d seconds\n" "$((END_TIME - START_TIME))"
