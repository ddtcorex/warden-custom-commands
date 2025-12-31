# Integration Tests for Warden Sync Command

This directory contains integration tests for the `warden sync` command to ensure reliability across all supported scenarios.

## Quick Start

```bash
# Set up test environments (one-time)
./tests/integration/setup-test-envs.sh

# Run tests
./tests/integration/run-tests.sh

# Tear down when done
./tests/integration/teardown-test-envs.sh
```

## Prerequisites

### Automated Setup (Recommended)

The setup script handles everything automatically:

```bash
./tests/integration/setup-test-envs.sh
```

This script will:

1. Create `tests/project-local`, `tests/project-dev`, `tests/project-staging` directories
2. Initialize Warden environments with `warden env-init`
3. Configure `REMOTE_*` variables in `.env` files
4. Start all environments with `warden env up -d`
5. Install SSH server in dev/staging containers
6. Generate SSH keys and distribute to remotes
7. Connect Docker networks for cross-container communication
8. Configure sshd and verify connectivity

## Running Tests

### Run All Tests

```bash
./tests/integration/run-tests.sh
```

### Run Individual Test Suite

```bash
source tests/integration/helpers.sh
source tests/integration/test-file-sync.sh
```

## Test Suites

### test-file-sync.sh

Tests file synchronization functionality:

- **Dry run** - Verify `--dry-run` doesn't transfer files
- **Upload** - Verify files transfer from local to dev
- **Download** - Verify files transfer from dev to local
- **Exclusions** - Verify `/generated`, `/var`, etc. are excluded

### test-media-sync.sh

Tests media synchronization:

- **Structure** - Verify directory structure preserved in `pub/media/`
- **Product exclusion** - Verify `catalog/product` excluded by default
- **Include product** - Verify `--include-product` flag works
- **Tmp exclusion** - Verify `tmp/` directory excluded

### test-custom-path.sh

Tests custom path synchronization (`-p` flag):

- **Specific directory** - Verify only specified path syncs
- **Trailing slash** - Verify paths with trailing slashes are normalized
- **Download** - Verify custom path download works

### test-error-handling.sh

Tests error conditions:

- **Same source/destination** - Verify error when `-s dev -d dev`
- **Invalid environment** - Verify error for unknown environments
- **Default sync type** - Verify defaults to file sync when no type specified

## Helper Functions

Located in `helpers.sh`:

| Function | Description |
|----------|-------------|
| `pass "message"` | Log a passing test |
| `fail "test" "reason"` | Log a failing test |
| `skip "message"` | Log a skipped test |
| `header "title"` | Print section header |
| `summary` | Print test summary and exit code |
| `create_test_file container path content` | Create file in container |
| `file_exists container path` | Check if file exists |
| `get_file_content container path` | Read file content |
| `remove_file container path` | Delete file from container |
| `cleanup_test_files` | Remove all test artifacts |
| `check_environments` | Verify all containers running |
| `run_sync args...` | Execute warden sync in local env |
| `run_sync_confirmed args...` | Execute sync with auto-confirm |

## Environment Variables

| Variable | Description |
|----------|-------------|
| `TEST_DIR` | Path to `tests/` directory |
| `PROJECT_ROOT` | Path to project root |
| `LOCAL_ENV` | Path to project-local |
| `DEV_ENV` | Path to project-dev |
| `STAGING_ENV` | Path to project-staging |
| `LOCAL_PHP` | Container name for local php-fpm |
| `DEV_PHP` | Container name for dev php-fpm |
| `STAGING_PHP` | Container name for staging php-fpm |

## Test Output Example

```
╔════════════════════════════════════════════════════════════╗
║     Warden Sync Integration Tests                          ║
╚════════════════════════════════════════════════════════════╝

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
File Sync Tests
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✓ PASS: Dry run file sync - no files transferred
✓ PASS: File upload sync - file transferred with correct content
✓ PASS: File download sync - file received
✓ PASS: File sync exclusions - /generated excluded correctly

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
TEST SUMMARY
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Passed: 12
Failed: 0

All tests passed!
```

## Adding New Tests

1. Create a new test file: `test-{feature}.sh`
2. Source helpers: `source "${SCRIPT_DIR}/helpers.sh"` (already sourced by runner)
3. Use `header "Test Suite Name"` to start
4. Implement test functions using `pass`/`fail`
5. Add cleanup at the end
6. Register in `run-tests.sh`:

```bash
TEST_SUITES=(
    ...
    "test-{feature}.sh"
)
```

## Troubleshooting

### "Container not running" error

Start all test environments:

```bash
cd tests/project-local && warden env up -d
cd tests/project-dev && warden env up -d
cd tests/project-staging && warden env up -d
```

### SSH connection failures

Ensure networks are connected and SSH is running:

```bash
docker network connect project-dev_default project-local-php-fpm-1
docker exec project-dev-php-fpm-1 sudo /usr/sbin/sshd
```

### Tests hang during sync

Check that the `.env` files in test projects have `REMOTE_*` variables configured correctly for the test topology.
