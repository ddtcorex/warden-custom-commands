# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.5.1] - 2026-01-30

**v2.5.1: Bootstrap Path Correction**

This release fixes a path detection issue in the Magento 2 bootstrap process when performing clean installations.

### 🐛 Bug Fixes

- **Fixed `composer.json` path check:**
  - Corrected the check to use `WARDEN_ENV_PATH` instead of `WARDEN_WEB_ROOT` during `warden bootstrap --fresh`.
  - Ensures reliable detection of existing installations and prevents accidental overwrites or missing file errors.

## [2.5.0] - 2026-01-23

**v2.5.0: Help System Standardization & UX Improvements**

This release brings a major overhaul to the documentation and help system, ensuring a consistent user experience across all supported frameworks.

### 🛠 Improvements

- **Standardized Help System:**
  - Refactored all subcommand help files to use a unified `WARDEN_USAGE` variable pattern.
  - Improved help sourcing logic to prevent direct output during internal sourcing, allowing for cleaner integration.
- **Enhanced Documentation:**
  - Added comprehensive **Examples** sections to almost every command help file.
  - Standardized usage descriptions and option formatting across Magento 2, Laravel, Symfony, and WordPress adapters.
  - Significant updates to the root `README.md` for better clarity and consistent framework documentation.
- **Command specific updates:**
  - Improved help content for `remote-exec`, `self-update`, `setup-remotes`, `sync`, and `upgrade`.
  - Added descriptive examples for framework-specific commands (e.g., `warden upgrade -v=6.5` for WordPress).

## [2.4.2] - 2026-01-22

**v2.4.2: Database Dump Ignored Tables Expansion**

This release significantly expands the list of ignored tables in Magento 2 database dumps, covering more third-party extensions and improving dump efficiency.

### 🛠 Improvements

- **Expanded `db-dump` ignored tables list:**
  - Added Mview changelog tables (`*_cl`) for MSI and catalog indexers.
  - Added Smile ElasticSuite tracker tables.
  - Added Mailchimp sync and error tables.
  - Added Klaviyo sync queue table.
  - Added Mirasvit cache warmer, search, and SEO tables.
  - Added Yotpo sync tables.
  - Added Amasty Most Viewed index tables.
  - Added Sutunam activity tables.
  - Added miscellaneous transient tables (OAuth, password reset, import history).
  - Sorted all tables alphabetically for easier maintenance.
  - Removed legacy/unused tables (`core_cache`, `search_query`, `catalogsearch_recommendations`).
  - Total ignored tables increased from ~88 to ~113.

## [2.4.1] - 2026-01-21

**v2.4.1: SSH Authentication Fix & Self-Update UX**

This release fixes a critical SSH authentication issue in file synchronization and improves the user experience of the self-update command.

### 🐛 Bug Fixes

- **Fixed rsync SSH authentication failures:**
  - Changed `rsync` execution context from inside the `php-fpm` container to the host machine in `sync.cmd`.
  - Ensures proper utilization of host SSH keys during file transfer operations.
  - Applied to all framework adapters: Magento 2, Laravel, WordPress, and Symfony.
  - Updated corresponding BATS unit tests to verify the new behavior.

### 🛠 Improvements

- **Enhanced `warden self-update` user experience:**
  - Now prompts users to confirm force update when uncommitted changes are detected, instead of aborting immediately.
  - Provides interactive choice: "Do you want to discard these changes and force update? [y/N]"
  - Improves usability by reducing the need to re-run with `--force` flag.

## [2.4.0] - 2026-01-19

**v2.4.0: Bootstrap Clone Enhancements & Agent Guidelines**

This release enhances the bootstrap command's cloning capabilities with better configuration preservation and auto-detection, while also optimizing argument parsing across all adapters. It also introduces dedicated guidelines for AI agents contributing to the project.

### ✨ New Features

- **Enhanced Bootstrap Cloning:**
  - Improved configuration preservation when using `--clone`.
  - Better project auto-detection mechanisms during bootstrap.

- **Agent Guidelines:**
  - Added `AGENTS.md` with comprehensive guidelines and best practices for AI agents working on the codebase.

### 🛠 Improvements

- **Bootstrap Optimization:**
  - Refactored argument parsing across all framework adapters for better consistency and performance.
- **Code Hygiene:**
  - Removed obsolete shellcheck directives to clean up the codebase.

## [2.3.0] - 2026-01-18

