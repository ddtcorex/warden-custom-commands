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

### Option 1: Via Homebrew (Recommended)

```bash
brew install wardenenv/warden/warden
warden svc up
```

### Option 2: Alternative Installation (Manual)

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

### SSH Key Setup (Local → Remote Server)

If you plan to use remote operations (cloning sites, syncing media/files, downloading databases), set up SSH keys for passwordless authentication.

#### 1) Generate an SSH key on your local machine

```bash
# Use ed25519 (recommended) or RSA
ssh-keygen -t ed25519 -C "your_email@example.com"

# Or for RSA (wider compatibility)
ssh-keygen -t rsa -b 4096 -C "your_email@example.com"
```

#### 2) Start the SSH agent and add your key

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519   # or ~/.ssh/id_rsa
```

#### 3) Add your public key to the remote server

```bash
ssh-copy-id -p 22 user@your-server.com

# Or manually:
cat ~/.ssh/id_ed25519.pub | ssh user@server 'cat >> ~/.ssh/authorized_keys'
```

#### 4) Test SSH login

```bash
ssh -p 22 user@your-server.com
```

#### 5) Optional: Simplify with `~/.ssh/config`

```ssh-config
Host staging
    HostName staging.example.com
    User deploy
    Port 22
    IdentityFile ~/.ssh/id_ed25519
```

Then connect with just `ssh staging`.

#### Troubleshooting

- **Permission denied**: Ensure `~/.ssh` is `700` and `authorized_keys` is `600` on remote
- **Agent not running**: Add `eval "$(ssh-agent -s)" && ssh-add` to your `.bashrc`/`.zshrc`
- **Host key verification**: Commands now include `-o StrictHostKeyChecking=no` to skip prompts

## Architecture

### Dispatcher Pattern

Commands use a **dispatcher pattern** where root commands delegate to environment-specific implementations:

```text
commands/
├── bootstrap.cmd          # Dispatcher → env-adapters/{type}/bootstrap.cmd
├── db-dump.cmd            # Dispatcher → env-adapters/{type}/db-dump.cmd
├── db-import.cmd          # Dispatcher → env-adapters/{type}/db-import.cmd
├── deploy.cmd             # Dispatcher → env-adapters/{type}/deploy.cmd
├── open.cmd               # Dispatcher → env-adapters/{type}/open.cmd
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
    │   ├── open.cmd
    │   ├── open.help
    │
    ├── laravel/
    │   ├── bootstrap.cmd
    │   ├── db-dump.cmd
    │   ├── db-dump.help
    │   ├── db-import.cmd
    │   ├── fix-deps.cmd
    │   ├── fix-deps.help
    │   ├── open.cmd
    │   ├── open.help
    │   ├── set-config.cmd
    │   ├── upgrade.cmd
    │   └── upgrade.help
    │
    ├── symfony/
    │   ├── bootstrap.cmd
    │   ├── db-dump.cmd
    │   ├── db-dump.help
    │   ├── db-import.cmd
    │   ├── fix-deps.cmd
    │   ├── fix-deps.help
    │   ├── open.cmd
    │   ├── open.help
    │   ├── set-config.cmd
    │   ├── upgrade.cmd
    │   └── upgrade.help
    │
    └── wordpress/
        ├── bootstrap.cmd
        ├── db-dump.cmd
        ├── db-dump.help
        ├── db-import.cmd
        ├── fix-deps.cmd
        ├── fix-deps.help
        ├── open.cmd
        ├── open.help
        ├── set-config.cmd
        ├── upgrade.cmd
        └── upgrade.help
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

### Common Commands

#### `warden sync`

The unified synchronization command for files, media, and databases.

**Options:**

- `-h, --help` - Display help menu
- `-s`, `--source`: Source environment (default: `staging`)
- `-d`, `--destination`: Destination environment (default: `local`)
- `-f`, `--file`: Sync source code/files
- `-m`, `--media`: Sync media files
- `--db`: Sync database (streaming, no local dump file created)
- `--full`: Sync everything (file, media, db)
- `-p`, `--path`: Sync a specific directory or file path
- `--dry-run`: Show what would happen without making changes
- `--flush`: Flush cache after sync (default: disabled)
- `--delete`: Delete files on destination that are not present in source

**Example:**

