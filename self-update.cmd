#!/usr/bin/env bash
set -euo pipefail
[[ ! "${WARDEN_DIR:-}" ]] && >&2 printf "\033[31mThis script is not intended to be run directly!\033[0m\n" && exit 1

SUBCOMMAND_DIR=$(dirname "${BASH_SOURCE[0]}")

# Source error handling utilities
source "${SUBCOMMAND_DIR}/lib/error-handling.sh"

FORCE=0
DRY_RUN=0

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -f|--force) FORCE=1 ;;
        --dry-run) DRY_RUN=1 ;;
        *) error "Unknown option: $1" ;;
    esac
    shift
done

function update_git_repo() {
    local dir="$1"
    local name="$2"

    if [[ ! -d "${dir}/.git" ]]; then
        warning "Directory '${dir}' is not a git repository. Skipping update for ${name}."
        return
    fi

    # Detect current branch
    local branch
    branch=$(git -C "${dir}" branch --show-current 2>/dev/null || echo "")
    if [[ -z "${branch}" ]]; then
        # Detached HEAD? Try to infer or fallback
        branch=$(git -C "${dir}" rev-parse --abbrev-ref HEAD)
    fi

    if [[ "${branch}" == "HEAD" ]]; then
        warning "${name} is in detached HEAD state. Skipping update."
        return
    fi

    info "Converting ${name} on branch '${branch}'..."

    # Check for uncommitted changes
    if [[ -n $(git -C "${dir}" status --porcelain) ]]; then
        if [[ "${FORCE}" -eq 1 ]]; then
            warning "Force enabled: Overwriting uncommitted changes in ${name}."
        else
            error "Uncommitted changes detected in ${name} (${dir}). Aborting. Use --force to discard changes and update."
            return 1
        fi
    fi

    if [[ "${DRY_RUN}" -eq 1 ]]; then
        info "[Dry Run] Would fetch origin and reset ${branch} to origin/${branch}"
        info "[Dry Run] Would clean directory"
    else
        git -C "${dir}" fetch origin
        git -C "${dir}" reset --hard "origin/${branch}"
        git -C "${dir}" clean -fd
        success "Updated ${name} successfully."
    fi
}

# 1. Update Warden Core
if [[ -d "${WARDEN_DIR}" ]]; then
    update_git_repo "${WARDEN_DIR}" "Warden Core" || exit 1
    
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        info "[Dry Run] Would run: warden svc pull && warden svc up --remove-orphans"
    else
        warden svc pull
        warden svc up --remove-orphans
    fi
else
    warning "WARDEN_DIR '${WARDEN_DIR}' not found."
fi

# 2. Update Custom Commands (this repository)
# Usually WARDEN_HOME_DIR/commands maps to this repo
COMMANDS_DIR="${WARDEN_HOME_DIR}/commands"
if [[ -d "${COMMANDS_DIR}" ]]; then
    update_git_repo "${COMMANDS_DIR}" "Custom Commands" || exit 1
else
    warning "Commands directory '${COMMANDS_DIR}' not found."
fi

# 3. Apply Patches
PATCH_FILE="${COMMANDS_DIR}/patches/warden-fix-file-permissions.patch"
TARGET_FILE="${WARDEN_DIR}/commands/env.cmd"

if [[ -f "${PATCH_FILE}" ]] && [[ -f "${TARGET_FILE}" ]]; then
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        info "[Dry Run] Would apply patch: ${PATCH_FILE}"
    else
        # Apply patch if not already applied
        if ! patch -N "${TARGET_FILE}" < "${PATCH_FILE}" 2>/dev/null; then
             # patch exits with 1 if forwarded patch fails (already applied often implies rejection or fail in some patch versions)
             # But -N is supposed to ignore patches already applied? 
             # Actually, if it's already applied, it might fail to apply again.
             # We assume failure means "already applied" or "not applicable", logging as info.
             info "Patch for ${TARGET_FILE} already applied or not needed."
        else
             success "Applied patch to ${TARGET_FILE}."
        fi
    fi
fi
