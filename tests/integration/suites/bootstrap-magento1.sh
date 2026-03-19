#!/usr/bin/env bash
# suites/bootstrap-magento1.sh
#
# Integration tests for Magento 1 bootstrap command

# Source helpers if not already sourced
if [[ -z "$(type -t header)" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/../helpers.sh"
fi

if [[ "${TEST_ENV_TYPE}" != "magento1" ]]; then
    echo "Skipping Magento 1 bootstrap tests for environment type: ${TEST_ENV_TYPE}"
    return
fi

header "Bootstrap Workflow Tests (Magento 1)"

# -----------------------------------------------------
# Scenario 1: Setup Mock Environments
# Since we don't do a full Magento 1 install (which is complex for CI),
# we ensure the environments have minimal structure for other tests.
# -----------------------------------------------------
header "Scenario 1: Setup Mock Environments (Magento 1)"

for container in "${LOCAL_PHP}" "${DEV_PHP}" "${STAGING_PHP}"; do
    echo "  Configuring ${container} ..."
    # Create app/etc/local.xml (Magento 1 config)
    docker exec --workdir / -u www-data "${container}" bash -c "mkdir -p /var/www/html/app/etc && cat > /var/www/html/app/etc/local.xml <<EOF
<config>
    <global>
        <resources>
            <default_setup>
                <connection>
                    <host><![CDATA[db]]></host>
                    <username><![CDATA[magento]]></username>
                    <password><![CDATA[magento]]></password>
                    <dbname><![CDATA[magento]]></dbname>
                    <initStatements><![CDATA[SET NAMES utf8]]></initStatements>
                    <model><![CDATA[mysql4]]></model>
                    <type><![CDATA[pdo_mysql]]></type>
                    <pdoType><![CDATA[]]></pdoType>
                    <active>1</active>
                </connection>
            </default_setup>
        </resources>
    </global>
</config>
EOF"
    
    # Create index.php to mark as "installed"
    docker exec --workdir / -u www-data "${container}" touch /var/www/html/index.php
    
    # Ensure media directory exists
    docker exec --workdir / -u www-data "${container}" mkdir -p /var/www/html/media
done

pass "Magento 1 mock environments configured"
