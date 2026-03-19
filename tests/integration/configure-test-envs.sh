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

# Step 1-3: Skipped (Initialization is handled by setup-test-envs.sh)

# Step 4: Configuring environment variables...
echo ""
echo "Step 4: Configuring environment variables..."

# Detect IPs for host-to-container connectivity
LOCAL_CONTAINER="${ENV_TYPE}-local-php-fpm-1"
DEV_CONTAINER="${ENV_TYPE}-dev-php-fpm-1"
STAGING_CONTAINER="${ENV_TYPE}-staging-php-fpm-1"

LOCAL_DB="${ENV_TYPE}-local-db-1"
DEV_DB="${ENV_TYPE}-dev-db-1"
STAGING_DB="${ENV_TYPE}-staging-db-1"

# Wait for containers to be ready
echo "  Waiting for containers to be ready..."
sleep 5

DEV_IP_DETECTED=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' "${DEV_CONTAINER}" | awk '{print $1}')
STAGING_IP_DETECTED=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' "${STAGING_CONTAINER}" | awk '{print $1}')

# Clean up existing REMOTE variables to prevent duplication
sed -i '/^WARDEN_SSH_IDENTITIES_ONLY=/d' "${TEST_DIR}/${ENV_TYPE}-local/.env"
sed -i '/^WARDEN_SSH_OPTS=/d' "${TEST_DIR}/${ENV_TYPE}-local/.env"
sed -i '/^REMOTE_DEV_/d' "${TEST_DIR}/${ENV_TYPE}-local/.env"
sed -i '/^REMOTE_STAGING_/d' "${TEST_DIR}/${ENV_TYPE}-local/.env"

# Use unquoted EOF to allow variable expansion
cat >> "${TEST_DIR}/${ENV_TYPE}-local/.env" << EOF

# Remote Environments for Sync Testing
WARDEN_SSH_IDENTITIES_ONLY=1
WARDEN_SSH_OPTS="-o IdentityAgent=none -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

REMOTE_DEV_HOST=${DEV_IP_DETECTED}
REMOTE_DEV_USER=www-data
REMOTE_DEV_PORT=22
REMOTE_DEV_PATH=/var/www/html

REMOTE_STAGING_HOST=${STAGING_IP_DETECTED}
REMOTE_STAGING_USER=www-data
REMOTE_STAGING_PORT=22
REMOTE_STAGING_PATH=/var/www/html
EOF
echo "  ${ENV_TYPE}-local: Added REMOTE_* variables (Dev IP: ${DEV_IP_DETECTED}, Staging IP: ${STAGING_IP_DETECTED})"

# Step 5: SSH Server (Parallel)
echo ""
echo "Step 5: Installing SSH server on dev/staging..."
pids=""
for container in "${STAGING_CONTAINER}" "${DEV_CONTAINER}"; do
    (
        # Handle CentOS 8 Stream EOL mirror changes if needed
        if docker exec -u root "${container}" [ -f /etc/os-release ] && docker exec -u root "${container}" grep -q "VERSION_ID=\"8\"" /etc/os-release; then
             docker exec -u root "${container}" bash -c "sed -i 's/mirrorlist/#mirrorlist/g' /etc/yum.repos.d/CentOS-Stream-* && sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-Stream-* && dnf clean all" >/dev/null 2>&1
        fi
        
        docker exec --workdir / -u root "${container}" bash -c "dnf install -y openssh-server > /dev/null 2>&1 && ssh-keygen -A > /dev/null 2>&1 && mkdir -p /run/sshd && /usr/sbin/sshd" 2>/dev/null || true
        echo "  ${container}: SSH server installed and started"
    ) &
    pids="$pids $!"
done
wait $pids

