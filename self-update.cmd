#!/usr/bin/env bash
set -u
[[ ! "${WARDEN_DIR:-}" ]] && >&2 printf "\033[31mThis script is not intended to be run directly!\033[0m\n" && exit 1

## Upgrade Warden to the latest version
git -C ${WARDEN_DIR} fetch origin
git -C ${WARDEN_DIR} reset --hard origin/main
git -C ${WARDEN_DIR} clean -fd
warden svc pull
warden svc up --remove-orphans

## Revert local changes and pull the latest updates from remote repository
git -C ${WARDEN_HOME_DIR}/commands fetch origin
git -C ${WARDEN_HOME_DIR}/commands reset --hard origin/master
git -C ${WARDEN_HOME_DIR}/commands clean -fd

## Apply patches for Warden
patch -N ${WARDEN_DIR}/commands/env.cmd < ${WARDEN_HOME_DIR}/commands/patches/warden-fix-file-permissions.patch || true
