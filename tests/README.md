# Warden Custom Commands Testing Suite

This repository contains two levels of testing to ensure the reliability of custom Warden commands:

1. **Unit/Behavioral Tests (BATS)**: Fast tests for checking script logic, argument parsing, and fail-safes without requiring a full container environment.
2. **Integration Tests**: Full end-to-end tests running against actual Docker containers to verify synchronization, database operations, and file consistency.

## 🚀 Quick Start

To run the complete test suite (Unit + Integration) for a specific environment type:

```bash
# Run all tests for Magento 2
./tests/run-tests.sh magento2

# Run all tests for Laravel
./tests/run-tests.sh laravel

# Run only unit tests (skip integration)
./tests/run-tests.sh magento2 --unit-only
```

## 🧪 Unit Tests (BATS)

Located in `tests/adapters/<framework>/`.

These tests use the [Bash Automated Testing System](https://github.com/bats-core/bats-core) to verify command scripts. They mock the `warden` and `docker` commands to ensure that the logic constructs the correct commands and handles flags properly.

### Running Unit Tests Individually

You can run BATS tests directly if you have `bats` installed or via `npx`:

```bash
# Run all unit tests for a framework
npx -y bats tests/adapters/magento2/*.bats

# Run specific test file
npx -y bats tests/adapters/magento2/bootstrap.bats
```

### Mocks

Shared mocks are located in `tests/libs/mocks.bash`. These are used to simulate:

* Warden commands (`env up`, `svc up`)
* Docker exec calls
* File system checks (where possible)

## 🔄 Integration Tests

Located in `tests/integration/`.

The test suite simulates a real-world multi-environment setup using Docker containers. Environments are named based on the framework type:

* **{type}-local**: Your simulated local development environment (e.g., `magento2-local`)
* **{type}-dev**: A simulated remote development server (e.g., `magento2-dev`)
* **{type}-staging**: A simulated staging server (e.g., `magento2-staging`)

The tests verify:

* **Bootstrap Command Logic (Unit tests)**
* File synchronization (Upload/Download)
* Media synchronization
* Database synchronization (streaming)
* Remote-to-Remote synchronization
* Custom path excludes and includes
* Error handling

### Prerequisites

* **Warden** installed and configured.
* **Docker** and **docker-compose** version 2+.
* SSH keys generated locally (`~/.ssh/id_rsa.pub` must exist).

### Setup

Before running tests, you must initialize the test environments for a specific framework type.

```bash
# Setup for Magento 2
./tests/integration/setup-test-envs.sh --type=magento2

# Setup for Laravel
./tests/integration/setup-test-envs.sh --type=laravel

# Setup for Symfony
./tests/integration/setup-test-envs.sh --type=symfony

# Setup for WordPress
./tests/integration/setup-test-envs.sh --type=wordpress
```

The setup script will:

1. Create directories in `tests/{type}-local`, `tests/{type}-dev`, `tests/{type}-staging`.
2. Initialize and start Warden environments.
3. Configure SSH servers and distribute keys between containers.
4. Establish Docker network connectivity between environments.

### Running Tests

After setup, run the tests:

```bash
# Run integration tests
./tests/integration/run-tests.sh --type=magento2

# Or use the unified runner (includes unit tests)
./tests/run-tests.sh magento2
```

### Cleanup

To stop and remove all test environments:

```bash
./tests/integration/teardown-test-envs.sh

# To completely remove data volumes and directories:
rm -rf tests/*-local tests/*-dev tests/*-staging
docker volume rm $(docker volume ls -q | grep -E "(magento2|laravel|symfony|wordpress)-(local|dev|staging)")
```

### Structure

* `setup-test-envs.sh`: Orchestrates container initialization and networking.
* `run-tests.sh`: Main test runner that sources individual test suites.
* `helpers.sh`: Shared functions for file creation, DB queries, and assertions.
  * `configure_test_envs(type)`: Sets up dynamic container/path variables.
* `suites/*.sh`: Individual test suites for specific features.

## 💡 Development Tip

If you are modifying the sync command, ensure your repository is symlinked to `~/.warden/commands` so the tests use your latest changes:

```bash
ln -s $(pwd) ~/.warden/commands
```