# Step 6: Keys
echo ""
echo "Step 6: Configuring SSH keys..."
pids=""
for container in "${LOCAL_CONTAINER}" "${DEV_CONTAINER}" "${STAGING_CONTAINER}"; do
    (
        docker exec --workdir / -u www-data "${container}" bash -c "[ -f ~/.ssh/id_rsa ] || ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa > /dev/null 2>&1"
        docker exec --workdir / -u www-data "${container}" bash -c "echo 'Host *' > ~/.ssh/config && echo '    IdentityAgent none' >> ~/.ssh/config && echo '    StrictHostKeyChecking no' >> ~/.ssh/config && chmod 600 ~/.ssh/config"
        echo "  ${container}: SSH key generated and configured"
    ) &
    pids="$pids $!"
done
wait $pids

LOCAL_PUBKEY=$(docker exec --workdir / "${LOCAL_CONTAINER}" cat /home/www-data/.ssh/id_rsa.pub)
DEV_PUBKEY=$(docker exec --workdir / "${DEV_CONTAINER}" cat /home/www-data/.ssh/id_rsa.pub)
STAGING_PUBKEY=$(docker exec --workdir / "${STAGING_CONTAINER}" cat /home/www-data/.ssh/id_rsa.pub)
HOST_PUBKEY=$(cat ~/.ssh/id_rsa.pub)

for container in "${LOCAL_CONTAINER}" "${DEV_CONTAINER}" "${STAGING_CONTAINER}"; do
    docker exec --workdir / -u www-data "${container}" bash -c "mkdir -p ~/.ssh && echo '${LOCAL_PUBKEY}' >> ~/.ssh/authorized_keys && echo '${DEV_PUBKEY}' >> ~/.ssh/authorized_keys && echo '${STAGING_PUBKEY}' >> ~/.ssh/authorized_keys && echo '${HOST_PUBKEY}' >> ~/.ssh/authorized_keys && sort -u ~/.ssh/authorized_keys -o ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
done
echo "  All environments: Public keys distributed"

# Step 7: Networks
echo ""
echo "Step 7: Connecting Docker networks and fixing DNS..."
docker network connect "${ENV_TYPE}-dev_default" "${LOCAL_CONTAINER}" 2>/dev/null || echo "Warning: Could not connect ${LOCAL_CONTAINER} to ${ENV_TYPE}-dev_default"
docker network connect "${ENV_TYPE}-staging_default" "${LOCAL_CONTAINER}" 2>/dev/null || echo "Warning: Could not connect ${LOCAL_CONTAINER} to ${ENV_TYPE}-staging_default"
docker network connect "${ENV_TYPE}-staging_default" "${DEV_CONTAINER}" 2>/dev/null || echo "Warning: Could not connect ${DEV_CONTAINER} to ${ENV_TYPE}-staging_default"
docker network connect "${ENV_TYPE}-dev_default" "${STAGING_CONTAINER}" 2>/dev/null || echo "Warning: Could not connect ${STAGING_CONTAINER} to ${ENV_TYPE}-dev_default"

# Fix 'db' DNS resolution to point to the correct DB container for each environment
# This is necessary because containers are connected to multiple networks where 'db' alias exists
for context in local dev staging; do
    case "${context}" in
        local) php_cont="${LOCAL_CONTAINER}"; db_cont="${LOCAL_DB}"; net="${ENV_TYPE}-local_default" ;;
        dev) php_cont="${DEV_CONTAINER}"; db_cont="${DEV_DB}"; net="${ENV_TYPE}-dev_default" ;;
        staging) php_cont="${STAGING_CONTAINER}"; db_cont="${STAGING_DB}"; net="${ENV_TYPE}-staging_default" ;;
    esac
    
    DB_IP=$(docker inspect -f "{{with index .NetworkSettings.Networks \"${net}\"}}{{.IPAddress}}{{end}}" "${db_cont}")
    if [[ -n "${DB_IP}" ]]; then
        # Add to /etc/hosts. Use a temporary file to avoid "Device or resource busy" with sed -i
        docker exec -u root "${php_cont}" bash -c "cat /etc/hosts | sed \"s/.*db$/${DB_IP} db/\" > /tmp/hosts.tmp && cat /tmp/hosts.tmp > /etc/hosts"
    fi
