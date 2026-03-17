#!/usr/bin/env bash
set -euo pipefail

[[ ! "${WARDEN_DIR:-}" ]] && >&2 printf "\033[31mNot intended to run directly!\033[0m\n" && exit 1

# Ensure SSH_OPTS is set
SSH_OPTS=${SSH_OPTS:-${WARDEN_SSH_OPTS:-}}

_ADAPTER_DIR=$(dirname "${BASH_SOURCE[0]}")
source "${_ADAPTER_DIR}"/env-variables
source "${_ADAPTER_DIR}"/utils.sh

ENV_SOURCE="${ENV_SOURCE:-local}"
if [[ "${ENV_SOURCE_DEFAULT:-0}" -eq "1" ]] || [[ "${ENV_SOURCE}" == "local" ]]; then
    ENV_SOURCE="local"
elif [[ -z "${!ENV_SOURCE_HOST_VAR+x}" ]]; then
    printf "Invalid environment '%s'\n" "${ENV_SOURCE:-}" >&2
    exit 2
fi

IGNORED_TABLES=(
    'catalogsearch_result'
    'smtppro_email_log'
    'udprod_images'
    'index_event'
    'mkp_api_session_vendor'
    'cron_schedule'
    'catalogsearch_fulltext'
    'log_customer'
    'log_quote'
    'log_summary'
    'log_summary_type'
    'log_url'
    'log_url_info'
    'log_visitor'
    'log_visitor_info'
    'log_visitor_online'
    'enterprise_logging_event'
    'enterprise_logging_event_changes'
)

function get_local_db_info() {
    # Extract credentials from local.xml
    local local_xml="${WARDEN_ENV_PATH}/app/etc/local.xml"
    if [[ ! -f "${local_xml}" ]]; then
        error "local.xml not found at ${local_xml}"
        return 1
    fi
    
    # Simple grep/sed extraction to avoid container overhead if possible
    DB_HOST=$(grep -oPm1 "(?<=<host><\!\[CDATA\[)[^\]]+" "${local_xml}")
    DB_USER=$(grep -oPm1 "(?<=<username><\!\[CDATA\[)[^\]]+" "${local_xml}")
    DB_PASS=$(grep -oPm1 "(?<=<password><\!\[CDATA\[)[^\]]+" "${local_xml}")
    DB_NAME=$(grep -oPm1 "(?<=<dbname><\!\[CDATA\[)[^\]]+" "${local_xml}")
}

function dump_local () {
    get_local_db_info
    
    local ignored_opts=()
    if [[ "${FULL_DUMP:-0}" -eq "0" ]]; then
        for table in "${IGNORED_TABLES[@]}"; do
            ignored_opts+=( --ignore-table="${DB_NAME}.${DB_PREFIX:-}${table}" )
        done
    fi

    printf "⌛ \033[1;32mDumping local database (\033[33m%s\033[1;32m)...\033[0m\n" "${DB_NAME}"
    
    mkdir -p "$(dirname "${DUMP_FILENAME}")"

    local sed_filters="sed -e '/999999.*sandbox/d' -e 's/DEFINER=[^*]*\*/\*/g' -e 's/ROW_FORMAT=FIXED//g'"
    
    local db_dump_metadata="export MYSQL_PWD='${DB_PASS}'; \$(command -v mariadb-dump || echo mysqldump) --max-allowed-packet=512M --force --single-transaction --no-tablespaces --no-data --routines -h${DB_HOST} -u${DB_USER} ${DB_NAME} 2>/dev/null | ${sed_filters} | gzip -1"
    warden env exec -T db bash -c "${db_dump_metadata}" > "${DUMP_FILENAME}"
    
    local db_dump_data="export MYSQL_PWD='${DB_PASS}'; \$(command -v mariadb-dump || echo mysqldump) --max-allowed-packet=512M --force --single-transaction --no-tablespaces --skip-triggers --no-create-info ${ignored_opts[*]} -h${DB_HOST} -u${DB_USER} ${DB_NAME} 2>/dev/null | ${sed_filters} | gzip -1"
    warden env exec -T db bash -c "${db_dump_data}" >> "${DUMP_FILENAME}"

    printf "✅ \033[32mDatabase dump complete! File: %s\033[0m\n" "${DUMP_FILENAME}"
}

