#!/usr/bin/env bash
set -euo pipefail

[[ ! "${WARDEN_DIR:-}" ]] && >&2 printf "\033[31mNot intended to run directly!\033[0m\n" && exit 1

if [[ "${ENV_SOURCE_DEFAULT:-0}" -eq "1" ]] || [[ "${ENV_SOURCE:-local}" == "local" ]]; then
    EXEC_PREFIX="warden env exec -T php-fpm"
else
    EXEC_PREFIX="warden remote-exec -e ${ENV_SOURCE} --"
fi

printf "\n"
printf "⌛ \033[1;32mEnabling maintenance mode...\033[0m\n"
${EXEC_PREFIX} touch maintenance.flag || true

printf "\n"
printf "⌛ \033[1;32mInstalling dependencies...\033[0m\n"
if ${EXEC_PREFIX} test -f composer.json; then
    ${EXEC_PREFIX} composer install --no-dev --no-interaction
fi

printf "\n"
printf "⌛ \033[1;32mDisabling compiler...\033[0m\n"
if ${EXEC_PREFIX} test -f shell/compiler.php; then
    ${EXEC_PREFIX} php shell/compiler.php disable || true
    ${EXEC_PREFIX} php shell/compiler.php clear || true
fi

printf "\n"
printf "⌛ \033[1;32mRunning database upgrades...\033[0m\n"
if ${EXEC_PREFIX} command -v n98-magerun &>/dev/null; then
    ${EXEC_PREFIX} n98-magerun sys:setup:run || true
fi

printf "\n"
printf "⌛ \033[1;32mCompiling...\033[0m\n"
if ${EXEC_PREFIX} test -f shell/compiler.php; then
    ${EXEC_PREFIX} php shell/compiler.php compile || true
fi

printf "\n"
printf "⌛ \033[1;32mFlushing cache...\033[0m\n"
${EXEC_PREFIX} bash -c "rm -rf var/cache/* var/session/* var/full_page_cache/* media/css/* media/js/*" || true

printf "\n"
printf "⌛ \033[1;32mDisabling maintenance mode...\033[0m\n"
${EXEC_PREFIX} rm -f maintenance.flag || true

printf "\n✅ \033[32mMagento 1 full deploy complete!\033[0m\n"
