# Helper function to get DB credentials from Magento 1 local.xml (Local or Remote)
# Usage: get_db_info ["local"|env_name] ["REMOTE_DIR"]
# Returns: newline-separated list of DB_VAR=VALUE
function get_db_info() {
    local env_name="${1:-local}"
    local remote_dir="${2:-}"
    
    # Isolate local vs remote directory defaults
    if [[ -z "${remote_dir}" ]]; then
        if [[ "${env_name}" == "local" ]]; then
            remote_dir="/var/www/html"
        else
            remote_dir="${ENV_SOURCE_DIR:-/var/www/html}"
        fi
    fi

    # Determine PHP command for local decoding (on the host)
    local php_host_cmd="php"
    if ! command -v php &> /dev/null; then
        if command -v warden &> /dev/null; then
             php_host_cmd="warden env exec -T php-fpm php"
        else
             printf "Error: 'php' command not found locally and 'warden' not available for fallback.\n" >&2
             return 1
        fi
    fi

    # PHP code to extract from local.xml
    local php_extract_code="
\$f = '${remote_dir}/app/etc/local.xml';
if (!file_exists(\$f)) { fwrite(STDERR, \"File not found: \$f\n\"); exit(1); }
\$x = @simplexml_load_file(\$f); 
if (!\$x) { fwrite(STDERR, \"Failed to parse XML from \$f\n\"); exit(1); }
\$c = \$x->global->resources->default_setup->connection; 
if (!\$c) { fwrite(STDERR, \"Could not find connection node in \$f\n\"); exit(1); }
echo base64_encode(json_encode([
    'host' => (string)\$c->host,
    'username' => (string)\$c->username,
    'password' => (string)\$c->password,
    'dbname' => (string)\$c->dbname
]));"

    local db_info_json
    if [[ "${env_name}" == "local" ]]; then
        db_info_json=$(warden env exec -T php-fpm php -r "${php_extract_code}" 2>&1) || {
            printf "❌ \033[31mLocal extraction failed:\033[0m\n%s\n" "${db_info_json}" >&2
            return 1
        }
    else
        # Remote environment via SSH (normalized details should be available in env)
        local norm_env=$(normalize_env_name "${env_name}")
        local host_var="REMOTE_${norm_env}_HOST"
        local port_var="REMOTE_${norm_env}_PORT"
        local user_var="REMOTE_${norm_env}_USER"
        
        local r_host="${!host_var:-}"
        local r_port="${!port_var:-22}"
        local r_user="${!user_var:-}"
        
        if [[ -z "${r_host}" ]]; then
            return 1
        fi
        
        local php_b64
        php_b64=$(printf '%s' "${php_extract_code}" | base64 -w 0)
        db_info_json=$(ssh ${SSH_OPTS:-} -o IdentityAgent=none -p "${r_port}" "${r_user}@${r_host}" "php -r 'eval(base64_decode(\"${php_b64}\"));'" 2>&1) || {
            printf "❌ \033[31mSSH failed or remote PHP error:\033[0m\n%s\n" "${db_info_json}" >&2
            return 1
        }
    fi

    if [[ -z "${db_info_json}" ]]; then
        return 1
    fi

    # Decode locally using determined php command
    local db_host=$(${php_host_cmd} -r "\$a = json_decode(base64_decode(\$argv[1]), true); echo strpos(\$a['host'] ?? 'db', ':') === false ? (\$a['host'] ?? 'db') : explode(':', \$a['host'])[0];" -- "${db_info_json}")
    local db_port=$(${php_host_cmd} -r "\$a = json_decode(base64_decode(\$argv[1]), true); echo strpos(\$a['host'] ?? '', ':') === false ? '3306' : explode(':', \$a['host'])[1];" -- "${db_info_json}")
    local db_user=$(${php_host_cmd} -r "\$a = json_decode(base64_decode(\$argv[1]), true); echo \$a['username'] ?? '';" -- "${db_info_json}")
    local db_pass=$(${php_host_cmd} -r "\$a = json_decode(base64_decode(\$argv[1]), true); echo \$a['password'] ?? '';" -- "${db_info_json}")
    local db_name=$(${php_host_cmd} -r "\$a = json_decode(base64_decode(\$argv[1]), true); echo \$a['dbname'] ?? '';" -- "${db_info_json}")

    echo "DB_HOST=${db_host}"
    echo "DB_PORT=${db_port}"
    echo "DB_USERNAME=${db_user}"
    echo "DB_PASSWORD=${db_pass}"
    echo "DB_DATABASE=${db_name}"
}

# Standalone helper to get DB credentials from a remote Magento 1 local.xml via SSH
# Usage: get_remote_db_info "REMOTE_DIR" ["ENV_NAME"]
# Returns: newline-separated list of DB_VAR=VALUE
# NOTE: Self-contained — does NOT call get_db_info() (mirrors magento2 pattern)
function get_remote_db_info() {
    local remote_dir="${1:-${ENV_SOURCE_DIR:-/var/www/html}}"
    local env_name="${2:-${ENV_SOURCE}}"

    # Determine PHP command for local decoding (on the host)
    local php_host_cmd="php"
    if ! command -v php &> /dev/null; then
        if command -v warden &> /dev/null; then
            php_host_cmd="warden env exec -T php-fpm php"
        else
            printf "Error: 'php' command not found locally and 'warden' not available for fallback.\n" >&2
            return 1
        fi
    fi

    # PHP code to extract from local.xml (base64-encoded to survive SSH quoting)
    local php_extract_code="
\$f = '${remote_dir}/app/etc/local.xml';
if (!file_exists(\$f)) { fwrite(STDERR, \"File not found: \$f\n\"); exit(1); }
\$x = @simplexml_load_file(\$f);
if (!\$x) { fwrite(STDERR, \"Failed to parse XML from \$f\n\"); exit(1); }
\$c = \$x->global->resources->default_setup->connection;
if (!\$c) { fwrite(STDERR, \"Could not find connection node in \$f\n\"); exit(1); }
echo base64_encode(json_encode([
    'host' => (string)\$c->host,
    'username' => (string)\$c->username,
    'password' => (string)\$c->password,
    'dbname' => (string)\$c->dbname
]));"

    local norm_env
    norm_env=$(normalize_env_name "${env_name}")
    local host_var="REMOTE_${norm_env}_HOST"
    local port_var="REMOTE_${norm_env}_PORT"
    local user_var="REMOTE_${norm_env}_USER"

    local r_host="${!host_var:-}"
    local r_port="${!port_var:-22}"
    local r_user="${!user_var:-}"

    if [[ -z "${r_host}" ]]; then
        printf "❌ \033[31mRemote host not configured for '%s'\033[0m\n" "${env_name}" >&2
        return 1
    fi

    local php_b64
    php_b64=$(printf '%s' "${php_extract_code}" | base64 -w 0)

    local db_info_json
    db_info_json=$(ssh ${SSH_OPTS:-} -o IdentityAgent=none -p "${r_port}" "${r_user}@${r_host}" "php -r 'eval(base64_decode(\"${php_b64}\"));'" 2>&1) || {
        printf "❌ \033[31mSSH failed or remote PHP error:\033[0m\n%s\n" "${db_info_json}" >&2
        return 1
    }

    if [[ -z "${db_info_json}" ]]; then
        return 1
    fi

    # Decode locally
    local db_host db_port db_user db_pass db_name
    db_host=$(${php_host_cmd} -r "\$a = json_decode(base64_decode(\$argv[1]), true); echo strpos(\$a['host'] ?? 'db', ':') === false ? (\$a['host'] ?? 'db') : explode(':', \$a['host'])[0];" -- "${db_info_json}")
    db_port=$(${php_host_cmd} -r "\$a = json_decode(base64_decode(\$argv[1]), true); echo strpos(\$a['host'] ?? '', ':') === false ? '3306' : explode(':', \$a['host'])[1];" -- "${db_info_json}")
    db_user=$(${php_host_cmd} -r "\$a = json_decode(base64_decode(\$argv[1]), true); echo \$a['username'] ?? '';" -- "${db_info_json}")
    db_pass=$(${php_host_cmd} -r "\$a = json_decode(base64_decode(\$argv[1]), true); echo \$a['password'] ?? '';" -- "${db_info_json}")
    db_name=$(${php_host_cmd} -r "\$a = json_decode(base64_decode(\$argv[1]), true); echo \$a['dbname'] ?? '';" -- "${db_info_json}")

    echo "DB_HOST=${db_host}"
    echo "DB_PORT=${db_port}"
    echo "DB_USERNAME=${db_user}"
    echo "DB_PASSWORD=${db_pass}"
    echo "DB_DATABASE=${db_name}"
}

# List of tables to ignore during standard (non-full) database dumps
IGNORED_TABLES=(
    'catalogsearch_fulltext'
    'catalogsearch_query'
    'catalogsearch_result'
    'core_session'
    'cron_schedule'
    'enterprise_logging_event'
    'enterprise_logging_event_changes'
    'index_event'
    'log_customer'
    'log_quote'
    'log_summary'
    'log_summary_type'
    'log_url'
    'log_url_info'
    'log_visitor'
    'log_visitor_info'
    'log_visitor_online'
    'mkp_api_session_vendor'
    'report_compared_product_index'
    'report_viewed_product_index'
    'smtppro_email_log'
    'udprod_images'
)

# List of tables containing sensitive data to be ignored when --no-pii is passed
SENSITIVE_TABLES=(
    'admin_passwords'
    'admin_user'
    'customer_address_entity'
    'customer_address_entity_datetime'
    'customer_address_entity_decimal'
    'customer_address_entity_int'
    'customer_address_entity_text'
    'customer_address_entity_varchar'
    'customer_entity'
    'customer_entity_datetime'
    'customer_entity_decimal'
    'customer_entity_int'
    'customer_entity_text'
    'customer_entity_varchar'
    'downloadable_link_purchased'
    'downloadable_link_purchased_item'
    'newsletter_subscriber'
    'paypal_payment_transaction'
    'sales_flat_creditmemo'
    'sales_flat_creditmemo_comment'
    'sales_flat_creditmemo_grid'
    'sales_flat_creditmemo_item'
    'sales_flat_invoice'
    'sales_flat_invoice_comment'
    'sales_flat_invoice_grid'
    'sales_flat_invoice_item'
    'sales_flat_order'
    'sales_flat_order_address'
    'sales_flat_order_grid'
    'sales_flat_order_item'
    'sales_flat_order_payment'
    'sales_flat_order_status_history'
    'sales_flat_quote'
    'sales_flat_quote_address'
    'sales_flat_quote_item'
    'sales_flat_quote_item_option'
    'sales_flat_quote_payment'
    'sales_flat_quote_shipping_rate'
    'sales_flat_shipment'
    'sales_flat_shipment_comment'
    'sales_flat_shipment_grid'
    'sales_flat_shipment_item'
    'sales_flat_shipment_track'
    'sales_order_tax'
    'sales_order_tax_item'
    'sales_payment_transaction'
    'urma_rma'
    'urma_rma_comment'
    'urma_rma_grid'
    'urma_rma_item'
    'urma_rma_track'
)