done

# Verify connectivity
if ! docker exec "${LOCAL_CONTAINER}" nc -z -w 2 "${DEV_CONTAINER}" 22 >/dev/null 2>&1; then
     # Try one more time with explicit IP just in case DNS is slow
     DEV_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' "${DEV_CONTAINER}" | awk '{print $1}')
     if ! docker exec "${LOCAL_CONTAINER}" nc -z -w 2 "${DEV_IP}" 22 >/dev/null 2>&1; then
         echo "Error: Network connection failed between local and dev containers."
     fi
fi

echo "  Networks connected and DNS fixed"

# Step 9: Test Dirs
echo ""
echo "Step 9: Creating test directories in containers..."
case "${ENV_TYPE}" in
    laravel) DIRS="/var/www/html/storage/app/public /var/www/html/public" ;;
    magento2) DIRS="/var/www/html/pub/media /var/www/html/app/code" ;;
    wordpress) DIRS="/var/www/html/wp-content/uploads" ;;
    *) DIRS="/var/www/html/pub/media" ;;
esac

for context in local dev staging; do
    env="${ENV_TYPE}-${context}"
    container="${env}-php-fpm-1"
    # Check for stale mount (Links: 0)
    if [[ "$(docker exec --workdir / "${container}" stat /var/www/html 2>/dev/null | grep 'Links: 0')" ]]; then
        echo "  ${container}: Stale mount detected, restarting..."
        docker restart "${container}" > /dev/null
        sleep 5
        # Re-start sshd if it was dev/staging
        if [[ "${context}" != "local" ]]; then
             docker exec --workdir / -u root "${container}" /usr/sbin/sshd 2>/dev/null || true
        fi
    fi
    docker exec --workdir / -u root "${container}" mkdir -p ${DIRS}
    docker exec --workdir / -u root "${container}" chown -R www-data:www-data /var/www/html
    
    # Initialize env.php for Magento 2
    if [[ "${ENV_TYPE}" == "magento2" ]]; then
        docker exec --workdir / -u www-data "${container}" bash -c "mkdir -p /var/www/html/app/etc && cat > /var/www/html/app/etc/env.php <<EOF
<?php
return [
    'db' => [
        'connection' => [
            'default' => [
                'host' => 'db',
                'dbname' => 'magento',
                'username' => 'magento',
                'password' => 'magento',
                'active' => '1',
            ]
        ]
    ]
];
EOF"
    fi
done
echo "  Test directories created for ${ENV_TYPE}"

# Step 8: Fix Symfony Configuration
if [[ "${ENV_TYPE}" == "symfony" ]]; then
    echo ""
    echo "Step 8: Fixing Symfony DB Configuration..."
    for context in local dev staging; do
        env="${ENV_TYPE}-${context}"
        cd "${TEST_DIR}/${env}"
        # Clean up .env
        if grep -q "^DATABASE_URL=" .env; then
             sed -i '/^DATABASE_URL=/d' .env
        fi
        
        # Recreate .env.local cleanly
        rm -f .env.local
        # Create empty if not exists
        touch .env.local
        
        echo "DATABASE_URL=\"mysql://symfony:symfony@${env}-db-1:3306/symfony?serverVersion=8.0\"" >> .env.local
        echo "  ${env}: .env updated"
    done
fi

echo ""
echo "Verifying Setup..."
# Use IP for verification to avoid hostname issues on host
DEV_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' "${DEV_CONTAINER}" | awk '{print $1}')
if docker exec --workdir / -u www-data "${LOCAL_CONTAINER}" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "${DEV_IP}" echo ok | grep -q ok; then
    echo "  ✓ SSH ${ENV_TYPE}-dev: OK"
else
    echo "  ✗ SSH ${ENV_TYPE}-dev: FAILED"
fi
