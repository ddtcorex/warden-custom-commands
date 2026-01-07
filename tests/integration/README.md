# Warden Custom Commands - Integration Tests

This directory contains the integration testing suite for Warden custom commands, specifically focusing on the `warden sync` functionality.

## Overview

The test suite simulates a real-world multi-environment setup using Docker containers:

- **project-local**: Your simulated local development environment.
- **project-dev**: A simulated remote development server.
- **project-staging**: A simulated staging server.

The tests verify:

- **Bootstrap Command Logic (Unit tests)**
- File synchronization (Upload/Download)
- Media synchronization
- Database synchronization (streaming)
- Remote-to-Remote synchronization
- Custom path excludes and includes
- Error handling

## Prerequisites

- **Warden** installed and configured.
- **Docker** and **docker-compose** version 2+.
- SSH keys generated locally (`~/.ssh/id_rsa.pub` must exist).

## Setup

Before running tests, you must initialize the test environments for a specific framework type.

```bash
# Setup for Laravel
./tests/integration/setup-test-envs.sh --type=laravel

# Setup for Magento 2
./tests/integration/setup-test-envs.sh --type=magento2

# Setup for Symfony
./tests/integration/setup-test-envs.sh --type=symfony
```

The setup script will:

1. Create temporary directories in `tests/project-*`.
2. Initialize and start Warden environments.
3. Configure SSH servers and distribute keys between containers.
4. Establish Docker network connectivity between environments.

## Running Tests

Once setup is complete, run the main test entry point.
**Note**: This command now automatically runs the relevant Unit Tests (BATS) before starting the integration suite.

```bash
# Run ALL tests (Unit + Integration) for the current initialized type
./tests/integration/run-tests.sh --type=laravel
```

## Cleanup

To stop and remove all test environments:

```bash
./tests/integration/teardown-test-envs.sh

# To completely remove data volumes and directories:
rm -rf tests/project-*
docker volume rm $(docker volume ls -q | grep project-)
```

## Structure

- `setup-test-envs.sh`: Orchestrates container initialization and networking.
- `run-tests.sh`: Main test runner that sources individual test suites.
- `helpers.sh`: Shared functions for file creation, DB queries, and assertions.
- `test-*.sh`: Individual test suites for specific features.

## Development Tip

If you are modifying the sync command, ensure your repository is symlinked to `~/.warden/commands` so the tests use your latest changes:

```bash
ln -s $(pwd) ~/.warden/commands
```
