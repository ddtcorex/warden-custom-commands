# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

### Fixed

- Fixed regex when removing sandbox mode comments in exported databases.
- Improved table exclusion lists for database exports (ignoring logs, sessions, etc.).
- Added `opensearch` command configuration support during setup.