```bash
warden sync --db                    # Sync DB from staging to local
warden sync --source=prod --media   # Sync media from production
warden sync --destination=dev --file # Upload local files to dev environment
warden sync --path=pub/media/tmp    # Sync specific path
```

> [!IMPORTANT]
> Operations to remote environments (where neither source nor destination is `local`) use **SSH Agent Forwarding**.
> - The local machine connects to the Source.
> - The Source connects to the Destination using **your local keys**.
> - **Requirement:** You must have your SSH keys loaded locally (`ssh-add -l`). If empty, run `ssh-add`.

### Magento 2 Commands

#### Magento 2: `warden bootstrap`

Initialize a new Magento 2 environment with all dependencies and configuration.

**Options:**

- `-h, --help` - Display help menu
- `--env-name=<name>` - Initialize environment with specified name
- `--env-type=<type>` - Initialize environment with specified type
- `--clean-install` - Create fresh Magento project
- `--version=<version>` - Magento version for clean install (e.g., 2.4.8)
- `--include-sample` - Include sample data (clean install)

- `--no-stream-db` - Use intermediate dump file instead of streaming (default: streaming enabled)
- `--download-source` - Download source code from remote
- `--db-dump=<file>` - Use specific database dump file
- `--skip-db-import` - Skip database import
- `--skip-media-sync` - Skip media sync from remote
- `--skip-composer-install` - Skip composer install
- `--skip-admin-create` - Skip admin user creation

**Example:**

```bash
warden bootstrap
warden bootstrap --clean-install --version=2.4.8
warden bootstrap --download-source -e production
```

#### Magento 2: `warden db-dump`

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

#### Magento 2: `warden db-import`

Import database from local or remote file.

**Options:**

- `-h, --help` - Display help menu
- `-f, --file=<file>` - Path to existing database dump file (can be gzipped)

**Example:**

```bash
warden db-import --file=backup.sql.gz
warden db-import -f /path/to/database.sql
```

#### Magento 2: `warden deploy`

Deploy Magento application (run setup:upgrade, compile, deploy).

**Options:**

- `-h, --help` - Display help menu
- `-j, --jobs=<n>` - Number of parallel jobs for static content (default: 4)
- `-s, --static-only` - Deploy static content only (skip di:compile)

**Example:**

```bash
warden deploy
warden deploy --jobs=8
warden deploy --static-only
```

#### Magento 2: `warden open`

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

#### Magento 2: `warden set-config`

Configure Magento settings (base URLs, cache, sessions, etc.).

**Example:**

```bash
warden set-config
```


#### Magento 2: `warden upgrade`

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

#### Laravel: `warden bootstrap`

Initialize Laravel environment with dependencies and database.

**Options:**

- `--clean-install` - Create fresh Laravel project
- `--download-source` - Download source code from remote environment
- `--db-dump=<file>` - Use specific database dump file
- `--skip-db-import` - Skip database import
- `--no-stream-db` - Use intermediate dump file instead of streaming (default: streaming enabled)
- `--env-name=<name>` - Initialize environment with specified name
- `--env-type=<type>` - Initialize environment with specified type
- `--skip-composer-install` - Skip composer install
- `--skip-migrate` - Skip database migrations
- `--fix-deps` - Auto-fix dependency versions for framework

**Example:**

```bash
warden bootstrap
warden bootstrap --clean-install
warden bootstrap --download-source -e production
warden bootstrap --db-dump=backup.sql.gz
```

#### Laravel: `warden db-dump`

Dump database from a remote Laravel environment.

**Options:**

- `-e, --environment=<dev|staging|production>` - Environment to dump from (default: staging)
- `-f, --file=<file>` - Output filename (default: auto-generated)

**Example:**

```bash
warden db-dump -e dev
warden db-dump --file=production-backup.sql.gz -e production
```

#### Laravel: `warden db-import`

Import database dump into Laravel project.

**Options:**

- `-f, --file=<file>` - Path to database dump file (can be gzipped)

**Example:**

```bash
warden db-import -f database.sql.gz
warden db-import --file=backup.sql
```

#### Laravel: `warden open`

Open Laravel services (local or remote).

**Options:**

- `-e, --environment=<local|dev|staging|production>` - Environment (default: local)
- `-a` - Auto-open in browser/client

**Arguments:** `db`, `shell`, `sftp`, `admin`, `elasticsearch`