**v2.3.0: Project Shortcuts, Minimal Verbose Mode & Self-Update**

This release introduces project-level shortcuts for common tasks, a minimal verbose mode for focused debugging, and a new self-update command for easy maintenance. It also includes architectural refinements for more robust remote execution and a cleaner test suite.

### ✨ New Features

- **Project Shortcuts (`warden open`):**
  - Added support for quickly opening the site, database, or SSH shell directly from the project directory.
  - Automatically identifies the current project context for faster access.

- **Minimal Verbose Mode (`-v`, `-vv`):**
  - Optimized verbosity levels for better focus.
  - `-v`: Enables informative logging.
  - `-vv`: Enables deep debugging mode with `set -x` cross-adapter and on remote sessions.

- **Self-Update Command (`warden self-update`):**
  - New built-in command to reliably update the Warden Custom Commands from the GitHub repository.
  - Supports `--dry-run` to preview updates and `--force` to bypass local change warnings.

- **Multiple Environments:**
  - Standardized support for `-s|--source` and `-d|--destination` flags across all synchronization and deployment commands.

### 🛠 Improvements

- **Refactored SSH Library:**
  - Centralized connectivity and command execution logic into `lib/ssh-utils.sh`.
  - Standardized environment name sanitization and security options.

- **Standardized Error Handling:**
  - Centralized messaging logic in `lib/error-handling.sh`.
  - Unified output formatting for errors, warnings, and information across all adapters.

- **Non-Interactive Execution:**
  - Improved `-y|--yes` flag support for automated environments.
  - Automatically accepts `auth.json` configuration in Magento 2 bootstrap workflows.

- **Lean Test Infrastructure:**
  - Removed external dependencies on `bats-assert` and `bats-support`.
  - Simplified all unit tests to use native Bash and BATS assertions for faster and more portable execution.

### 🐛 Bug Fixes

- **Test Blocking prompts:** Fixed an issue where interactive prompts would hang automated integration tests despite using the `-y` flag.
- **Environment Detection:** Corrected error reporting when specific environment details (like `dev`) were missing from `.env`.

### 🚀 Key Features

- **Cross-Framework Parity:** Achieved full command and feature parity across Magento 2, Laravel, Symfony, and WordPress adapters.

## [2.2.0] - 2026-01-14

**v2.2.0: Deployer Strategy & Production Optimization**

This release integrates the powerful **Deployer** tool as a first-class deployment strategy within Warden, enabling zero-downtime deployments and advanced rollback capabilities. It also ensures all production deployments use optimized Composer flags by default and improves Docker container orchestration.

### ✨ New Features

- **Deployer Strategy (`--deployer`):**
  - Added native support for Deployer via `warden deploy --deployer` (or `--strategy=deployer`).
  - Automatically detects `deploy.php` or `deploy.yaml` configurations.
  - Installs `deployer` globally within the container if missing from the project.
  - Executes deployment entirely within the local Warden container for consistent environments.
  - Automatically configures SSH (`~/.ssh/config`) to bypass host key verification for seamless connectivity.

- **Deployer CLI Options:**
  - `--deployer-config=<path>`: Specific path to a custom Deployer configuration file.
  - `--strategy=deployer|native`: Explicit strategy selection.
  - Environment Name Preservation: Uses the exact environment name (e.g., `develop`) passed via `-e` to match Deployer host configurations.

### 🛠 Improvements

- **Production Optimization:**
  - Standardized `composer install` commands to always use `--no-dev` and `--optimize-autoloader` for production deployments across all adapters.
  - Enhanced unit tests to verify production flag usage.
- **Test Suite Expansion:**
  - Added comprehensive BATS unit tests for the new Deployer strategy (`tests/unit/adapters/magento2/deployer.bats`).
  - Verified installation, configuration detection, and command execution flows.

### 🐛 Bug Fixes

- **Deployer "Host key verification failed":** Resolved by injecting an idempotent SSH configuration into the container before execution.
- **Deployer 7+ TypeError:** Fixed by removing invalid CLI string overrides for `ssh_arguments`.
- **Variable Pollution:** Redirected installation status messages to `STDERR` to ensuring binary path variables remain clean.

## [2.1.0] - 2026-01-14

**v2.1.0: Sensitive Data Exclusion & Test Suite Stabilization**

