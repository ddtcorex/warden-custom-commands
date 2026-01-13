#!/usr/bin/env bash
set -u
[[ ! "${WARDEN_DIR:-}" ]] && >&2 printf "\033[31mThis script is not intended to be run directly!\033[0m\n" && exit 1

# env-variables is already sourced by the root dispatcher

function before_set_config() { :; }
function after_set_config() { :; }

function version { echo "$@" | awk -F. '{ printf("%d%03d%03d%03d\n", $1,$2,$3,$4); }'; }

ENV_HOOKS_FILE="${WARDEN_ENV_PATH}/.warden/hooks"
if [ -f "${ENV_HOOKS_FILE}" ]; then
    source "${ENV_HOOKS_FILE}"
fi

:: Installing application
warden env exec php-fpm bin/magento setup:upgrade || true

:: Importing config
warden env exec php-fpm bin/magento app:config:import || true

if [ ! -f "${WARDEN_ENV_PATH}/app/etc/config.php" ]; then
    :: Enabling all modules
    warden env exec php-fpm bin/magento module:enable --all
fi

if [[ "$WARDEN_VARNISH" -eq "1" ]]; then
    :: Configuring Varnish
    warden env exec php-fpm bin/magento setup:config:set --http-cache-hosts=varnish || true
    warden env exec php-fpm bin/magento config:set system/full_page_cache/varnish/backend_host varnish || true
    warden env exec php-fpm bin/magento config:set system/full_page_cache/varnish/backend_port 80 || true
    warden env exec php-fpm bin/magento config:set system/full_page_cache/caching_application 2 || true
    warden env exec php-fpm bin/magento config:set system/full_page_cache/ttl 604800 || true
else
    warden env exec php-fpm bin/magento config:set system/full_page_cache/caching_application 1 || true
fi

if [[ "$WARDEN_ELASTICSEARCH" -eq "1" ]] || [[ "$WARDEN_OPENSEARCH" -eq "1" ]]; then
    MAGENTO_VERSION=$(warden env exec php-fpm bin/magento --version 2>/dev/null | awk '{print $3}')
    
    # Magento version-specific search engine configuration
    # Default to OpenSearch (Magento 2.4.8+ or unknown)
    SEARCH_ENGINE="opensearch"
    SEARCH_HOST="opensearch"
    CONFIG_PREFIX="opensearch"
    
    # Determine version-specific overrides
    if [[ -n "${MAGENTO_VERSION}" ]]; then
        if test "$(version "${MAGENTO_VERSION}")" -lt "$(version "2.4.8")"; then
            # Pre-2.4.8: Uses "elasticsearch7" engine name (even for OpenSearch connection in 2.4.6/7)
            SEARCH_ENGINE="elasticsearch7"
            CONFIG_PREFIX="elasticsearch7"
            
            # Use Elasticsearch host if OpenSearch is not enabled
            if [[ "${WARDEN_OPENSEARCH:-0}" -ne "1" ]]; then
                SEARCH_HOST="elasticsearch"
            fi
        fi
    elif [[ "${WARDEN_OPENSEARCH:-0}" -eq "1" ]]; then
        # Unknown version with explicit OpenSearch enabled: use elasticsearch7 engine (safer assumption)
        SEARCH_ENGINE="elasticsearch7"
        CONFIG_PREFIX="elasticsearch7"
    fi
    
    if [[ "${SEARCH_ENGINE}" == "opensearch" ]]; then
        :: Configuring OpenSearch
    else
        :: Configuring Elasticsearch
    fi

    warden env exec php-fpm bin/magento config:set catalog/search/engine $SEARCH_ENGINE || true
    warden env exec php-fpm bin/magento config:set catalog/search/${CONFIG_PREFIX}_server_hostname $SEARCH_HOST || true
    warden env exec php-fpm bin/magento config:set catalog/search/${CONFIG_PREFIX}_server_port 9200 || true
    warden env exec php-fpm bin/magento config:set catalog/search/${CONFIG_PREFIX}_index_prefix magento2 || true
    warden env exec php-fpm bin/magento config:set catalog/search/${CONFIG_PREFIX}_enable_auth 0 || true
    warden env exec php-fpm bin/magento config:set catalog/search/${CONFIG_PREFIX}_server_timeout 15 || true
