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

### Install Warden

### Option 1: Manual Installation (Recommended)

```bash
sudo mkdir /opt/warden
sudo chown $(whoami) /opt/warden
git clone -b main https://github.com/wardenenv/warden.git /opt/warden
echo 'export PATH="/opt/warden/bin:$PATH"' >> ~/.bashrc
PATH="/opt/warden/bin:$PATH"
warden svc up
```

### Option 2: Via Homebrew

```bash
brew install wardenenv/warden/warden
warden svc up
```

**For zsh users:**

```bash
echo 'export PATH="/opt/warden/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

### DNS Resolver Configuration (Linux)

If you are running on Linux (Ubuntu, Fedora, etc.), you must configure `systemd-resolved` to work with Warden's DNS resolver.

1. Create a configuration directory for `systemd-resolved`:

   ```bash
   sudo mkdir -p /etc/systemd/resolved.conf.d
   ```

2. Create the Warden configuration file:

   ```bash
   sudo tee /etc/systemd/resolved.conf.d/warden.conf <<EOF
   [Resolve]
   DNS=127.0.0.1
   Domains=~test
   EOF
   ```

3. Restart the service:

   ```bash
   sudo systemctl restart systemd-resolved
   ```

For more details, see [Warden Docs: Systemd Resolved](https://docs.warden.dev/configuration/dns-resolver.html#systemd-resolved).

### Install Custom Commands

```bash
# Clone this repository to ~/.warden/commands
git clone https://github.com/ddtcorex/warden-custom-commands.git ~/.warden/commands

