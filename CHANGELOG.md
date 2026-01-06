# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

- Fixed critical bug where `warden bootstrap` would fail on fresh installs due to missing `app/etc` directory.
- Fixed exit code leakage in `db-import` where scripts would return error code 1 even after successful imports.
- Fixed `warden sync` defaulting to "Staging" even when `-s dev` was passed.
- Fixed "local: can only be used in a function" errors in multiple scripts.
- Fixed `warden sync` directory nesting issues by standardizing parent-directory referencing.
- Fixed `warden sync` dry-run logic for remote-to-remote operations (now correctly shows incremental file list without executing changes).
- Fixed `warden sync` remote-to-remote cache flushing by using direct `php`/`wp` commands instead of `warden env exec`.
- Enhanced `warden sync` to auto-create parent directories on destination if missing.
- Fixed `warden bootstrap` crash related to uninitialized variables during partial syncs.
- Improved path normalization to robustly strip all trailing slashes (e.g. `path//` -> `path`).

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

- Fixed `.env` quote handling in credential parsing (Laravel/Symfony).
- Fixed `db-import` argument parsing for `-f=filename` format.
- Fixed database permission errors by using container credentials directly.

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

- Fixed search engine host configuration to correctly respect `WARDEN_OPENSEARCH` flags for older Magento versions.
- Corrected path sourcing for `env-variables` to use `WARDEN_HOME_DIR`.

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
