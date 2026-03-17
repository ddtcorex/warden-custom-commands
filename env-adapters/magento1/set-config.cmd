#!/usr/bin/env bash
set -euo pipefail

[[ ! "${WARDEN_DIR:-}" ]] && >&2 printf "\033[31mNot intended to run directly!\033[0m\n" && exit 1

START_TIME=$(date +%s)
_ADAPTER_DIR=$(dirname "${BASH_SOURCE[0]}")
source "${_ADAPTER_DIR}"/env-variables

# Update base_url
warden db connect -e "UPDATE ${DB_PREFIX}core_config_data SET value = 'https://${TRAEFIK_SUBDOMAIN}.${TRAEFIK_DOMAIN}/' WHERE path = 'web/secure/base_url'" || true
warden db connect -e "UPDATE ${DB_PREFIX}core_config_data SET value = 'http://${TRAEFIK_SUBDOMAIN}.${TRAEFIK_DOMAIN}/' WHERE path = 'web/unsecure/base_url'" || true
warden db connect -e "UPDATE ${DB_PREFIX}core_config_data SET value = '{{secure_base_url}}' WHERE path = 'web/unsecure/base_link_url'" || true
warden db connect -e "UPDATE ${DB_PREFIX}core_config_data SET value = '{{secure_base_url}}skin/' WHERE path = 'web/unsecure/base_skin_url'" || true
warden db connect -e "UPDATE ${DB_PREFIX}core_config_data SET value = '{{secure_base_url}}media/' WHERE path = 'web/unsecure/base_media_url'" || true
warden db connect -e "UPDATE ${DB_PREFIX}core_config_data SET value = '{{secure_base_url}}js/' WHERE path = 'web/unsecure/base_js_url'" || true
warden db connect -e "UPDATE ${DB_PREFIX}core_config_data SET value = '1' WHERE path = 'web/secure/use_in_frontend'" || true
warden db connect -e "UPDATE ${DB_PREFIX}core_config_data SET value = '1' WHERE path = 'web/secure/use_in_adminhtml'" || true