# Make commands executable
chmod +x ~/.warden/commands/*.cmd
chmod +x ~/.warden/commands/env-adapters/*/*.cmd
```

> [!TIP] > **Development Workflow:** If you are contributing or modifying these commands, it is recommended to symlink your development directory to `~/.warden/commands`:
>
> ```bash
> ln -s ~/path/to/your/repo ~/.warden/commands
> ```

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
├── env-sync.cmd           # Dispatcher → env-adapters/{type}/env-sync.cmd
├── fix-deps.cmd           # Dispatcher → env-adapters/{type}/fix-deps.cmd
├── open.cmd               # Dispatcher → env-adapters/{type}/open.cmd
├── set-config.cmd         # Dispatcher → env-adapters/{type}/set-config.cmd
├── upgrade.cmd            # Dispatcher → env-adapters/{type}/upgrade.cmd
│
├── env-variables          # Global environment loader
├── remote-exec.cmd        # Global command
├── self-update.cmd        # Global command
├── setup-remotes.cmd      # Global command
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
    │   ├── env-sync.cmd
    │   ├── fix-deps.cmd
    │   ├── fix-deps.help
    │   ├── magento-versions.json
    │   ├── open.cmd
    │   ├── open.help
    │   ├── set-config.cmd
    │   ├── set-config.help
    │   ├── upgrade.cmd
    │   └── upgrade.help
    │
    ├── laravel/
    │   ├── bootstrap.cmd
    │   ├── db-dump.cmd
    │   ├── db-dump.help
    │   ├── db-import.cmd
    │   ├── env-sync.cmd
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
    │   ├── env-sync.cmd
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
        ├── env-sync.cmd
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

### Global Options

Most commands support the following global flags:

- `-v`, `--verbose`: Enable verbose output (detailed logs).
- `-vv`: Enable debug mode (prints shell commands during execution).

### Common Commands

#### `warden env-sync`

The unified synchronization command for files, media, and databases.

**Options:**

- `-h, --help` - Display help menu
- `-s, -e, --source, --environment`: Source environment (default: `staging`)
- `-d, --destination`: Destination environment (default: `local`)
- `-f, --file`: Sync source code/files
- `-m, --media`: Sync media files
- `--db`: Sync database (streaming, no local dump file created)
- `--full`: Sync everything (file, media, db)
- `-p, --path`: Sync a specific directory or file path
- `--include-product`: Include product/cache images in media sync (Magento 2 only)
- `--dry-run`: Show what would happen without making changes
- `--redeploy`: Redeploy destination after sync using `deploy.cmd` (default: disabled)
- `--delete`: Delete files on destination that are not present in source (rsync only)
- `--backup`: Create a backup of the destination database before syncing (if DB is synced)
- `--backup-dir=PATH`: Path to store backups (default: `~/backup` on destination)
- `-y, --yes`: Non-interactive mode

**Examples:**

1. **Sync Database (Remote to Local)**

   ```bash
   # Pull database from staging (default) to local
   warden env-sync --db

   # Pull database from prod to local
   warden env-sync -s prod --db
   ```

2. **Sync Media (Remote to Local)**

   ```bash
   # Pull media files from staging to local
   warden env-sync --media

   # Delete local files that are missing on remote (mirroring)
   warden env-sync --media --delete
   ```

3. **Sync Files/Code (Local to Remote)**

   ```bash
   # Push local changes to dev environment
   warden env-sync -d dev --file

   # Push a specific file
   warden env-sync -d dev -p app/etc/config.php
   ```

4. **Sync Specific Path (Remote to Remote)**

   ```bash
   # Sync a specific log folder from prod to staging
   warden env-sync -s prod -d staging -p var/log/
   ```

5. **Full Synchronization**

   ```bash
   # Sync everything: DB, Media, Files
   warden env-sync --full
   ```

6. **Dry Run**

   ```bash
   # See what would happen without actually syncing
   warden env-sync --media --delete --dry-run
   ```

> [!IMPORTANT]
> Operations to remote environments (where neither source nor destination is `local`) use **SSH Agent Forwarding**.
>
> - The local machine connects to the Source.
> - The Source connects to the Destination using **your local keys**.
> - **Requirement:** You must have your SSH keys loaded locally (`ssh-add -l`). If empty, run `ssh-add`.

### Magento 2 Commands

#### Magento 2: `warden bootstrap`

Initialize a new Magento 2 environment with all dependencies and configuration.

**Clone Options:**

- `-c, --clone` - Clone project from remote (source + DB + media)
- `--code-only` - With --clone: skip DB and media sync

**Install Options:**

- `--fresh` - Create fresh Magento project (aliases: `--clean-install`, `--fresh-install`)
- `--version, --meta-version=<version>` - Magento version for fresh install (e.g., 2.4.8)
- `--meta-package=<package>` - Magento package name (default: `magento/project-community-edition`)
- `--mage-username=<username>` - Magento Marketplace Public Key
- `--mage-password=<password>` - Magento Marketplace Private Key
- `--include-sample` - Include sample data (fresh install/bootstrap)
- `--hyva-install` - Install Hyvä theme (fresh install)

**Skip Options:**

- `--no-db` - Skip database import
- `--no-media` - Skip media sync from remote
- `--no-composer` - Skip composer install
- `--no-admin` - Skip admin user creation
- `--no-stream-db` - Use intermediate dump file instead of streaming

**Other Options:**

- `-e, --environment=<env>` - Source environment (staging, prod, dev). Default: staging
- `--db-dump=<file>` - Use specific local database dump file for import
- `--fix-deps` - Auto-fix dependency versions (PHP, Redis, etc.) based on Magento version
- `-y, --yes` - Non-interactive mode

**Example:**

```bash
# Standard bootstrap from staging
warden bootstrap

# Clone project from prod (one-command setup)
warden bootstrap -c -e prod

# Clone code only, skip DB and media
warden bootstrap -c --code-only -e staging

