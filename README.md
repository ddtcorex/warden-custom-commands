# Warden Custom Commands

Custom commands that extend Warden's functionality for multiple framework types.

## Installation

### Prerequisites

1. **Docker Desktop** or **Docker Engine**

   - [Docker Desktop for Mac](https://hub.docker.com/editions/community/docker-ce-desktop-mac) 2.2.0.0 or later
   - [Docker for Linux](https://docs.docker.com/install/) (tested on Fedora 29 and Ubuntu 18.10)
   - [Docker for Windows](https://docs.docker.com/desktop/windows/install/)

   **Important:** Docker Desktop should have at least **6GB RAM** allocated (Preferences → Resources → Advanced → Memory)

2. **docker-compose** version 2 or later

   ```bash
   # Verify docker-compose is installed
   docker-compose --version
   ```

3. **Mutagen** 0.11.4 or later (macOS only, for sync sessions)
   ```bash
   # Will be automatically installed via Homebrew if not present
   ```

### Install Warden

**Option 1: Via Homebrew (Recommended)**

```bash
brew install wardenenv/warden/warden
warden svc up
```

**Option 2: Alternative Installation (Manual)**

```bash
sudo mkdir /opt/warden
sudo chown $(whoami) /opt/warden
git clone -b main https://github.com/wardenenv/warden.git /opt/warden
echo 'export PATH="/opt/warden/bin:$PATH"' >> ~/.bashrc
PATH="/opt/warden/bin:$PATH"
warden svc up
```

**For zsh users:**

```bash
echo 'export PATH="/opt/warden/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

### Install Custom Commands

```bash
# Clone this repository to ~/.warden/commands
git clone https://github.com/KaiDo92/warden-custom-commands.git ~/.warden/commands

# Make commands executable
chmod +x ~/.warden/commands/*.cmd
chmod +x ~/.warden/commands/env-adapters/*/*.cmd
```

Commands will be automatically available via `warden <command>`.

## Architecture

### Dispatcher Pattern

Commands use a **dispatcher pattern** where root commands delegate to environment-specific implementations:

```
commands/
├── bootstrap.cmd          # Dispatcher → env-adapters/{type}/bootstrap.cmd
├── db-dump.cmd            # Dispatcher → env-adapters/{type}/db-dump.cmd
├── db-import.cmd          # Dispatcher → env-adapters/{type}/db-import.cmd
├── deploy.cmd             # Dispatcher → env-adapters/{type}/deploy.cmd
├── download-files.cmd     # Dispatcher → env-adapters/{type}/download-files.cmd
├── open.cmd               # Dispatcher → env-adapters/{type}/open.cmd
├── set-config.cmd         # Dispatcher → env-adapters/{type}/set-config.cmd
├── sync-media.cmd         # Dispatcher → env-adapters/{type}/sync-media.cmd
├── upload-files.cmd       # Dispatcher → env-adapters/{type}/upload-files.cmd
│
├── self-update.cmd        # Global command
├── env-variables          # Global environment loader
│
└── env-adapters/          # Environment-specific implementations
    ├── magento2/
    │   ├── bootstrap.cmd
    │   ├── bootstrap.help
    │   ├── db-dump.cmd
    │   ├── db-dump.help
    │   ├── db-import.cmd
    │   ├── db-import.help
    │   ├── deploy.cmd
    │   ├── deploy.help
    │   ├── download-files.cmd
    │   ├── download-files.help
    │   ├── open.cmd
    │   ├── open.help
    │   ├── set-config.cmd
    │   ├── sync-media.cmd
    │   ├── sync-media.help
    │   ├── upload-files.cmd
    │   └── upload-files.help
    │
    ├── laravel/
    │   ├── bootstrap.cmd
    │   ├── bootstrap.help
    │   ├── db-import.cmd
    │   ├── db-import.help
    │   ├── set-config.cmd
    │   └── set-config.help
    │
    ├── wordpress/
    │   ├── bootstrap.cmd
    │   ├── bootstrap.help
    │   ├── db-import.cmd
    │   ├── db-import.help
    │   ├── set-config.cmd
    │   └── set-config.help
    │
    └── symfony/
        ├── bootstrap.cmd
        ├── bootstrap.help
        ├── db-import.cmd
        ├── db-import.help
        ├── set-config.cmd
        └── set-config.help
```

### How It Works

1. You run: `warden bootstrap`
2. Warden calls: `~/.warden/commands/bootstrap.cmd` (dispatcher)
3. Dispatcher reads `WARDEN_ENV_TYPE` from `.env`
4. Dispatcher sources the appropriate implementation:
   - `env-adapters/magento2/bootstrap.cmd` for Magento 2
   - `env-adapters/laravel/bootstrap.cmd` for Laravel
   - etc.

## Commands Reference

### Magento 2 Commands

#### `warden bootstrap`

Initialize a new Magento 2 environment with all dependencies and configuration.

**Options:**

- `-h, --help` - Display help menu
- `--env-name=<name>` - Initialize environment with specified name
- `--env-type=<type>` - Initialize environment with specified type
- `--skip-deploy` - Skip deployment after installation

**Example:**

```bash
warden bootstrap
warden bootstrap --skip-deploy
```

#### `warden db-dump`

Create a database backup with optional compression.

**Options:**

- `-h, --help` - Display help menu
- `-f, --file=<file>.sql.gz` - Output file
- `-e, --environment=<dev|staging|production>` - Specific environment (default: staging)
- `--full` - Export full database from selected environment
- `--exclude-sensitive-data` - Exclude sensitive data

**Example:**

```bash
warden db-dump
warden db-dump --file=production-backup.sql.gz --environment=production
warden db-dump --exclude-sensitive-data
```

#### `warden db-import`

Import database from local or remote file.

**Options:**

- `-h, --help` - Display help menu
- `-f, --file=<file>` - Path to existing database dump file (can be gzipped)

**Example:**

```bash
warden db-import --file=backup.sql.gz
warden db-import -f /path/to/database.sql
```

#### `warden deploy`

Deploy Magento application (run setup:upgrade, compile, deploy).

**Options:**

- `-h, --help` - Display help menu

**Arguments:**

- `full` - Full deployment (default)
- `static` - Deploy static files only

**Example:**

```bash
warden deploy
warden deploy full
warden deploy static
```

#### `warden download-files`

Download files from a remote environment to the local file system.

**Options:**

- `-h, --help` - Display help menu
- `-e, --environment=<dev|staging|production>` - Environment to sync files from (default: staging)
- `-p, --path=<dump_path>` - Specific path to download (default: ./)

**Example:**

```bash
warden download-files
warden download-files --environment=production
warden download-files --path=pub/media/
```

#### `warden download-source`

Download source code files from a remote environment to the local file system (excludes generated, var, pub/media, pub/static, and archive files).

**Options:**

- `-h, --help` - Display help menu
- `-e, --environment=<dev|staging|production>` - Environment to download from (default: staging)

**Example:**

```bash
warden download-source
warden download-source --environment=production
```

#### `warden upload-files`

Upload files from the local file system to a remote environment.

**Options:**

- `-h, --help` - Display help menu
- `-e, --environment=<dev|staging|production>` - Environment to upload files to (default: staging)
- `-p, --path=<upload_path>` - Specific path to upload (default: ./)

**Example:**

```bash
warden upload-files
warden upload-files --environment=production --path=pub/media/
```

#### `warden open`

Open Magento services in browser or establish tunnels.

**Options:**

- `-h, --help` - Display help menu
- `-e, --environment=<local|dev|staging|production>` - Specific environment (default: local)

**Arguments:**

- `db` - Open database connection
- `shell` - Open shell
- `sftp` - Open SFTP connection
- `admin` - Open admin panel
- `elasticsearch` - Open Elasticsearch

**Example:**

```bash
warden open
warden open admin
warden open --environment=staging
```

#### `warden set-config`

Configure Magento settings (base URLs, cache, sessions, etc.).

**Example:**

```bash
warden set-config
```

#### `warden sync-media`

Download media files from a remote environment to the local file system.

**Options:**

- `-h, --help` - Display help menu
- `-e, --environment=<dev|staging|production>` - Environment to sync media from (default: staging)

**Example:**

```bash
warden sync-media
warden sync-media --environment=production
```

#### `warden upgrade`

Upgrade Magento to a specified version.

**Options:**

- `--version=<version>` - Target version to upgrade to (required)
- `--dry-run` - Show what would be done without making changes
- `--skip-db-upgrade` - Skip database upgrade step

**Example:**

```bash
warden upgrade --version=2.4.8
warden upgrade --version=2.4.8 --dry-run
warden upgrade --version=2.4.8-p3 --skip-db-upgrade
```

### Laravel Commands

#### `warden bootstrap`

Initialize Laravel environment with dependencies and database.

**Options:**

- `--clean-install` - Create fresh Laravel project
- `--env-name=<name>` - Initialize environment with specified name
- `--env-type=<type>` - Initialize environment with specified type
- `--skip-composer-install` - Skip composer install
- `--skip-migrate` - Skip database migrations

**Example:**

```bash
warden bootstrap
warden bootstrap --clean-install
```

#### `warden db-import`

Import database dump into Laravel project.

**Example:**

```bash
warden db-import database.sql
```

#### `warden set-config`

Update Laravel `.env` configuration with Warden-specific settings.

**Example:**

```bash
warden set-config
```

#### `warden upgrade`

Upgrade Laravel framework to a specified version.

**Options:**

- `--version=<version>` - Target version to upgrade to (required)
- `--dry-run` - Show what would be done without making changes

**Example:**

```bash
warden upgrade --version=11.0
warden upgrade --version=10.x --dry-run
```

### Symfony Commands

#### `warden bootstrap`

Initialize Symfony environment with dependencies and database.

**Options:**

- `-h, --help` - Display help menu
- `--clean-install` - Create fresh Symfony project from scratch
- `--env-name=<name>` - Initialize environment with specified name
- `--env-type=<type>` - Initialize environment with specified type
- `--skip-composer-install` - Skip composer install
- `--skip-migrate` - Skip database migrations

**Example:**

```bash
warden bootstrap
warden bootstrap --clean-install
warden bootstrap --skip-migrate
```

#### `warden db-import`

Import database dump into Symfony project.

**Options:**

- `-h, --help` - Display help menu
- `-f, --file=<file>` - Path to database dump file (can be gzipped)

**Example:**

```bash
warden db-import --file=database.sql.gz
warden db-import -f backup.sql
```

#### `warden set-config`

Update Symfony configuration for Warden environment.

**Example:**

```bash
warden set-config
```

#### `warden upgrade`

Upgrade Symfony framework to a specified version.

**Options:**

- `--version=<version>` - Target version to upgrade to (required)
- `--dry-run` - Show what would be done without making changes

**Example:**

```bash
warden upgrade --version=7.0
warden upgrade --version=6.4 --dry-run
```

### WordPress Commands

#### `warden bootstrap`

Initialize WordPress environment with complete installation.

**Options:**

- `-h, --help` - Display help menu
- `--clean-install` - Download WordPress core and install
- `--env-name=<name>` - Initialize environment with specified name
- `--env-type=<type>` - Initialize environment with specified type
- `--skip-composer-install` - Skip composer install
- `--skip-wp-install` - Skip WordPress installation

**Example:**

```bash
warden bootstrap
warden bootstrap --clean-install
```

**Note:** With `--clean-install`, WordPress will be downloaded, wp-config.php created, and the site installed with admin credentials displayed.

#### `warden db-import`

Import database dump into WordPress.

**Options:**

- `-h, --help` - Display help menu
- `-f, --file=<file>` - Path to database dump file (can be gzipped)

**Example:**

```bash
warden db-import --file=production.sql.gz
warden db-import -f backup.sql
```

**Note:** After import, use WP-CLI to search-replace URLs if needed:

```bash
warden env exec php-fpm wp search-replace 'old-domain.com' 'app.test.test'
```

#### `warden set-config`

Update WordPress configuration for Warden environment.

**Example:**

```bash
warden set-config
```

#### `warden upgrade`

Upgrade WordPress core to a specified version.

**Options:**

- `--version=<version>` - Target version to upgrade to (required)
- `--dry-run` - Show what would be done without making changes

**Example:**

```bash
warden upgrade --version=6.5
warden upgrade --version=6.4.3 --dry-run
```

### Global Commands

#### `warden self-update`

Update custom commands from git repository.

**Example:**

```bash
warden self-update
```

## Adding New Environment Support

To add support for a new framework (e.g., Symfony):

1. **Create the directory:**

   ```bash
   mkdir -p ~/.warden/commands/env-adapters/symfony
   ```

2. **Create command files:**

   ```bash
   touch ~/.warden/commands/env-adapters/symfony/bootstrap.cmd
   touch ~/.warden/commands/env-adapters/symfony/set-config.cmd
   # ... other commands
   ```

3. **Implement the logic:**

   ```bash
   #!/usr/bin/env bash
   # Don't include shebang - file will be sourced

   :: Installing Symfony
   warden env exec php-fpm composer install
   # ... Symfony-specific logic
   ```

4. **Create help files (optional):**

   ```bash
   touch ~/.warden/commands/env-adapters/symfony/bootstrap.help
   ```

5. **Make executable:**
   ```bash
   chmod +x ~/.warden/commands/env-adapters/symfony/*.cmd
   ```

The commands will automatically be available when `WARDEN_ENV_TYPE=symfony` is set in `.env`.

## Configuration

Custom commands read environment variables from the project's `.env` file:

```bash
# Required
WARDEN_ENV_NAME=myproject
WARDEN_ENV_TYPE=magento2   # or laravel, wordpress, symfony

# Optional (framework-specific)
TRAEFIK_DOMAIN=myproject.test
TRAEFIK_SUBDOMAIN=app

# Magento 2 specific
PHP_VERSION=8.2
COMPOSER_VERSION=2
MYSQL_DISTRIBUTION=mysql
MYSQL_DISTRIBUTION_VERSION=8.0

# Laravel specific
DB_CONNECTION=mysql
DB_HOST=db
DB_DATABASE=magento
DB_USERNAME=magento
DB_PASSWORD=magento
```

## Troubleshooting

### Commands not found

```bash
# Ensure commands are executable
chmod +x ~/.warden/commands/*.cmd
chmod +x ~/.warden/commands/env-adapters/*/*.cmd
```

### Wrong environment commands loading

```bash
# Check .env file has correct WARDEN_ENV_TYPE
cat .env | grep WARDEN_ENV_TYPE
```

### Permission issues

```bash
# Fix ownership
chown -R $(whoami):$(whoami) ~/.warden/commands
```

## Contributing

1. Create a feature branch
2. Make your changes
3. Test with different environment types
4. Submit a pull request

## License

GNU General Public License v3.0