This release introduces sensitive data exclusion for all framework adapters, stabilizes database imports by resolving `pv` and scope issues, and enhances the integration test suite for better cross-environment reliability.

### ✨ New Features

- **Sensitive Data Exclusion (`--exclude-sensitive-data`):**
  - Added support for `--exclude-sensitive-data` flag to `warden db-dump` for **Laravel**, **Symfony**, and **WordPress** adapters.
  - Automatically excludes sensitive tables (e.g., users, sessions, password resets) during database exports.
  - Aligns logic across all 4 major framework adapters.

### 🛠 Improvements

- **Robust Database Sync (`warden sync --db`):**
  - Updated to accept either hyphenated naming (e.g., `local-to-dev`) or direct streaming confirmation in integration tests.
  - Improved compatibility with different `mariadb-dump` versions.
- **Enhanced Integration Tests:**
  - Added explicit SSH server setup/start before "Clone from Staging" scenarios in bootstrap tests.
  - Ensures SSH connectivity even if the staging container was restarted or stopped.
  - Fixed WordPress bootstrap test command to standard single-call pattern.
  - All 163 integration tests now passing across Magento2, Symfony, Laravel, and WordPress.

### 🐛 Bug Fixes

- **PV Command Fallback:** Fixed `warden db-import` error when `pv` is not installed by correctly falling back to `cat` while preserving progress visibility settings.
- **Local Scope fixes:** Resolved "local: can only be used in a function" errors in `db-import` scripts across all adapters.
- **Grep Brittleness:** Refactored unit tests to use multiple, smaller `grep` assertions instead of single long strings, reducing test failures due to minor formatting changes.
- **MySQL Import flags:** Removed incorrect `-f` (force) flag when piping to `mysql`/`mariadb` to prevent confusing error messages when errors occur.

## [2.0.0] - 2026-01-12

**v2.0.0: Interactive Remote Setup & Robust DB Sync**

This major release significantly improves database synchronization reliability by introducing file-based transfers and transactional integrity. It also adds a new interactive command for configuring remote environments and expands the test suite with comprehensive unit and integration tests.

### ✨ New Features

- **Interactive Remote Setup (`warden setup-remotes`):**
  - New wizard-style command to easily configure remote environments (Dev/Staging) in `.env`.
  - Validates inputs and updates `.env` file automatically.

- **Robust DB Sync (`warden sync --db`):**
  - Refactored Remote-to-Remote (R2R) sync to use file-based transfer (Dump -> SCP -> Import) instead of piping.
  - Added `--force` flag to `mysqldump` to gracefully handle missing view/table definitions.
  - Improved error handling and transactional safety during syncs.

- **Laravel Legacy Support:**
  - Added support for legacy Laravel 4 `app/config/local/database.php` via `.env.php`.
  - Improved non-interactive mode for legacy projects.

### 🛠 Improvements

- **Refactored Adapters:** Centralized logic in `utils.sh` for all frameworks (Magento 2, Laravel, Symfony, WordPress).
- **Extended Test Coverage:**
  - Added comprehensive unit tests (`.bats`) for `open`, `sync`, and `utils` commands.
  - Added full integration tests for Database Sync and Remote-to-Remote operations.
- **Test Environment Stability:**
  - Implemented DNS resolution fixes (`/etc/hosts` injection) for test containers.
  - Added `configure-test-envs.sh` to restore SSH/DNS settings after container recreation.

### 🐛 Bug Fixes

- **Fixed `mysqldump` failures** on views with invalid definers or missing tables.
- **Fixed SSH pipe corruption** issues during large database transfers.
- **Fixed SSH persistence** issues where test containers lost configuration after bootstrap.

## [1.9.0] - 2026-01-09

**v1.9.0: Bootstrap Improvements & Full Integration Testing**

This release standardizes the bootstrap process across all frameworks and introduces a complete integration testing suite for ensuring stability.

### Added

- **Integration Tests:**
  - Added comprehensive BATS integration tests for `magento2`, `laravel`, `symfony`, and `wordpress`.
  - Added `tests/integration/suites/bootstrap-*.sh` for verifying clean installs and downloads.
- **Magento 2 Enhancements:**
  - Implemented dynamic database credential fetching (replacing hardcoded strings).
  - Added specific safety checks to prevent accidental execution without the dispatcher.

### Changed

- **Database Configuration:**
  - Refactored all environment adapters to use the standardized `db` service alias for maximum reliability.
  - Removed environment-specific naming logic (e.g. `WARDEN_ENV_NAME-db-1`) in favor of direct service resolution.
