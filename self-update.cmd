#!/usr/bin/env bash
set -euo pipefail
[[ ! "${WARDEN_DIR:-}" ]] && >&2 printf "\033[31mThis script is not intended to be run directly!\033[0m\n" && exit 1

SUBCOMMAND_DIR=$(dirname "${BASH_SOURCE[0]}")

# Source error handling utilities
source "${SUBCOMMAND_DIR}/lib/error-handling.sh"

function main() {
    info "Starting Warden self-update process..."

    # 1. Safety Checks
    check_dirty_state "${WARDEN_DIR}" "Warden"
    check_dirty_state "${WARDEN_HOME_DIR}/commands" "Custom Commands"

    # 2. Update Warden Core
    update_repo "${WARDEN_DIR}" "Warden"
    
    # 3. Update Custom Commands (this repo)
    # We do this before patching to ensure we have the latest patch files.
    # Note: Since this script is running from memory (bash function), updating the file on disk 
    # shouldn't crash the running process, but it relies on bash buffering the function.
    update_repo "${WARDEN_HOME_DIR}/commands" "Custom Commands"
    
    # 4. Service Update
    info "Pulling latest service images..."
    if ! warden svc pull; then
        warning "Failed to pull some images. Continuing..."
    fi
    
    info "Restarting services..."
    warden svc up --remove-orphans

    # 5. Apply Patches
    # Now that custom commands are updated, we apply the patch from the updated file
    apply_patches

    info "Self-update completed successfully!"
}

function check_dirty_state() {
    local dir="$1"
    local name="$2"
    
    if [[ ! -d "${dir}" ]]; then
        return 0
    fi

    if [[ -n $(git -C "${dir}" status --porcelain) ]]; then
        fatal "${name} repository has local changes. Aborting update to prevent data loss. Please stash or commit your changes."
    fi
}

function update_repo() {
    local dir="$1"
    local name="$2"
    
    if [[ ! -d "${dir}" ]]; then
        warning "Directory ${dir} does not exist. Skipping update for ${name}."
        return
    fi

    info "Updating ${name}..."
    local branch
    branch=$(git -C "${dir}" rev-parse --abbrev-ref HEAD)
    
    info "  Fetching origin for branch '${branch}'..."
    git -C "${dir}" fetch origin
    
    info "  Resetting hard to origin/${branch}..."
    git -C "${dir}" reset --hard "origin/${branch}"
    
    info "  Cleaning untracked files..."
    git -C "${dir}" clean -fd
}

function apply_patches() {
    local patch_file="${WARDEN_HOME_DIR}/commands/patches/warden-fix-file-permissions.patch"
    local target_file="${WARDEN_DIR}/commands/env.cmd"
    
    if [[ ! -f "${patch_file}" ]]; then
        warning "Patch file not found: ${patch_file}"
        return
    fi
    
    info "Applying patches..."
    
    # Check if patch is applicable (dry run forward)
    # -N: Ignore patches that seem to be reversed (already applied)
    # -s: Silent
    if patch -N -s --dry-run "${target_file}" < "${patch_file}" &>/dev/null; then
        if patch -N -s "${target_file}" < "${patch_file}"; then
            info "  Successfully patched env.cmd"
        else
            warning "  Failed to apply patch to env.cmd"
        fi
    else
        # If dry-run fails, check if it's because it's already applied
        # We simulate a reversal dry-run. If that succeeds, the patch is applied.
        if patch -R -s --dry-run "${target_file}" < "${patch_file}" &>/dev/null; then
            info "  Patch already applied (skipping)"
        else
            warning "  Patch not applicable (possibly conflicting or file changed)"
        fi
    fi
}

# Execute main
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
