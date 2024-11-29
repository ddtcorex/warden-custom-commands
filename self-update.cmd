#!/usr/bin/env bash
[[ ! ${WARDEN_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

## Upgrade Warden to the latest version
git -C ${WARDEN_DIR} fetch origin
git -C ${WARDEN_DIR} reset --hard origin/main
git -C ${WARDEN_DIR} clean -fd
warden svc up -d --remove-orphans

## Revert local changes and pull the latest updates from remote repository
git -C ~/.warden/commands fetch origin
git -C ~/.warden/commands reset --hard origin/master
git -C ~/.warden/commands clean -fd

## Apply patches for Warden
patch -N ${WARDEN_DIR}/commands/env.cmd < ~/.warden/commands/patches/warden-fix-file-permissions.patch || true