fi

if [[ "$WARDEN_REDIS" -eq "1" ]]; then
    :: Configuring Redis
    warden env exec php-fpm bin/magento setup:config:set --cache-backend=redis --cache-backend-redis-server=redis --cache-backend-redis-db=0 --cache-backend-redis-port=6379 --no-interaction || true
    warden env exec php-fpm bin/magento setup:config:set --page-cache=redis --page-cache-redis-server=redis --page-cache-redis-db=1 --page-cache-redis-port=6379 --no-interaction || true
    warden env exec php-fpm bin/magento setup:config:set --session-save=redis --session-save-redis-host=redis --session-save-redis-max-concurrency=20 --session-save-redis-db=2 --session-save-redis-port=6379 --no-interaction || true
fi

:: Update configuration
before_set_config

warden env exec -T db bash -c '$(command -v mariadb || echo mysql) -hdb -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" -e "UPDATE ${DB_PREFIX:-}core_config_data SET value = '\''https://${TRAEFIK_SUBDOMAIN}.${TRAEFIK_DOMAIN}/'\'' WHERE path IN ('\''web/secure/base_url'\'', '\''web/unsecure/base_url'\'', '\''web/secure/base_link_url'\'', '\''web/unsecure/base_link_url'\'')"' 2> >(grep -v 'Deprecated program name' >&2) || true
warden env exec -T db bash -c '$(command -v mariadb || echo mysql) -hdb -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" -e "DELETE FROM ${DB_PREFIX:-}core_config_data WHERE path IN ('\''web/secure/base_static_url'\'', '\''web/secure/base_media_url'\'', '\''web/unsecure/base_static_url'\'', '\''web/unsecure/base_media_url'\'')"' 2> >(grep -v 'Deprecated program name' >&2) || true

warden env exec php-fpm bin/magento config:set -q --lock-env web/unsecure/base_url "https://${TRAEFIK_SUBDOMAIN}.${TRAEFIK_DOMAIN}/" || true
warden env exec php-fpm bin/magento config:set -q --lock-env web/secure/base_url "https://${TRAEFIK_SUBDOMAIN}.${TRAEFIK_DOMAIN}/" || true

