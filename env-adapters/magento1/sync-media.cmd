#!/usr/bin/env bash
set -euo pipefail

[[ ! "${WARDEN_DIR:-}" ]] && >&2 printf "\033[31mNot intended to run directly!\033[0m\n" && exit 1

_ADAPTER_DIR=$(dirname "${BASH_SOURCE[0]}")

# Export sync type to media and delegate to env-sync.cmd
export SYNC_TYPE_MEDIA=1
export SYNC_TYPE_FULL=0

# Ensure we pass all arguments to env-sync.cmd
source "${_ADAPTER_DIR}/env-sync.cmd" "$@"
