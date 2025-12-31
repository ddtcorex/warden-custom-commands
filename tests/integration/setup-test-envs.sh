#!/usr/bin/env bash
# setup-test-envs.sh - Set up test environments for integration testing

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${TEST_DIR}/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     Setting Up Test Environments                           ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"

# ─────────────────────────────────────────────────────────────────────────────
# Step 1: Create test environment directories
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${YELLOW}Step 1: Creating test directories...${NC}"

for env in project-local project-dev project-staging; do
    mkdir -p "${TEST_DIR}/${env}"
    echo "  Created: tests/${env}/"
done

# ─────────────────────────────────────────────────────────────────────────────
# Step 2: Initialize Warden environments
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${YELLOW}Step 2: Initializing Warden environments...${NC}"

for env in project-local project-dev project-staging; do
    cd "${TEST_DIR}/${env}"
    if [[ -f ".env" ]]; then
        echo "  ${env}: Already initialized, skipping"
    else
        yes | warden env-init "${env}" magento2 > /dev/null 2>&1
        echo "  ${env}: Initialized"
    fi
done

# ─────────────────────────────────────────────────────────────────────────────
# Step 3: Configure .env files with REMOTE_* variables
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${YELLOW}Step 3: Configuring environment variables...${NC}"

# Add REMOTE_* variables to project-local for sync testing
cat >> "${TEST_DIR}/project-local/.env" << 'EOF'

# Remote Environments for Sync Testing
WARDEN_SSH_IDENTITIES_ONLY=1

REMOTE_DEV_HOST=project-dev-php-fpm-1
REMOTE_DEV_USER=www-data
REMOTE_DEV_PORT=22
REMOTE_DEV_PATH=/var/www/html

REMOTE_STAGING_HOST=project-staging-php-fpm-1
REMOTE_STAGING_USER=www-data
REMOTE_STAGING_PORT=22
REMOTE_STAGING_PATH=/var/www/html
EOF
echo "  project-local: Added REMOTE_* variables"

# ─────────────────────────────────────────────────────────────────────────────
# Step 4: Start environments
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${YELLOW}Step 4: Starting environments...${NC}"

for env in project-local project-dev project-staging; do
    cd "${TEST_DIR}/${env}"
    warden env up -d > /dev/null 2>&1
    echo "  ${env}: Started"
done

# Wait for containers to be ready
echo "  Waiting for containers to be ready..."
sleep 10

# ─────────────────────────────────────────────────────────────────────────────
# Step 5: Install SSH server on remote environments
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${YELLOW}Step 5: Installing SSH server on dev/staging...${NC}"

for env in project-dev project-staging; do
    cd "${TEST_DIR}/${env}"
    warden env exec php-fpm bash -c "sudo dnf install -y openssh-server > /dev/null 2>&1 && sudo ssh-keygen -A > /dev/null 2>&1 && sudo /usr/sbin/sshd" 2>/dev/null || true
    echo "  ${env}: SSH server installed"
done

# ─────────────────────────────────────────────────────────────────────────────
# Step 6: Generate SSH keys and distribute
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${YELLOW}Step 6: Configuring SSH keys...${NC}"

# Generate SSH keys in all environments and distribute to all
for env in project-local project-dev project-staging; do
    cd "${TEST_DIR}/${env}"
    warden env exec php-fpm bash -c "[ -f ~/.ssh/id_rsa ] || ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa > /dev/null 2>&1"
    echo "  ${env}: SSH key generated"
done

# Get public keys
LOCAL_PUBKEY=$(docker exec project-local-php-fpm-1 cat /home/www-data/.ssh/id_rsa.pub)
DEV_PUBKEY=$(docker exec project-dev-php-fpm-1 cat /home/www-data/.ssh/id_rsa.pub)
STAGING_PUBKEY=$(docker exec project-staging-php-fpm-1 cat /home/www-data/.ssh/id_rsa.pub)
HOST_PUBKEY=$(cat ~/.ssh/id_rsa.pub)

# Distribute all to all (including host key)
# Note: authorized_keys will contain all four keys
for container in project-local-php-fpm-1 project-dev-php-fpm-1 project-staging-php-fpm-1; do
    docker exec "${container}" bash -c "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '${LOCAL_PUBKEY}' >> ~/.ssh/authorized_keys && echo '${DEV_PUBKEY}' >> ~/.ssh/authorized_keys && echo '${STAGING_PUBKEY}' >> ~/.ssh/authorized_keys && echo '${HOST_PUBKEY}' >> ~/.ssh/authorized_keys && sort -u ~/.ssh/authorized_keys -o ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
done
echo "  All environments: Public keys (including host) distributed cross-container"

# ─────────────────────────────────────────────────────────────────────────────
# Step 7: Connect Docker networks
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${YELLOW}Step 7: Connecting Docker networks...${NC}"

docker network connect project-dev_default project-local-php-fpm-1 2>/dev/null || true
docker network connect project-staging_default project-local-php-fpm-1 2>/dev/null || true
echo "  Networks connected"

# ─────────────────────────────────────────────────────────────────────────────
# Step 8: Configure sshd and restart
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${YELLOW}Step 8: Configuring SSH daemon...${NC}"

for env in project-dev project-staging; do
    cd "${TEST_DIR}/${env}"
    warden env exec php-fpm bash -c "sudo sed -i 's/#PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config && sudo sed -i 's/#MaxStartups.*/MaxStartups 100:30:200/' /etc/ssh/sshd_config && sudo pkill sshd; sudo /usr/sbin/sshd" 2>/dev/null || true
    echo "  ${env}: SSH daemon configured"
done

# ─────────────────────────────────────────────────────────────────────────────
# Step 9: Create test directories
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${YELLOW}Step 9: Creating test directories in containers...${NC}"

for container in project-local-php-fpm-1 project-dev-php-fpm-1 project-staging-php-fpm-1; do
    docker exec "${container}" bash -c "mkdir -p /var/www/html/pub/media /var/www/html/app/code" 2>/dev/null || true
done
echo "  Test directories created"

# ─────────────────────────────────────────────────────────────────────────────
# Verify Setup
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${YELLOW}Verifying Setup...${NC}"

# Test SSH connectivity
cd "${TEST_DIR}/project-local"
if warden env exec php-fpm ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o IdentitiesOnly=yes -o ConnectTimeout=5 www-data@project-dev-php-fpm-1 "echo ok" 2>/dev/null | grep -q ok; then
    echo -e "  ${GREEN}✓${NC} SSH to project-dev: OK"
else
    echo -e "  ${RED}✗${NC} SSH to project-dev: FAILED"
fi

if warden env exec php-fpm ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o IdentitiesOnly=yes -o ConnectTimeout=5 www-data@project-staging-php-fpm-1 "echo ok" 2>/dev/null | grep -q ok; then
    echo -e "  ${GREEN}✓${NC} SSH to project-staging: OK"
else
    echo -e "  ${RED}✗${NC} SSH to project-staging: FAILED"
fi

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     Setup Complete!                                        ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Run tests with: ./tests/integration/run-tests.sh"
echo ""