warden env exec php-fpm bin/magento config:set -q --lock-env web/seo/use_rewrites 1 || true
warden env exec php-fpm bin/magento config:set -q --lock-env web/secure/offloader_header X-Forwarded-Proto || true
warden env exec php-fpm bin/magento config:set -q --lock-env web/cookie/cookie_domain "${TRAEFIK_SUBDOMAIN}.${TRAEFIK_DOMAIN}" || true
warden env exec php-fpm bin/magento config:set -q --lock-env admin/url/use_custom 0 || true
warden env exec php-fpm bin/magento config:set -q --lock-env admin/security/password_is_forced 0 || true
warden env exec php-fpm bin/magento config:set -q --lock-env admin/security/admin_account_sharing 1 || true
warden env exec php-fpm bin/magento config:set -q --lock-env admin/security/session_lifetime 31536000 || true
warden env exec php-fpm bin/magento config:set -q --lock-env admin/security/use_form_key 0 || true
warden env exec php-fpm bin/magento config:set -q --lock-env admin/captcha/enable 0 || true
warden env exec php-fpm bin/magento config:set -q --lock-env google/analytics/active 0 || true
warden env exec php-fpm bin/magento config:set -q --lock-env google/adwords/active 0 || true
warden env exec php-fpm bin/magento config:set -q --lock-env recaptcha_frontend/type_recaptcha/public_key '' || true
warden env exec php-fpm bin/magento config:set -q --lock-env recaptcha_frontend/type_recaptcha/private_key '' || true
warden env exec php-fpm bin/magento config:set -q --lock-env recaptcha_frontend/type_invisible/public_key '' || true
warden env exec php-fpm bin/magento config:set -q --lock-env recaptcha_frontend/type_invisible/private_key '' || true
warden env exec php-fpm bin/magento config:set -q --lock-env recaptcha_frontend/type_recaptcha_v3/public_key '' || true
warden env exec php-fpm bin/magento config:set -q --lock-env recaptcha_frontend/type_recaptcha_v3/private_key '' || true
warden env exec php-fpm bin/magento config:set -q --lock-env payment/checkmo/active 1 || true
warden env exec php-fpm bin/magento config:set -q --lock-env payment/stripe_payments/active 0 || true
warden env exec php-fpm bin/magento config:set -q --lock-env payment/stripe_payments_basic/stripe_mode test || true
warden env exec php-fpm bin/magento config:set -q --lock-env paypal/wpp/sandbox_flag 1 || true
warden env exec php-fpm bin/magento config:set -q --lock-env msp_securitysuite_recaptcha/backend/enabled 0 || true
warden env exec php-fpm bin/magento config:set -q --lock-env msp_securitysuite_recaptcha/frontend/enabled 0 || true
warden env exec php-fpm bin/magento config:set -q --lock-env msp_securitysuite_twofactorauth/general/enabled 0 || true
warden env exec php-fpm bin/magento config:set -q --lock-env msp_securitysuite_twofactorauth/google/enabled 0 || true
warden env exec php-fpm bin/magento config:set -q --lock-env msp_securitysuite_twofactorauth/u2fkey/enabled 0 || true
warden env exec php-fpm bin/magento config:set -q --lock-env msp_securitysuite_twofactorauth/duo/enabled 0 || true
warden env exec php-fpm bin/magento config:set -q --lock-env msp_securitysuite_twofactorauth/authy/enabled 0 || true
warden env exec php-fpm bin/magento config:set -q --lock-env klaviyo_reclaim_general/general/enable 0 || true
warden env exec php-fpm bin/magento config:set -q --lock-env klaviyo_reclaim_webhook/klaviyo_webhooks/using_product_delete_before_webhook 0 || true

after_set_config

if [ ! -z ${WARDEN_PWA+x} ] && [[ "$WARDEN_PWA" -eq "1" ]]; then
    :: Configuring PWA theme
    if [ ! -d "${WARDEN_ENV_PATH}/${WARDEN_PWA_PATH}" ]; then
        git clone -b ${WARDEN_PWA_GIT_BRANCH} ${WARDEN_PWA_GIT_REMOTE} ${WARDEN_ENV_PATH}/${WARDEN_PWA_PATH}
    fi

    cat <<EOT > "${WARDEN_ENV_PATH}/${WARDEN_PWA_PATH}/.env"
MAGENTO_BACKEND_URL=https://${TRAEFIK_SUBDOMAIN}.${TRAEFIK_DOMAIN}/
MAGENTO_BACKEND_EDITION=CE
CHECKOUT_BRAINTREE_TOKEN=sandbox_8yrzsvtm_s2bg8fs563crhqzk
EOT

    node /usr/share/yarn/bin/yarn.js --cwd ${WARDEN_ENV_PATH}/${WARDEN_PWA_PATH} --ignore-optional || true
    node /usr/share/yarn/bin/yarn.js --cwd ${WARDEN_ENV_PATH}/${WARDEN_PWA_PATH} build || true

    warden env exec php-fpm bin/magento config:set web/upward/enabled 1 || true
    warden env exec php-fpm bin/magento config:set web/upward/path /var/www/html/${WARDEN_PWA_UPWARD_PATH} || true
fi

:: Flushing cache
warden env exec php-fpm bin/magento cache:flush || true

:: Reindex data
warden env exec php-fpm bin/magento indexer:reindex || true

:: Enable developer mode
warden env exec php-fpm bin/magento deploy:mode:set -s developer || true