- **Bootstrapping:**
  - Unified `bootstrap.cmd` logic across all adapters to use consistent DB host determination.
- **Diagnostics:**
  - Replaced `ping` with `nc` (netcat) for more reliable connectivity checks in `setup-test-envs.sh`.

### Fixed

- **WordPress Stability:**
  - Resolved `wp-config.php` generation issues during bootstrap.
  - Fixed SSH agent pollution in test environments.

## [1.8.0] - 2026-01-07

**v1.8.0: Unified Testing & Full Framework Parity**

This major release introduces a comprehensive BATS-based unit testing framework, achieves full command parity across all supported frameworks (Laravel, Symfony, WordPress), and refactors the integration testing infrastructure for better scalability.

### Added

- **BATS Unit Testing Framework:**
  - Comprehensive coverage for all environment adapters (Magento 2, Laravel, Symfony, WordPress).
  - Tests for `bootstrap`, `db-dump`, `db-import`, `fix-deps`, and `upgrade` logic using robust mock-based verification.
- **Full Framework Parity:**
  - **Laravel:** Added `deploy.cmd` and finalized `sync.cmd`, `db-dump.cmd`, and `db-import.cmd`.
  - **Symfony:** Added `deploy.cmd` and standardized `sync.cmd` behavior.
  - **WordPress:** Added `deploy.cmd` and updated `sync.cmd` structure.
- **Modular Integration Testing:**
  - Refactored integration tests into specialized suites in `tests/integration/suites/`.
  - Support for dynamic environment naming (`{type}-local`, `{type}-dev`, `{type}-staging`).
  - New unified runner `./tests/run-tests.sh` that executes both unit and integration tests.

### Changed

- **Testing Infrastructure:**
  - Integration tests now run in dynamic directories to prevent cross-framework conflicts.
  - Updated `setup-test-envs.sh` to handle automated SSH key distribution and network bridging for all framework types.
- **Documentation:**
  - Consolidated all testing documentation into a comprehensive `tests/README.md`.
  - Updated root `README.md` with new testing workflows.

### Fixed

- **Integration Testing:**
  - Fixed swallowed shell variables (like `$table_prefix` in WordPress) in mock configuration files by using quoted heredoc markers.
  - Resolved `mysqldump` connection failures in test environments by using dynamic host variables.
  - Fixed character encoding and DEFINER stripping in streaming DB imports.
- **SSH Isolation:**
  - Improved SSH agent isolation in test containers to prevent host-level leakage during integration runs.

## [1.7.0] - 2026-01-06

**v1.7.0: Integration Testing Suite & Sync Stability**

This release introduces a comprehensive integration testing suite for all environments, stabilizes the Remote-to-Remote synchronization, and improves the `db-dump` command usability.

### Added

- **WordPress Testing Support:**
  - Expanded integration test suite to fully support WordPress environments.
  - Added specific exclusions for WordPress caching directories in file sync tests.
  - Implemented automated `.env` and `wp-config.php` generation for test environments.
- **Local Source for `db-dump`:**
  - Added support for dumping databases directly from the local environment using `warden db-dump -s local`.

### Fixed

- **Integration Test Robustness:**
  - Fixed `test-error-handling.sh` to correctly detect error messages across different terminal outputs.
  - Fixed SSH permission issues in Docker-based test runner to allow successful Remote-to-Remote (R2R) sync tests.
  - Fixed critical data loss in `magento2/sync.cmd` regarding Remote-to-Remote DB sync by enforcing transactional persistence and splitting SSH command chains.
- **Sync Stability:**
  - Added `--force` flag to `rsync` in all environment adapters to handle cases where a remote file needs to replace a local directory of the same name.
  - Standardized `RSYNC_OPTS` to include `-azvPLk` across all frameworks for consistent symlink and directory handling.
- **Documentation:**
  - Updated `db-dump` help messages to correctly reflect the default behavior.

## [1.6.0] - 2025-12-25

**v1.6.0: Hyvä Theme Integration**

This release adds seamless Hyvä theme installation and activation during Magento 2 clean installs.

### Added

- **Hyvä Theme Installation (Magento 2):**
  - New `--hyva-install` flag for `warden bootstrap --clean-install` to automatically install and activate the Hyvä theme.
  - Automatic Hyvä repository registration with Private Packagist.
  - Installs `hyva-themes/magento2-default-theme` package.
  - Automatic theme activation after installation (sets as default frontend theme).
  - Magento version compatibility check (requires 2.4.4+).

