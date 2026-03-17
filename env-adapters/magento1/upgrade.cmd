#!/usr/bin/env bash
set -euo pipefail

[[ ! "${WARDEN_DIR:-}" ]] && >&2 printf "\033[31mNot intended to run directly!\033[0m\n" && exit 1

# Variable checks and execution context setup
if [[ "${ENV_SOURCE_DEFAULT:-0}" -eq "1" ]] || [[ "${ENV_SOURCE:-local}" == "local" ]]; then
    EXEC_PREFIX="warden env exec -T php-fpm"
else
    EXEC_PREFIX="warden remote-exec -e ${ENV_SOURCE} --"
fi

## Magento 1 Upgrade Command
printf "\n"
printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
printf "Magento 1 Upgrade\n"
printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
printf "\n"

printf "Step 1/3: Installing composer dependencies (if composer.json exists)...\n"
if ${EXEC_PREFIX} test -f composer.json; then
    ${EXEC_PREFIX} composer install
fi

printf "Step 2/3: Clearing compiler cache (if exists)...\n"
if ${EXEC_PREFIX} test -f shell/compiler.php; then
    ${EXEC_PREFIX} php shell/compiler.php clear || true
fi

printf "Step 3/3: Flushing cache...\n"
${EXEC_PREFIX} bash -c "rm -rf var/cache/* var/session/* var/full_page_cache/* media/css/* media/js/*" || true

# If n98-magerun is available, run sys:setup:run
if ${EXEC_PREFIX} command -v n98-magerun &>/dev/null; then
    printf "Running database upgrades via n98-magerun...\n"
    ${EXEC_PREFIX} n98-magerun sys:setup:run
fi

printf "\n✅ \033[32mMagento 1 upgrade completed!\033[0m\n"
