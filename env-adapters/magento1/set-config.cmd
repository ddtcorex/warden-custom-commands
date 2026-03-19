#!/usr/bin/env bash
set -euo pipefail

[[ ! "${WARDEN_DIR:-}" ]] && >&2 printf "\033[31mNot intended to run directly!\033[0m\n" && exit 1

START_TIME=$(date +%s)
_ADAPTER_DIR=$(dirname "${BASH_SOURCE[0]}")
source "${_ADAPTER_DIR}"/env-variables

# Update base_url via direct exec to avoid TTY/flag issues with warden db connect
function run_sql() {
    local query="$1"
    printf "%s" "${query}" | warden env exec -T db bash -c 'export MYSQL_PWD="$MYSQL_PASSWORD"; $(command -v mariadb || echo mysql) -u"$MYSQL_USER" "$MYSQL_DATABASE" -f'
}

:: Configuring Magento base URLs
run_sql "UPDATE ${DB_PREFIX}core_config_data SET value = 'https://${TRAEFIK_SUBDOMAIN}.${TRAEFIK_DOMAIN}/' WHERE path = 'web/secure/base_url'"
run_sql "UPDATE ${DB_PREFIX}core_config_data SET value = 'http://${TRAEFIK_SUBDOMAIN}.${TRAEFIK_DOMAIN}/' WHERE path = 'web/unsecure/base_url'"
run_sql "UPDATE ${DB_PREFIX}core_config_data SET value = '{{secure_base_url}}' WHERE path = 'web/unsecure/base_link_url'"
run_sql "UPDATE ${DB_PREFIX}core_config_data SET value = '{{secure_base_url}}skin/' WHERE path = 'web/unsecure/base_skin_url'"
run_sql "UPDATE ${DB_PREFIX}core_config_data SET value = '{{secure_base_url}}media/' WHERE path = 'web/unsecure/base_media_url'"
run_sql "UPDATE ${DB_PREFIX}core_config_data SET value = '{{secure_base_url}}js/' WHERE path = 'web/unsecure/base_js_url'"
run_sql "UPDATE ${DB_PREFIX}core_config_data SET value = '1' WHERE path = 'web/secure/use_in_frontend'"
run_sql "UPDATE ${DB_PREFIX}core_config_data SET value = '1' WHERE path = 'web/secure/use_in_adminhtml'"
run_sql "UPDATE ${DB_PREFIX}core_config_data SET value = NULL WHERE path = 'web/cookie/cookie_domain'"
run_sql "UPDATE ${DB_PREFIX}core_config_data SET value = '0' WHERE path = 'aminvisiblecaptcha/backend/enabled'"
run_sql "UPDATE ${DB_PREFIX}core_config_data SET value = '0' WHERE path = 'aminvisiblecaptcha/frontend/enabled'"

printf "\n✅ \033[32mConfiguration updated!\033[0m\n"