function dump_premise () {
    local src_db_info=$(get_remote_db_info "${ENV_SOURCE_HOST}" "${ENV_SOURCE_PORT}" "${ENV_SOURCE_USER}" "${ENV_SOURCE_DIR}")
    local db_host=$(echo "${src_db_info}" | grep "^DB_HOST=" | cut -d= -f2-)
    local db_port=$(echo "${src_db_info}" | grep "^DB_PORT=" | cut -d= -f2-)
    local db_user=$(echo "${src_db_info}" | grep "^DB_USERNAME=" | cut -d= -f2-)
    local db_pass=$(echo "${src_db_info}" | grep "^DB_PASSWORD=" | cut -d= -f2-)
    local db_name=$(echo "${src_db_info}" | grep "^DB_DATABASE=" | cut -d= -f2-)

    local ignored_opts=""
    if [[ "${FULL_DUMP:-0}" -eq "0" ]]; then
        for table in "${IGNORED_TABLES[@]}"; do
            ignored_opts+=" --ignore-table=\"${db_name}.${DB_PREFIX:-}${table}\""
        done
    fi

    local sed_filters="sed -e '/999999.*sandbox/d' -e 's/DEFINER=[^*]*\\*/\\*/g' -e 's/ROW_FORMAT=FIXED//g'"

    if [[ "${LOCAL_DOWNLOAD}" -eq 1 ]]; then
        printf "⌛ \033[1;32mDumping \033[33m%s\033[1;32m database from \033[33m%s\033[1;32m to local...\033[0m\n" "${db_name}" "${ENV_SOURCE_HOST}"

        local db_dump_metadata="export MYSQL_PWD='${db_pass}'; \$(command -v mariadb-dump || echo mysqldump) --max-allowed-packet=512M --force --single-transaction --no-tablespaces --no-data --routines -h${db_host} -P${db_port} -u${db_user} ${db_name} 2>/dev/null | ${sed_filters} | gzip -1"
        warden remote-exec -e "${ENV_SOURCE}" -- bash -c "set -o pipefail; ${db_dump_metadata}" > "${DUMP_FILENAME}"

        local db_dump_data="export MYSQL_PWD='${db_pass}'; \$(command -v mariadb-dump || echo mysqldump) --max-allowed-packet=512M --force --single-transaction --no-tablespaces --skip-triggers --no-create-info ${ignored_opts} -h${db_host} -P${db_port} -u${db_user} ${db_name} 2>/dev/null | ${sed_filters} | gzip -1"
        warden remote-exec -e "${ENV_SOURCE}" -- bash -c "set -o pipefail; ${db_dump_data}" >> "${DUMP_FILENAME}"
        
        printf "✅ \033[32mDatabase dump complete! File: %s\033[0m\n" "${DUMP_FILENAME}"
    else
        printf "⌛ \033[1;32mDumping \033[33m%s\033[1;32m database on \033[33m%s\033[1;32m...\033[0m\n" "${db_name}" "${ENV_SOURCE_HOST}"

        local remote_cmd_file="${DUMP_FILENAME}"
        if [[ "${remote_cmd_file}" != /* ]]; then
            remote_cmd_file="${ENV_SOURCE_DIR}/${remote_cmd_file}"
        fi

        local dump_cmd="
            mkdir -p \"\$(dirname \"${remote_cmd_file}\")\" && 
            export MYSQL_PWD='${db_pass}'; 
            { 
               \$(command -v mariadb-dump || echo mysqldump) --max-allowed-packet=512M --force --single-transaction --no-tablespaces --no-data --routines -h${db_host} -P${db_port} -u${db_user} ${db_name} 2>/dev/null | ${sed_filters};
               \$(command -v mariadb-dump || echo mysqldump) --max-allowed-packet=512M --force --single-transaction --no-tablespaces --skip-triggers --no-create-info ${ignored_opts} -h${db_host} -P${db_port} -u${db_user} ${db_name} 2>/dev/null | ${sed_filters};
            } | gzip -1 > \"${remote_cmd_file}\"
        "
        
        if ! warden remote-exec -e "${ENV_SOURCE}" -- bash -c "${dump_cmd}"; then
            printf "\033[31mError: Database dump failed on remote.\033[0m\n" >&2
            return 1
        fi
        
        printf "✅ \033[32mDatabase dump complete! File: %s:%s\033[0m\n" "${ENV_SOURCE_HOST}" "${DUMP_FILENAME}"
    fi
}

DUMP_FILENAME=
FULL_DUMP=0
EXCLUDE_SENSITIVE_DATA=0
LOCAL_DOWNLOAD=0

while (( "$#" )); do
    case "$1" in
        -f=*|--file=*)
            DUMP_FILENAME="${1#*=}"
            shift
            ;;
        -f|--file)
            DUMP_FILENAME="$2"
            shift 2
            ;;
        --full)
            FULL_DUMP=1
            shift
            ;;
        --exclude-sensitive-data)
            EXCLUDE_SENSITIVE_DATA=1
            shift
            ;;
        --local)
            LOCAL_DOWNLOAD=1
            shift
            ;;
        *)
            shift
            ;;
    esac
done

if [[ -z "${DUMP_FILENAME}" ]] && [[ -n "${WARDEN_PARAMS[0]+1}" ]]; then
    DUMP_FILENAME="${WARDEN_PARAMS[0]}"
fi

if [[ -z "${DUMP_FILENAME}" ]]; then
    DUMP_FILENAME="var/${WARDEN_ENV_NAME}_${ENV_SOURCE}-$(date +%Y%m%dT%H%M%S).sql.gz"
fi

if [[ "${FULL_DUMP}" -eq "0" && "${EXCLUDE_SENSITIVE_DATA}" -eq "1" ]]; then
    IGNORED_TABLES+=(
        'admin_user' 'admin_passwords'
        'sales_flat_order' 'sales_flat_order_address' 'sales_flat_order_grid' 'sales_flat_order_item' 'sales_flat_order_payment' 'sales_flat_order_status_history' 'sales_order_tax' 'sales_order_tax_item'
        'sales_flat_invoice' 'sales_flat_invoice_comment' 'sales_flat_invoice_grid' 'sales_flat_invoice_item'
        'sales_flat_shipment' 'sales_flat_shipment_comment' 'sales_flat_shipment_grid' 'sales_flat_shipment_item' 'sales_flat_shipment_track'
        'sales_flat_creditmemo' 'sales_flat_creditmemo_comment' 'sales_flat_creditmemo_grid' 'sales_flat_creditmemo_item' 'sales_payment_transaction'
        'paypal_payment_transaction' 'urma_rma' 'urma_rma_comment' 'urma_rma_grid' 'urma_rma_item' 'urma_rma_track'
        'sales_flat_quote' 'sales_flat_quote_item' 'sales_flat_quote_item_option' 'sales_flat_quote_address' 'sales_flat_quote_shipping_rate' 'sales_flat_quote_payment'
        'customer_address_entity' 'customer_address_entity_datetime' 'customer_address_entity_decimal' 'customer_address_entity_int' 'customer_address_entity_text' 'customer_address_entity_varchar'
        'customer_entity' 'customer_entity_datetime' 'customer_entity_decimal' 'customer_entity_int' 'customer_entity_text' 'customer_entity_varchar' 'newsletter_subscriber'
    )
fi

if [[ "${ENV_SOURCE}" = "local" ]]; then
    dump_local
else
    dump_premise
fi
