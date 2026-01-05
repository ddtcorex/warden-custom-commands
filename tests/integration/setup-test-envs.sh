#!/usr/bin/env bash
set -e

# setup-test-envs.sh - Initialize Wardens for integration testing
TEST_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ENV_TYPE="magento2"

for i in "$@"; do
    case $i in
        --type=*) ENV_TYPE="${i#*=}"; shift ;;
    esac
done

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║     Setting Up Test Environments                           ║"
echo "╚════════════════════════════════════════════════════════════╝"

# Step 1: Directories
echo ""
echo "Step 1: Creating test directories for type: ${ENV_TYPE}..."
for env in project-local project-dev project-staging; do
    mkdir -p "${TEST_DIR}/${env}"
    echo "  Created: tests/${env}/"
done

# Step 2: Initialize
echo ""
echo "Step 2: Initializing Warden environments (${ENV_TYPE})..."
for env in project-local project-dev project-staging; do
    cd "${TEST_DIR}/${env}"
    rm -f .env
    yes | warden env-init "${env}" "${ENV_TYPE}" > /dev/null 2>&1
    if ! grep -q "WARDEN_ENV_NAME" .env; then
        echo "WARDEN_ENV_NAME=${env}" >> .env
        echo "WARDEN_ENV_TYPE=${ENV_TYPE}" >> .env
    fi
    echo "  ${env}: Initialized"
done

# Step 3: Start
echo ""
echo "Step 3: Starting environments..."
for env in project-local project-dev project-staging; do
    cd "${TEST_DIR}/${env}"
    warden env up -d > /dev/null 2>&1
    echo "  ${env}: Started"
done

# Step 4: REMOTE vars
echo ""
echo "Step 4: Configuring environment variables..."

# Detect IPs for host-to-container connectivity
DEV_IP_DETECTED=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' project-dev-php-fpm-1 | awk '{print $1}')
STAGING_IP_DETECTED=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' project-staging-php-fpm-1 | awk '{print $1}')

# Use unquoted EOF to allow variable expansion
cat >> "${TEST_DIR}/project-local/.env" << EOF

# Remote Environments for Sync Testing
WARDEN_SSH_IDENTITIES_ONLY=1
WARDEN_SSH_OPTS="-o IdentityAgent=none"

REMOTE_DEV_HOST=${DEV_IP_DETECTED}
REMOTE_DEV_USER=www-data
REMOTE_DEV_PORT=22
REMOTE_DEV_PATH=/var/www/html

REMOTE_STAGING_HOST=${STAGING_IP_DETECTED}
REMOTE_STAGING_USER=www-data
REMOTE_STAGING_PORT=22
REMOTE_STAGING_PATH=/var/www/html
EOF
echo "  project-local: Added REMOTE_* variables (Dev IP: ${DEV_IP_DETECTED}, Staging IP: ${STAGING_IP_DETECTED})"

echo "  Waiting for containers to be ready..."
sleep 15

# Step 5: SSH Server
echo ""
echo "Step 5: Installing SSH server on dev/staging..."
for container in project-dev-php-fpm-1 project-staging-php-fpm-1; do
    docker exec --workdir / -u root "${container}" bash -c "dnf install -y openssh-server > /dev/null 2>&1 && ssh-keygen -A > /dev/null 2>&1 && mkdir -p /run/sshd && /usr/sbin/sshd" 2>/dev/null || true
    echo "  ${container}: SSH server installed and started"
done

# Step 6: Keys
echo ""
echo "Step 6: Configuring SSH keys..."
for container in project-local-php-fpm-1 project-dev-php-fpm-1 project-staging-php-fpm-1; do
    docker exec --workdir / -u www-data "${container}" bash -c "[ -f ~/.ssh/id_rsa ] || ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa > /dev/null 2>&1"
    docker exec --workdir / -u www-data "${container}" bash -c "echo 'Host *' > ~/.ssh/config && echo '    IdentityAgent none' >> ~/.ssh/config && echo '    StrictHostKeyChecking no' >> ~/.ssh/config && chmod 600 ~/.ssh/config"
    echo "  ${container}: SSH key generated and configured"
done

LOCAL_PUBKEY=$(docker exec --workdir / project-local-php-fpm-1 cat /home/www-data/.ssh/id_rsa.pub)
DEV_PUBKEY=$(docker exec --workdir / project-dev-php-fpm-1 cat /home/www-data/.ssh/id_rsa.pub)
STAGING_PUBKEY=$(docker exec --workdir / project-staging-php-fpm-1 cat /home/www-data/.ssh/id_rsa.pub)
HOST_PUBKEY=$(cat ~/.ssh/id_rsa.pub)

for container in project-local-php-fpm-1 project-dev-php-fpm-1 project-staging-php-fpm-1; do
    docker exec --workdir / -u www-data "${container}" bash -c "mkdir -p ~/.ssh && echo '${LOCAL_PUBKEY}' >> ~/.ssh/authorized_keys && echo '${DEV_PUBKEY}' >> ~/.ssh/authorized_keys && echo '${STAGING_PUBKEY}' >> ~/.ssh/authorized_keys && echo '${HOST_PUBKEY}' >> ~/.ssh/authorized_keys && sort -u ~/.ssh/authorized_keys -o ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
done
echo "  All environments: Public keys distributed"

# Step 7: Networks
echo ""
echo "Step 7: Connecting Docker networks..."
docker network connect project-dev_default project-local-php-fpm-1 2>/dev/null || true
docker network connect project-staging_default project-local-php-fpm-1 2>/dev/null || true
docker network connect project-staging_default project-dev-php-fpm-1 2>/dev/null || true
docker network connect project-dev_default project-staging-php-fpm-1 2>/dev/null || true
echo "  Networks connected"

# Step 9: Test Dirs
echo ""
echo "Step 9: Creating test directories in containers..."
case "${ENV_TYPE}" in
    laravel) DIRS="/var/www/html/storage/app/public /var/www/html/public" ;;
    magento2) DIRS="/var/www/html/pub/media /var/www/html/app/code" ;;
    wordpress) DIRS="/var/www/html/wp-content/uploads" ;;
    *) DIRS="/var/www/html/pub/media" ;;
esac
for env in project-local project-dev project-staging; do
    container="${env}-php-fpm-1"
    # Check for stale mount (Links: 0)
    if [[ "$(docker exec --workdir / "${container}" stat /var/www/html 2>/dev/null | grep 'Links: 0')" ]]; then
        echo "  ${container}: Stale mount detected, restarting..."
        docker restart "${container}" > /dev/null
        sleep 5
        # Re-start sshd if it was dev/staging
        if [[ "${env}" != "project-local" ]]; then
             docker exec --workdir / -u root "${container}" /usr/sbin/sshd 2>/dev/null || true
        fi
    fi
    docker exec --workdir / -u root "${container}" mkdir -p ${DIRS}
    docker exec --workdir / -u root "${container}" chown -R www-data:www-data /var/www/html
done
echo "  Test directories created for ${ENV_TYPE}"

echo ""
echo "Verifying Setup..."
# Use IP for verification to avoid hostname issues on host
DEV_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' project-dev-php-fpm-1 | awk '{print $1}')
if docker exec --workdir / -u www-data project-local-php-fpm-1 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "${DEV_IP}" echo ok | grep -q ok; then
    echo "  ✓ SSH project-dev: OK"
else
    echo "  ✗ SSH project-dev: FAILED"
fi