# Fresh Magento installation
warden bootstrap --fresh --version=2.4.8
```

#### Magento 2: `warden db-dump`

Create a database backup with optional compression.

**Options:**

- `-h, --help` - Display help menu
- `-f, --file=<file>` - Output file path
- `-e, --environment=<env>` - Specific environment (local, dev, staging, prod). Default: local
- `--full` - Export full database (no table exclusions)
- `--exclude-sensitive-data` - Exclude sensitive data (customers, orders, etc.)
- `--local` - Download the dump to your local machine (host) instead of storing it on the remote server.
  (Applies only when dumping from remote environments; default behavior for remote is to store at `~/backup/` on the server).

**Example:**

```bash
warden db-dump
warden db-dump --file=prod-backup.sql.gz -e prod
warden db-dump --exclude-sensitive-data
```

#### Magento 2: `warden db-import`

Import database from local or remote file.

**Options:**

- `-h, --help` - Display help menu
- `-f, --file=<file>` - Path to existing database dump file (can be gzipped)
- `--stream-db` - Stream database directly from remote environment (no local file)
- `-e, --environment=<env>` - Remote environment to stream from (used with `--stream-db`)

**Example:**

```bash
warden db-import --file=backup.sql.gz
warden db-import -f /path/to/database.sql
```

#### Magento 2: `warden deploy`

Deploy Magento application (run setup:upgrade, compile, deploy).

**Options:**

- `-h, --help` - Display help menu
- `-e, --environment=<env>` - Environment to deploy to. Default: local
- `-j, --jobs=<n>` - Number of parallel jobs for static content (default: 4)
- `-o, --only-static` - Deploy static content only (skip composer, upgrade, compile)
- `--deployer` - Use Deployer strategy (equivalent to `--strategy=deployer`)
- `--strategy=<type>` - Deployment strategy: `native` (default) or `deployer`
- `--deployer-config=<path>` - Path to custom `deploy.php` or `deploy.yaml`

**Example:**

```bash
warden deploy
warden deploy --jobs=8
warden deploy --only-static

