Magento 2 & Warden Setup
========================================================
Useful URLs on DEV:

* https://traefik.warden.test/
* https://portainer.warden.test/
* https://dnsmasq.warden.test/
* https://mailhog.warden.test/

## Developer Setup

### Prerequisites:

* [Docker Desktop](https://docs.docker.com/desktop/install/mac-install/) for Mac 2.2.0.0 or later
  or [Docker for Linux](https://docs.docker.com/get-docker/)
  or [Docker for Windows](https://docs.docker.com/desktop/install/windows-install/)
* [Homebrew](https://brew.sh/) is installed.
* [Warden](https://docs.warden.dev/) 1.0.0 or later is installed. See
  the [Installing Warden](https://docs.warden.dev/installing.html) docs page for further info and procedures.

1. Install Docker and Docker Compose
    ```
    sudo apt-get update
    sudo apt-get install ca-certificates curl gnupg lsb-release
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    sudo apt-get install docker-ce docker-ce-cli containerd.io docker-compose-plugin
    sudo service docker start
    ```
2. Fix docker command permission
    ```
    sudo groupadd docker
    sudo usermod -aG docker $USER
    newgrp docker
    mkdir /home/"$USER"/.docker
    sudo chown "$USER":"$USER" /home/"$USER"/.docker -R
    sudo chmod g+rwx "$HOME/.docker" -R
    ```
3. Start docker on boot
    ```
    sudo systemctl enable docker.service
    sudo systemctl enable containerd.service
    ```
4. Install Homebrew
    ```
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    (echo; echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"') >> /home/$USER/.bashrc
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    ```
5. Install Warden
    ```
    brew install gcc
    sudo apt-get install build-essential procps curl file git
    brew install wardenenv/warden/warden
    warden svc up
    ```
6. Load the site in your browser using the links and credentials taken from the init script output.

   **Note:** If you are using **Firefox** and it warns you the SSL certificate is invalid/untrusted, go to
   Preferences -> Privacy & Security -> View Certificates (bottom of page) -> Authorities -> Import and
   select `~/.warden/ssl/rootca/certs/ca.cert.pem` for import, then reload the page.

   **Note:** If you are using **Chrome** on **Linux** and it warns you the SSL certificate is invalid/untrusted, go to
   Chrome Settings -> Privacy And Security -> Manage Certificates (see more) -> Authorities -> Import and
   select `~/.warden/ssl/rootca/certs/ca.cert.pem` for import, then reload the page.

7. Auto DNS resolution for all *.test domains in local environment
    ```
    sudo mkdir -p /etc/systemd/resolved.conf.d
    echo -e "[Resolve]\nDNS=127.0.0.1\nDomains=~test\n" | sudo tee /etc/systemd/resolved.conf.d/warden.conf > /dev/null
    sudo systemctl restart systemd-resolved
    ```

# Warden Custom Commands

Provides additional commands to simplify local installation.

### Installation
Clone this [repository](https://github.com/KaiDo92/warden-custom-commands) in `~/.warden/commands` to install it globally (recommended), or locally per project in `[project directory]/.warden/commands`.
```
git clone https://github.com/KaiDo92/warden-custom-commands.git ~/.warden/commands
```

### Configuration
In the project `.env` (after `warden env-init`), add and configure these values:

```
REMOTE_PROD_HOST=project.com
REMOTE_PROD_USER=user
REMOTE_PROD_PORT=22
REMOTE_PROD_PATH=/var/www/html

REMOTE_STAGING_HOST=staging.project.com
REMOTE_STAGING_USER=user
REMOTE_STAGING_PORT=22
REMOTE_STAGING_PATH=/var/www/html

REMOTE_DEV_HOST=dev.project.com
REMOTE_DEV_USER=user
REMOTE_DEV_PORT=22
REMOTE_DEV_PATH=/var/www/html
```

#### Adobe Commerce Cloud
The `REMOTE_[env]_HOST` variables must be set with the name of the environment. All other variables are not used and can be removed.

Additionally, you must have this variable:  
`CLOUD_PROJECT=[projectId]`

### Usage

For all commands, execute `warden <command> -h` to see the details of all options.

`warden self-update`
* Pull the latest update
* Apply fixes and improvements

`warden bootstrap`
* Create and configure Warden environment
* Download and import database dump from selected remote
* Download medias from selected remote
* Install composer dependencies
* Configure Redis, Varnish and ElasticSearch if applicable
* Other Magento config like domain, switch some payment methods to sandbox
* Create admin user

`warden db-dump`
* Dump DB from selected remote

`warden db-import`
* Import DB. File **must** be specified with option `--file`

`warden sync-media`
* Download medias from selected remote
* Product images are not downloaded by default (use `--include-product`)

`warden open`
* Open DB tunnel to local or remote environments
* SSH to local or remote environments
* Show SFTP link you can use in your SFTP client

`warden download-source`
* Download all source code from selected remote

`warden download-files`
* Download files from selected remote

`warden upload-files`
* Upload files to selected remote

`warden set-config`
* Update Magento configurations

### Initializing Environment

In the below examples `~/Work/htdocs/magento` is used as the path. Simply replace this with whatever path you will be
running this project from. It is recommended however to deploy the project locally to a case-sensitive volume.

1. Clone the project codebase.
    ```
    git clone -b develop git@github.com:<GITHUB_ACCOUNT>/<REPOSITORY_NAME>.git ~/Work/htdocs/magento
    ```
2. Change into the project directory.
    ```
    cd ~/Work/htdocs/magento
    ```

3. Create a new .env file in the project's root directory and ensure that you update the necessary variables accordingly (please refer to the .env.example file in this repository for guidance).

4. Run the init script to bootstrap the environment.
    ```
    warden bootstrap
    ```

### Additional Configuration

Information on configuring and using tools such as Xdebug, LiveReload, MFTF, and multi-domain site setups may be found
in the Warden docs page on [Configuration](https://docs.warden.dev/configuration.html).

### Destroying Environment

To completely destroy the local environment we just created, run `warden env down -v` to tear down the project’s Docker
containers, volumes, and (where applicable) cleanup the Mutagen sync session.