### Changed

- **Improved Bootstrap Flow:**
  - Reordered Hyvä theme activation and media sync steps for better reliability.
  - Added `|| true` to Hyvä theme configuration command to prevent non-critical errors from stopping the bootstrap process.

## [1.5.0] - 2025-12-24

**v1.5.0: Remote Deployment & Enhanced File Sync**

This release adds remote deployment capabilities for Magento 2, introduces redeployment options for file synchronization, and standardizes SSH security options across all commands.

### Added

- **Remote Deployment (Magento 2):**
  - Added support for deploying code to remote environments via `warden deploy -e <env>`.
  - Supports both full deployment and static-only deployment on remote servers.
- **Redeployment Support:**
  - Introduced `--redeploy` flag to `warden sync` to force-sync and override protected files like `env.php`.
- **Selective Media Sync:**
  - Added `--include-product` flag to `warden sync` for Magento 2.
  - Product images are now excluded by default to significantly speed up media synchronization.
- **Improved Environment Aliases:**
  - Added `-e` and `--environment` as official aliases for the source environment in `warden sync` and its help documentation.

### Changed

- **Standardized SSH Options:**
  - Centralized SSH configuration using a new `SSH_OPTS` variable.
  - Ensures consistent security settings (`StrictHostKeyChecking=no`, etc.) across all custom commands.
- **Enhanced Asset Protection:**
  - Improved `rsync` logic in `sync.cmd` to intelligently exclude `app/etc/env.php` by default.
- **Centralized Argument Parsing:**
  - Refactored source and destination parsing in `sync.cmd` and `deploy.cmd` to be consistent across all framework adapters.
- **Command UX:**
  - Renamed `warden deploy`'s `--static` option to `--only-static` for better clarity and alignment with other commands.

### Fixed

- **Magento Version Check:** Fixed `deploy.cmd` to correctly use `bc` for decimal version comparisons, ensuring compatibility across different environments.
- **Rsync Reliability:** Improved `rsync` flags to better handle symlinks and directory structures during environment synchronization.

## [1.4.0] - 2025-12-23

**v1.4.0: Unified Sync & Enhanced Robustness**

This release introduces a powerful, unified `sync` command, enables direct database streaming for faster imports, and significantly improves the stability and error handling of all bash scripts.

### Added

- **Unified `warden sync` Command:**
  - Replaces `download-files`, `upload-files`, `sync-media`, `sync-db` with a single, versatile command.
  - Supports `--file` (f), `--media` (m), `--db`, and `--full` synchronization types.
  - Supports custom paths via `-p|--path`.
  - Supports `remote-to-remote` synchronization (piping data between two remote servers without local storage).
  - Smart defaults: Defaults to "Files" sync if no type specified; defaults to "Staging" source if not specified.
  - **Streaming Database Sync:** Direct piping of mysqldump output to mysql import, eliminating intermediate dump files for faster operations.
  - **Centralized SQL Cleanup:** Standardized `sed` filters applied during streaming (stripping DEFINERs, fixing collations, removing sensitive data).

- **Magento 2 Improvements:**
  - **Refactored Search Configuration:** Simplified search engine logic with support for version-specific overrides.
  - **Bootstrap Stability:** Added directory validation to ensure `app/etc/` exists before writing configuration files.

### Changed

- **Database Import Refactor:**
  - All `db-import` commands (all adapters) now support the `--stream-db` flag for direct imports.
  - Logic standardized to prevent exit code leakage (fixed `exit 1` on success).

- **Environment Selection Logic:**
  - Updated `env-variables` to explicitly support `-s|--source` flags.
  - Prevents overwriting of `ENV_SOURCE` if already set by a dispatcher, properly fixing `warden sync -s dev`.

- **Bash Script Robustness:**
  - **Strict `local` Scoping:** Audited and fixed all instances of valid variables incorrectly flagged as `local` outside of functions.
  - **`set -u` Compatibility:** Added default value expansions (`${VAR:-}`) across all scripts to prevent "unbound variable" errors.
  - **UX Refinements:** Removed redundant confirmation prompts when syncing from remote to `local` (safe operation).

### Fixed