# Deployer Strategy
warden deploy --deployer
warden deploy -e staging --strategy=deployer
warden deploy --deployer-config=custom/deploy.php
```

#### Deployer Strategy

You can use [Deployer](https://deployer.org/) to handle deployments by passing the `--deployer` flag or using `--strategy=deployer`.

- **Automatic Detection:** Warden looks for `deploy.php` or `deploy.yaml`.
- **Global Installation:** If `dep` is not in your project, Warden installs it globally within the container.
- **SSH Config:** Host key verification is automatically handled.
- **Environment Matching:** The `-e` environment name (e.g., `staging`) is passed directly to Deployer as the stage name.

#### Magento 2: `warden open`

Open Magento services in browser or establish tunnels.

**Options:**

- `-h, --help` - Display help menu
- `-e, --environment=<env>` - Specific environment (local, dev, staging, prod). Default: local

**Arguments:**

- `db` - Open database connection (tunnels to remote if environment specified)
- `shell` - Open container shell (or SSH to remote)
- `sftp` - Open SFTP connection
- `admin` - Open admin panel in browser
- `elasticsearch` - Open Elasticsearch/OpenSearch

**Other Options:**

- `-a, --xdg-open` - Automatically open in browser/client

**Example:**

```bash
warden open
warden open admin
warden open -e staging
```

#### Magento 2: `warden set-config`

Automatically configure Magento settings to optimize for the Warden development environment.

**Features:**

- Sets base URLs to match Traefik configuration.
- Configures Varnish, Redis, and OpenSearch/Elasticsearch based on `.env` settings.
- Disables security features for easier development (2FA, reCAPTCHA, etc.).
- Enables developer mode.
- Supports custom hooks via `.warden/hooks`.

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
- `--skip-env-update` - Skip environment dependency updates (automatic `fix-deps`)

**Example:**

```bash
warden upgrade --version=2.4.8
warden upgrade --version=2.4.8 --dry-run
warden upgrade --version=2.4.8-p3 --skip-db-upgrade
```

#### Magento 2: `warden fix-deps`

Automatically detect and update environment dependency versions (PHP, MySQL, Redis, etc.) in `.env` based on the Magento version.

**Options:**

- `-v, --version=VERSION` - Specify Magento version manually (e.g., 2.4.8)
- `--dry-run` - Preview changes without modifying `.env`

**Example:**

```bash
warden fix-deps --version=2.4.8
warden fix-deps --dry-run
```

### Laravel Commands

#### Laravel: `warden bootstrap`

Initialize Laravel environment with dependencies and database.

**Clone Options:**

- `-c, --clone` - Clone project from remote (source + DB)
- `--code-only` - With --clone: skip DB sync

**Install Options:**

- `--fresh` - Create fresh Laravel project
- `--fix-deps` - Auto-fix dependency versions

**Skip Options:**

- `--no-db` - Skip database import
- `--no-composer` - Skip composer install
- `--no-migrate` - Skip database migrations
- `--no-stream-db` - Use intermediate dump file instead of streaming

**Other Options:**

- `-e, --environment=<env>` - Source environment (staging, prod, dev). Default: staging
- `--db-dump=<file>` - Use specific local database dump file for import
- `-y, --yes` - Non-interactive mode

**Example:**

```bash
warden bootstrap                    # Standard bootstrap
warden bootstrap -c -e prod         # Clone from prod
warden bootstrap --fresh            # Create new Laravel project
```

#### Laravel: `warden db-dump`

Dump database from a remote Laravel environment.

**Options:**

- `-h, --help` - Display help menu
- `-e, --environment=<env>` - Specific environment (local, dev, staging, prod). Default: local
- `-f, --file=<file>` - Output file path
- `--exclude-sensitive-data` - Exclude sensitive data from the dump
- `--local` - Download remote dump to local machine (default: store on remote at `~/backup/`)

**Example:**

```bash
warden db-dump -e dev --local
warden db-dump --file=prod-backup.sql.gz -e prod
```

#### Laravel: `warden db-import`

Import database dump into Laravel project.

**Options:**

- `-h, --help` - Display help menu
- `-f, --file=<file>` - Path to existing database dump file (can be gzipped)
- `--stream-db` - Stream database directly from remote environment (no local file)
- `-e, --environment=<env>` - Remote environment to stream from (used with `--stream-db`)

**Example:**

```bash
warden db-import --file=backup.sql.gz
warden db-import --stream-db -e staging
```

#### Laravel: `warden open`

Open Laravel services (local or remote).

**Options:**

- `-h, --help` - Display help menu
- `-e, --environment=<env>` - Specific environment (local, dev, staging, prod). Default: local
- `-a, --xdg-open` - Automatically open in browser/client

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

#### Laravel: `warden deploy`

Deploy Laravel locally. Supports native strategy and Deployer.

**Options:**

- `-h, --help` - Display help menu
- `-e, --environment=<env>` - Environment to deploy to. Default: local
- `-o, --only-static` - Deploy static assets only (storage:link) and run hooks
- `--deployer` - Use Deployer strategy (equivalent to `--strategy=deployer`)
- `--strategy=<type>` - Deployment strategy: `native` (default) or `deployer`
- `--deployer-config=<path>` - Path to custom `deploy.php` or `deploy.yaml`

**Example:**

```bash
warden deploy
warden deploy --deployer
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

**Clone Options:**

- `-c, --clone` - Clone project from remote (source + DB)
- `--code-only` - With --clone: skip DB sync

**Install Options:**

- `--fresh` - Create fresh Symfony project
- `--fix-deps` - Auto-fix dependency versions

**Skip Options:**

- `--no-db` - Skip database import
- `--no-composer` - Skip composer install
- `--no-migrate` - Skip database migrations
- `--no-stream-db` - Use intermediate dump file instead of streaming

**Other Options:**

