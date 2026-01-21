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

PATCH_FILE="${SUBCOMMAND_DIR}/patches/warden-fix-file-permissions.patch"
PATCH_TARGET_FILES=""
if [[ -f "${PATCH_FILE}" ]]; then
    # Extract list of files modified by the patch (ignoring /dev/null for new files if any, but simplistic grep works for modified)
    PATCH_TARGET_FILES=$(grep "^+++ b/" "${PATCH_FILE}" | sed 's|^+++ b/||' | tr '\n' ' ')
fi

function update_git_repo() {
    local dir="$1"
    local name="$2"
    local allowed_dirty_files="${3:-}"

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
    local dirty_status
    dirty_status=$(git -C "${dir}" status --porcelain)
    
    if [[ -n "${dirty_status}" ]]; then
        local unexpected_changes=0
        
        # Check each dirty file
        while IFS= read -r line; do
            # Extract path (skip status columns)
            local path="${line:3}"
            path="${path%\"}" # Remove trailing quote
            path="${path#\"}" # Remove leading quote
            
            local is_allowed=0
            if [[ -n "${allowed_dirty_files}" ]]; then
                for allowed in ${allowed_dirty_files}; do
                    if [[ "${path}" == "${allowed}" ]]; then
                        is_allowed=1
                        break
                    fi
                done
            fi
            
            if [[ "${is_allowed}" -eq 0 ]]; then
                unexpected_changes=1
            fi
        done <<< "${dirty_status}"
        
        if [[ "${unexpected_changes}" -eq 0 ]]; then
             warning "Detected uncommitted changes in allowed files (likely patches). Proceeding with reset/update."
        elif [[ "${FORCE}" -eq 1 ]]; then
            warning "Force enabled: Overwriting uncommitted changes in ${name}."
        else
            error "Uncommitted changes detected in ${name} (${dir})."
            echo "${dirty_status}" | sed 's/^/  /' >&2
            
            read -p "Do you want to discard these changes and force update? [y/N] " response
            if [[ "$response" =~ ^[yY]$ ]]; then
                warning "Force enabled: Overwriting uncommitted changes in ${name}."
                # FORCE=1 is local to this scope? FORCE is global.
                FORCE=1
            else
                error "Aborting update for ${name}."
                return 1
            fi
        fi
    fi

    if [[ "${DRY_RUN}" -eq 1 ]]; then
        info "[Dry Run] Would fetch origin and reset ${branch} to origin/${branch}"
        info "[Dry Run] Would clean directory"
    else
        git -C "${dir}" fetch origin
        git -C "${dir}" reset --hard "origin/${branch}"
        git -C "${dir}" clean -fd
        info "Updated ${name} successfully."
    fi
}

# 1. Update Warden Core
if [[ -d "${WARDEN_DIR}" ]]; then
    update_git_repo "${WARDEN_DIR}" "Warden Core" "${PATCH_TARGET_FILES}" || exit 1
    
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
COMMANDS_DIR="${WARDEN_HOME_DIR}/commands"
if [[ -d "${COMMANDS_DIR}" ]]; then
    update_git_repo "${COMMANDS_DIR}" "Custom Commands" || exit 1
else
    warning "Commands directory '${COMMANDS_DIR}' not found."
fi

# 3. Apply Patches
if [[ -f "${PATCH_FILE}" ]]; then
    # Target file is relative to WARDEN_DIR in the patch?
    # Actually patch file paths are relative to where patch is run.
    # The patch file header says "diff --git a/commands/env.cmd".
    # WARDEN_DIR contains "commands" dir?
    # Yes, lines 24 of original script: `patch -N "${WARDEN_DIR}/commands/env.cmd" ...`
    # Our generic logic below logic iterates targets?
    
    # We just apply the patch file as a whole to WARDEN_DIR?
    # Previous logic applied it to a specific file.
    
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        info "[Dry Run] Would apply patch: ${PATCH_FILE}"
    else
        # Try to apply patch to WARDEN_DIR
        # Use -d to set working dir for patch
        # Use -p1 to strip a/ b/ prefixes
        if ! patch -d "${WARDEN_DIR}" -p1 -N -r - < "${PATCH_FILE}" >/dev/null 2>&1; then
             info "Patch for ${PATCH_FILE} already applied or not needed."
        else
             info "Applied patch: ${PATCH_FILE}"
        fi
    fi
fi