- **Fixed critical bug** where `warden bootstrap` would fail on fresh installs due to missing `app/etc` directory.
- **Fixed exit code leakage** in `db-import` where scripts would return error code 1 even after successful imports.
- **Fixed `warden sync` behavior** defaulting to "Staging" even when `-s dev` was passed.
- **Fixed variable scoping errors** "local: can only be used in a function" across multiple scripts.
- **Fixed `warden sync` dry-run logic** for remote-to-remote operations (now correctly shows incremental file list without executing changes).
- **Fixed `warden sync` remote-to-remote cache flushing** by using direct `php`/`wp` commands instead of `warden env exec`.
- **Improved path normalization** to robustly strip all trailing slashes.

## [1.3.0] - 2025-12-12

**v1.3.0: Remote Cloning & Dynamic Configuration**

This release adds powerful remote environment cloning capabilities to bootstrap commands and improves reliability with dynamic database credential configuration.

### Added

- **Remote Cloning in Bootstrap (Laravel, Symfony, WordPress):**
  - New `--download-source` flag to clone source code from remote environments.
  - New `--db-dump=<file>` option to use a specific database dump file.
  - New `--skip-db-import` flag to skip database import during bootstrap.
  - Automatic database fetch from remote environment when no dump file specified.

- **Comprehensive Help Documentation:**
  - Added environment-specific `.help` files for all commands across all adapters.
  - Commands: `db-dump`, `db-import`, `download-files`, `upload-files`, `open`, `upgrade`, `fix-deps`.
  - Consistent dispatcher pattern for root-level help files.

### Changed

- **Dynamic Database Credentials:**
  - Bootstrap commands now fetch actual credentials from the running db container.
  - Uses `warden env exec -T db printenv MYSQL_USER|PASSWORD|DATABASE`.
  - Falls back to framework defaults if not available.
  - Applied to Laravel, Symfony, and WordPress bootstrap commands.

- **Magento 2 Deploy Enhancements:**
  - Added `--jobs` (`-j`) flag for parallel static content deployment (default: 4).
  - Added `--static-only` (`-s`) flag for static content deployment only.
  - Magento 2.2+ version check for parallel job support.
  - Improved asset clearing with direct `rm -rf` instead of magerun.
  - Conditional ece-patches application based on ece-tools availability.

- **Symfony Bootstrap Improvements:**
  - Uses `composer install --no-scripts` to avoid cache:clear before DB is configured.
  - Runs `composer run-script auto-scripts` after database configuration.
  - Supports `.env.local` for local database/Redis configuration (Symfony convention).

- **Open Command Defaults to LOCAL:**
  - `warden open` now defaults to local environment when no `-e` flag specified.
  - Explicit `-e local` also works correctly.

### Fixed

- **URL Encoding for Database Credentials:**
  - Database connection URLs in `open db` now URL-encode username and password.
  - Fixes compatibility with tools like Beekeeper Studio when credentials contain special characters.
  - Applied to all environments (Laravel, Magento2, Symfony, WordPress).

- **Removed Duplicate env-variables Sourcing:**
  - Fixed double-sourcing of `env-variables` in environment-specific commands.
  - Root dispatcher now sources once; env-specific files skip duplicate sourcing.
  - Intentional reloads (after fix-deps) are preserved.

- **Help File Corrections:**
  - Fixed `magento2/deploy.help` to document new `--jobs` and `--static-only` flags.
  - Fixed `magento2/download-files.help` and `upload-files.help` command names and default paths.
  - Added shebangs to all `.help` files for proper shell recognition.

## [1.2.0] - 2025-12-12

**v1.2.0: Full Multi-Framework Support & Remote Operations**

This release completes multi-framework support with comprehensive remote operations for Laravel, Symfony, and WordPress environments.

### Added

- **`warden upgrade` Command:**
  - New command to upgrade framework versions with intelligent dependency management.
  - Magento 2: Fetch-merge-relax strategy for `composer.json`, automatic PHP/Redis/Varnish version updates.
  - Laravel/Symfony/WordPress: Composer-based upgrade workflows.

- **`warden open` Command (Laravel, Symfony, WordPress):**
  - Access local and remote services: `db`, `shell`, `sftp`, `admin`, `elasticsearch`.
  - Remote database access via SSH tunnel with automatic credential parsing.
  - Supports `.env` (Laravel), `.env.local`/`.env` (Symfony), and `wp-config.php` (WordPress).

