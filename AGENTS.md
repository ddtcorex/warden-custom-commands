# Warden Custom Commands - Agent Guidelines

Custom shell commands extending Warden for Magento 2, Laravel, Symfony, and WordPress.

## Project Overview

- **Language**: Bash (POSIX-compatible shell scripts)
- **Architecture**: Dispatcher pattern - root `*.cmd` delegate to `env-adapters/{type}/*.cmd`
- **File types**: `*.cmd` (commands), `*.help` (help text), `lib/*.sh` (utilities)

## Build and Test Commands

```bash
./tests/run-tests.sh                    # Run all tests (unit + integration)
./tests/run-tests.sh magento2           # Tests for specific env type
./tests/run-tests.sh magento2 --unit-only  # Skip integration tests

# Single test file or by name
npx -y bats tests/unit/core/ssh-utils.bats
npx -y bats tests/unit/core/ssh-utils.bats --filter "normalize_env_name"
```

**Test locations**: `tests/unit/core/` (core libs), `tests/unit/adapters/{type}/`, `tests/integration/`

## Code Style Guidelines

### Shebang and Guards

```bash
#!/usr/bin/env bash
set -euo pipefail  # Always enable strict mode

# Guard for sourced files
[[ ! "${WARDEN_DIR:-}" ]] && >&2 printf "\033[31mNot intended to run directly!\033[0m\n" && exit 1
```

### Naming Conventions

- **Exports/Constants**: `UPPER_SNAKE_CASE` (`SYNC_SOURCE`, `ENV_TYPE`)
- **Local variables**: `lower_snake_case` with `local` keyword
- **Functions**: `lower_snake_case` (`function get_remote_env()`)
- **Files**: `kebab-case` (`db-dump.cmd`, `ssh-utils.sh`)

### Functions and Variables

```bash
# Brief description | Usage: function_name "arg1" "arg2"
function function_name() {
    local arg1="$1"
    local arg2="${2:-default}"  # Always provide defaults for set -u
}

# Indirect references for dynamic variable names
local host_var="${prefix}_HOST"
[[ -n "${!host_var:-}" ]] && echo "${!host_var}"
```

### Error Handling (lib/error-handling.sh)

```bash
source "${SUBCOMMAND_DIR}/lib/error-handling.sh"

info "Processing..."        # Green message
warning "Potential issue"   # Yellow to stderr
error "Failed"              # Red to stderr
fatal "Cannot continue"     # Red + exit 1

run_required "Desc" cmd     # Exit on failure
run_optional "Desc" cmd     # Continue on failure
run_idempotent "Desc" cmd   # Handle "already exists"
```

### Argument Parsing

```bash
while (( "$#" )); do
    case "$1" in
        -f|--file)         SYNC_TYPE_FILE=1; shift ;;      # Boolean flag
        -o=*|--output=*)   OUTPUT="${1#*=}"; shift ;;      # Value with =
        -o|--output)       OUTPUT="$2"; shift 2 ;;         # Value next arg
        --)                shift; break ;;
        -*)                printf "Unknown: %s\n" "$1" >&2; exit 1 ;;
        *)                 WARDEN_PARAMS+=("$1"); shift ;;
    esac
done
```

### Warden Exec

```bash
warden env exec php-fpm composer install      # Interactive (TTY)
warden env exec -T php-fpm bin/magento c:f    # Non-interactive (-T for scripts/pipelines)
```

### Output

```bash
printf "\033[33m%s\033[0m\n" "Yellow text"     # Use printf, not echo
printf "\033[31mError: %s\033[0m\n" "$msg" >&2
:: "Section header"                            # From env-variables
```

## Testing (BATS)

```bash
#!/usr/bin/env bats
load "../../../libs/mocks.bash"

setup() { setup_mocks; export WARDEN_ENV_NAME="test-project"; }
teardown() { rm -rf "${TEST_TMP_DIR:?}"/*; }

@test "descriptive test name" {
    run some_function "arg1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"expected"* ]]
    grep -q "warden env exec" "$MOCK_LOG"
}
```

## Dispatcher Pattern

```bash
ENV_CMD="${SUBCOMMAND_DIR}/env-adapters/${WARDEN_ENV_TYPE}/bootstrap.cmd"
if [[ -f "${ENV_CMD}" ]]; then
    source "${ENV_CMD}"
else
    printf "\033[31mNot supported for '%s'\033[0m\n" "${WARDEN_ENV_TYPE}" >&2
    exit 1
fi
```

## Key Environment Variables

- `WARDEN_DIR` / `WARDEN_HOME_DIR` - Installation and user home (~/.warden)
- `WARDEN_ENV_PATH` / `WARDEN_ENV_NAME` / `WARDEN_ENV_TYPE` - Project context
- `ENV_SOURCE` - Remote environment (staging, prod, dev)
- `VERBOSE` - 0=quiet, 1=verbose, 2=debug (set -x)

## Common Patterns

### SSH Operations

```bash
source "${SUBCOMMAND_DIR}/lib/ssh-utils.sh"
SSH_OPTS=$(build_ssh_opts)
# SSH_OPTS unquoted intentionally - multiple options need word splitting
ssh ${SSH_OPTS} -p "${port}" "${user}@${host}" "command"
```

### Remote Environment Access

```bash
norm_env=$(normalize_env_name "${ENV_SOURCE}")
eval "$(get_remote_env "${norm_env}" "ENV_SOURCE")"
# Sets: ENV_SOURCE_HOST, ENV_SOURCE_USER, ENV_SOURCE_PORT, ENV_SOURCE_DIR
```

### Source Guard

```bash
[[ -n "${_MY_LIB_LOADED:-}" ]] && return 0
_MY_LIB_LOADED=1
```
