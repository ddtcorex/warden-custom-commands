# Warden Custom Commands Testing Suite

This repository contains two levels of testing to ensure the reliability of custom Warden commands:

1. **Unit/Behavioral Tests (BATS)**: Fast tests for checking script logic, argument parsing, and fail-safes without requiring a full container environment.
2. **Integration Tests**: Full end-to-end tests running against actual Docker containers to verify synchronization, database operations, and file consistency.

## 🚀 Quick Start

To run the complete test suite (Unit + Integration) for a specific environment type:

```bash
# Example: Test Laravel commands
./tests/integration/run-tests.sh --type=laravel

# Example: Test Magento 2 commands
./tests/integration/run-tests.sh --type=magento2
```

## 🧪 Unit Tests (BATS)

Located in `tests/adapters/<framework>/bootstrap.bats`.

These tests use the [Bash Automated Testing System](https://github.com/bats-core/bats-core) to verify the `bootstrap.cmd` scripts. They mock the `warden` and `docker` commands to ensure that the logic constructs the correct commands and handles flags properly.

### Running Unit Tests Individually

You can run BATS tests directly if you have `bats` installed or via `npx`:

```bash
# Run all unit tests
npx -y bats tests/adapters/*/bootstrap.bats

# Run specific framework tests
npx -y bats tests/adapters/magento2/bootstrap.bats
```

### Mocks

Shared mocks are located in `tests/libs/mocks.bash`. These are used to simulate:

* Warden commands (`env up`, `svc up`)
* Docker exec calls
* File system checks (where possible)

## 🔄 Integration Tests

Located in `tests/integration/`.

These tests provision real Docker environments (`project-local`, `project-dev`, `project-staging`) to test the actual data transfer and command execution results.

### Setup

Before running integration tests for the first time or when switching types:

```bash
./tests/integration/setup-test-envs.sh --type=<magento2|laravel|symfony|wordpress>
```

### Details

For more detailed information on the integration test architecture, see [tests/integration/README.md](tests/integration/README.md).