**Example:**

```bash
warden open db
warden open -e staging shell
```


#### Laravel: `warden set-config`

Update Laravel `.env` configuration with Warden-specific settings.

**Example:**

```bash
warden set-config
```

#### Laravel: `warden upgrade`

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

#### Symfony: `warden bootstrap`

Initialize Symfony environment with dependencies and database.

**Options:**

- `-h, --help` - Display help menu
- `--clean-install` - Create fresh Symfony project from scratch
- `--download-source` - Download source code from remote environment
- `--db-dump=<file>` - Use specific database dump file
- `--skip-db-import` - Skip database import
- `--no-stream-db` - Use intermediate dump file instead of streaming (default: streaming enabled)
- `--env-name=<name>` - Initialize environment with specified name
- `--env-type=<type>` - Initialize environment with specified type
- `--skip-composer-install` - Skip composer install
- `--skip-migrate` - Skip database migrations
- `--fix-deps` - Auto-fix dependency versions for framework

**Example:**

```bash
warden bootstrap
warden bootstrap --clean-install
warden bootstrap --download-source -e staging
warden bootstrap --db-dump=var/backup.sql.gz
```

#### Symfony: `warden db-dump`

Dump database from a remote Symfony environment.

**Options:**

- `-e, --environment=<dev|staging|production>` - Environment to dump from (default: staging)
- `-f, --file=<file>` - Output filename (default: auto-generated)

**Example:**

```bash
warden db-dump -e dev
warden db-dump --file=production-backup.sql.gz -e production
```

#### Symfony: `warden db-import`

Import database dump into Symfony project.

**Options:**

- `-f, --file=<file>` - Path to database dump file (can be gzipped)

**Example:**

```bash
warden db-import --file=database.sql.gz
warden db-import -f backup.sql
```

#### Symfony: `warden open`

Open Symfony services (local or remote).

**Options:**

- `-e, --environment=<local|dev|staging|production>` - Environment (default: local)
- `-a` - Auto-open in browser/client

**Arguments:** `db`, `shell`, `sftp`, `admin`, `elasticsearch`

**Example:**

```bash
warden open db
warden open -e staging shell
```


#### Symfony: `warden set-config`

Update Symfony configuration for Warden environment.

**Example:**

```bash
warden set-config
```

#### Symfony: `warden upgrade`

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

#### WordPress: `warden bootstrap`

Initialize WordPress environment with complete installation.

**Options:**

- `-h, --help` - Display help menu
- `--clean-install` - Download WordPress core and install
- `--download-source` - Download source code from remote environment
- `--db-dump=<file>` - Use specific database dump file
- `--skip-db-import` - Skip database import
- `--no-stream-db` - Use intermediate dump file instead of streaming (default: streaming enabled)
- `--env-name=<name>` - Initialize environment with specified name
- `--env-type=<type>` - Initialize environment with specified type
- `--skip-composer-install` - Skip composer install
- `--skip-wp-install` - Skip WordPress installation
- `--fix-deps` - Auto-fix dependency versions for framework

**Example:**

```bash
warden bootstrap
warden bootstrap --clean-install
warden bootstrap --download-source -e production
warden bootstrap --db-dump=wp-content/backup.sql.gz
```

**Note:** With `--clean-install`, WordPress will be downloaded, wp-config.php created, and the site installed with admin credentials displayed.

#### WordPress: `warden db-dump`

Dump database from a remote WordPress environment.

**Options:**

- `-e, --environment=<dev|staging|production>` - Environment to dump from (default: staging)
- `-f, --file=<file>` - Output filename (default: auto-generated)

**Example:**

```bash
warden db-dump -e dev
warden db-dump --file=production-backup.sql.gz -e production
```

#### WordPress: `warden db-import`

Import database dump into WordPress.

**Options:**

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

#### WordPress: `warden open`

Open WordPress services (local or remote).

**Options:**

- `-e, --environment=<local|dev|staging|production>` - Environment (default: local)
- `-a` - Auto-open in browser/client

**Arguments:** `db`, `shell`, `sftp`, `admin`, `elasticsearch`

**Example:**

```bash
warden open db
warden open -e staging admin
```

#### WordPress: `warden set-config`

Update WordPress configuration for Warden environment.

**Example:**

```bash
warden set-config
```

#### WordPress: `warden upgrade`

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