- **`warden db-dump` Command (Laravel, Symfony, WordPress):**
  - Remote database dumping via SSH with automatic gzip compression.
  - Parses credentials from remote configuration files.
  - Robust quote handling for `.env` values.

- **`warden db-import` Command Enhancements:**
  - Standardized implementation across all environments.
  - Automatic database container startup if not running.
  - Progress visualization with `pv`.
  - Dynamic credential fetching from container environment.
  - Environment-specific defaults (symfony/laravel/wordpress).

- **File Transfer Commands (Laravel, Symfony, WordPress):**
  - New `warden download-files` and `warden upload-files` commands.
  - Rsync-based file synchronization over SSH.
  - Standardized `-p|--path` argument parsing.

### Changed

- **Standardized Argument Parsing:**
  - Unified `-f|--file` and `-p|--path` argument handling across all commands.
  - Proper error messages for missing arguments.
  - Support for both space-separated (`-f file`) and equals-separated (`-f=file`) formats.

- **Removed Cloud Logic from Non-Magento Adapters:**
  - Cleaned up `CLOUD_PROJECT` related code from Laravel, Symfony, and WordPress adapters.

- **Magento 2 Improvements:**
  - Enhanced `magento-versions.json` with updated service requirements.
  - Improved `fix-deps` command with better version resolution.
  - Standardized argument parsing in `db-dump`, `db-import`, `download-files`, `upload-files`.

### Fixed

- **Fixed `.env` quote handling** in credential parsing (Laravel/Symfony).
- **Fixed `db-import` argument parsing** for `-f=filename` format.
- **Fixed database permission errors** by using container credentials directly.

## [1.1.0] - 2025-12-09

**v1.1.0: Multi-Framework Support & Intelligent Bootstrap**

This release introduces a major architectural refactor to support multiple frameworks (Laravel, Symfony, WordPress) alongside Magento 2, and enhances the automation of environment configuration.

### Added

- **Multi-Framework Support:** Added dedicated environment adapters for **Laravel**, **Symfony**, and **WordPress**.
  - New `warden bootstrap`, `set-config`, and `db-import` implementations for each framework.
- **Automatic Dependency Management (`fix-deps`):**
  - New command to automatically configure `.env` versions (PHP, Redis, Varnish, RabbitMQ, Elasticsearch/OpenSearch) based on the project's framework version.
  - Includes a `magento-versions.json` mapping file for precise service versioning.
- **Intelligent Magento 2 Bootstrap:**
  - Added logic to automatically determine the correct Search Engine (OpenSearch vs Elasticsearch) based on Magento version ( < 2.4.6, 2.4.6+, etc.).
  - Supports `opensearch`, `elasticsearch7`, `elasticsearch6`, and `elasticsearch5` configurations.
  - Support for clean installs with `--clean-install` for all frameworks.
- **Non-Interactive Bootstrap:**
  - Added `--env-name` and `--env-type` arguments to `warden bootstrap` to bypass interactive prompts during CI/CD or automated setups.

### Changed

- **Refactored Architecture:** Moved all logic into `env-adapters/{type}/` to allow for clean, framework-specific command implementations (Adapter Pattern).
- **Composer Versioning:** Updated default Composer versions in configurations (Composer 2.2 / 1.x).
- **Documentation:** Updated README with new framework setup instructions and command options.

### Fixed

- **Fixed search engine host configuration** to correctly respect `WARDEN_OPENSEARCH` flags for older Magento versions.
- **Corrected path sourcing** for `env-variables` to use `WARDEN_HOME_DIR`.

## [1.0.0] - 2025-07-04

**v1.0.0: Magento 2 Toolkit**

This release represents the stable version of the Warden Custom Commands, designed specifically for **Magento 2** development on Warden.

### Added

- **Automated Bootstrap:** complete Magento 2 installation workflow via `warden bootstrap`, including source downloading, automated configuration generation, and installation.
- **Database Management:**
  - **Smart Export:** `warden db-dump` includes logic to strip sensitive tables/data and sanitize definers.
  - **Streamlined Import:** `warden db-import` supports direct import of compressed `.sql.gz` files.
- **Environment Sync:** Tools (`sync-media`, `download-files`, `upload-files`) to easily synchronize assets and media between local and remote environments using `rsync`.
- **Developer Shortcuts:** `warden open` to quickly access shell, database, and application services; `warden deploy` for standard Magento deployment sequences.