- `-e, --environment=<env>` - Source environment (staging, prod, dev). Default: staging
- `--db-dump=<file>` - Use specific local database dump file for import
- `-y, --yes` - Non-interactive mode

**Example:**

```bash
warden bootstrap                    # Standard bootstrap
warden bootstrap -c -e prod         # Clone from prod
warden bootstrap --fresh            # Create new Symfony project
```

#### Symfony: `warden db-dump`

Dump database from a remote Symfony environment.

**Options:**

- `-h, --help` - Display help menu
- `-e, --environment=<env>` - Specific environment (local, dev, staging, prod). Default: local
- `-f, --file=<file>` - Output file path
- `--exclude-sensitive-data` - Exclude sensitive data from the dump
- `--local` - Download remote dump to local machine (default: store on remote at `~/backup/`)

**Example:**

```bash
warden db-dump -e dev --local
warden db-dump --file=prod-backup.sql.gz -e prod
```

#### Symfony: `warden db-import`

Import database dump into Symfony project.

**Options:**

- `-h, --help` - Display help menu
- `-f, --file=<file>` - Path to existing database dump file (can be gzipped)
- `--stream-db` - Stream database directly from remote environment (no local file)
- `-e, --environment=<env>` - Remote environment to stream from (used with `--stream-db`)

**Example:**

```bash
warden db-import --file=backup.sql.gz
warden db-import --stream-db -e staging
```

#### Symfony: `warden open`

Open Symfony services (local or remote).

**Options:**

- `-h, --help` - Display help menu
- `-e, --environment=<env>` - Specific environment (local, dev, staging, prod). Default: local
- `-a, --xdg-open` - Automatically open in browser/client

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

#### Symfony: `warden deploy`

Deploy Symfony locally. Supports native strategy and Deployer.

**Options:**

- `-h, --help` - Display help menu
- `-e, --environment=<env>` - Environment to deploy to. Default: local
- `-o, --only-static` - Deploy assets only (skip composer, migrations)
- `--deployer` - Use Deployer strategy (equivalent to `--strategy=deployer`)
- `--strategy=<type>` - Deployment strategy: `native` (default) or `deployer`
- `--deployer-config=<path>` - Path to custom `deploy.php` or `deploy.yaml`

**Example:**

```bash
warden deploy
warden deploy --deployer
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

**Clone Options:**

- `-c, --clone` - Clone project from remote (source + DB)
- `--code-only` - With --clone: skip DB sync

**Install Options:**

- `--fresh` - Download fresh WordPress installation
- `--fix-deps` - Auto-fix dependency versions

**Skip Options:**

- `--no-db` - Skip database import
- `--no-composer` - Skip composer install
- `--no-wp-install` - Skip WordPress installation wizard
- `--no-stream-db` - Use intermediate dump file instead of streaming

**Other Options:**

- `-e, --environment=<env>` - Source environment (staging, prod, dev). Default: staging
- `--db-dump=<file>` - Use specific local database dump file for import
- `-y, --yes` - Non-interactive mode

**Example:**

```bash
warden bootstrap                    # Standard bootstrap
warden bootstrap -c -e prod         # Clone from prod
warden bootstrap --fresh            # Download fresh WordPress
```

**Note:** With `--fresh`, WordPress will be downloaded, wp-config.php created, and the site installed with admin credentials displayed.

#### WordPress: `warden db-dump`

Dump database from a remote WordPress environment.

**Options:**

- `-h, --help` - Display help menu
- `-e, --environment=<env>` - Specific environment (local, dev, staging, prod). Default: local
- `-f, --file=<file>` - Output file path
- `--exclude-sensitive-data` - Exclude sensitive data from the dump
- `--local` - Download remote dump to local machine (default: store on remote at `~/backup/`)

**Example:**

```bash
warden db-dump -e dev --local
warden db-dump --file=prod-backup.sql.gz -e prod
```

#### WordPress: `warden db-import`

Import database dump into WordPress.

**Options:**

- `-h, --help` - Display help menu
- `-f, --file=<file>` - Path to existing database dump file (can be gzipped)
- `--stream-db` - Stream database directly from remote environment (no local file)
- `-e, --environment=<env>` - Remote environment to stream from (used with `--stream-db`)

**Example:**

```bash
warden db-import --file=backup.sql.gz
warden db-import --stream-db -e staging
```

**Note:** After import, use WP-CLI to search-replace URLs if needed:

```bash
warden env exec php-fpm wp search-replace 'old-domain.com' 'app.test.test'
```

#### WordPress: `warden open`

Open WordPress services (local or remote).

**Options:**

- `-h, --help` - Display help menu
- `-e, --environment=<env>` - Specific environment (local, dev, staging, prod). Default: local
- `-a, --xdg-open` - Automatically open in browser/client

**Arguments:** `db`, `shell`, `sftp`, `admin`, `elasticsearch`

**Example:**

```bash
warden open db
warden open -e staging admin
```

#### WordPress: `warden deploy`

Deploy WordPress locally. Supports native strategy and Deployer.

**Options:**

- `-h, --help` - Display help menu
- `-e, --environment=<env>` - Environment to deploy to. Default: local
- `-o, --only-static` - Deploy static assets only (flush cache) and run hooks
- `--deployer` - Use Deployer strategy (equivalent to `--strategy=deployer`)
- `--strategy=<type>` - Deployment strategy: `native` (default) or `deployer`
- `--deployer-config=<path>` - Path to custom `deploy.php` or `deploy.yaml`

**Example:**

```bash
warden deploy
warden deploy --deployer
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

Update both **Warden Core** and these **Custom Commands** to the latest versions. It also applies necessary patches to Warden to ensure compatibility.

**Options:**

- `-f, --force`: Force update, overwriting local changes (uncommitted files).
- `--dry-run`: Simulate the update process without making changes.

**Example:**

```bash
warden self-update
warden self-update --dry-run
warden self-update --force
```

#### `warden setup-remotes`

Interactive wizard to configure remote environment connection details (Dev, Staging) in your `.env` file.

**Features:**

- Interactive prompts for Host, User, Port, and Path.
- Auto-validation of SSH connectivity.
- Updates/Creates `.env` entries safely.

**Example:**

```bash
warden setup-remotes
warden setup-remotes --help
```

#### `warden remote-exec`

Run arbitrary commands on a remote environment via SSH.

**Options:**

- `-h, --help` - Display help menu
- `-e, --environment` - Remote environment to execute on (default: `staging`)
- `-v, --verbose` - Print the command execution details for debugging

**Example:**

```bash
# Run command on staging (default)
warden remote-exec bin/magento cache:flush

# Run command on prod
warden remote-exec -e prod bin/magento indexer:reindex
```

## Adding New Environment Support

To add support for a new framework (e.g., Drupal):

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
DB_DATABASE=laravel
DB_USERNAME=laravel
DB_PASSWORD=laravel
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

## Testing

This project includes a comprehensive testing suite (Unit & Integration) based on Docker. It simulates multiple environments (`-local`, `-dev`, `-staging`) to verify the `warden` custom commands across different frameworks.

Detailed instructions can be found in [tests/README.md](tests/README.md).

### Quick Start

```bash
# Run all tests for Magento 2 (Unit + Integration)
./tests/run-tests.sh magento2

# Run only unit tests
./tests/run-tests.sh magento2 --unit-only
```

The runner will automatically:

1. Detect container IPs for dynamic environments.
2. Isolate the SSH environment to prevent conflicts with your host's ssh-agent.
3. Distribute safe test keys between containers.
4. Execute all test suites (files, media, db, custom paths, R2R, error handling).

## Contributing

1. Create a feature branch
2. Make your changes
3. Test with different environment types
4. Submit a pull request

## License

GNU General Public License v3.0
