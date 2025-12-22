#!/usr/bin/env bash
[[ ! ${WARDEN_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

# env-variables is already sourced by the root dispatcher

if [ -z ${!ENV_SOURCE_HOST_VAR+x} ]; then
    echo "Invalid environment '${ENV_SOURCE}'"
    exit 2
fi

function dumpCloud () {
    echo -e "\033[1;32mDownloading files from \033[33mAdobe Commerce Cloud \033[1;36m${ENV_SOURCE}\033[0m ..."
    magento-cloud mount:download -p "$CLOUD_PROJECT" \
        --environment="$ENV_SOURCE_HOST" \
        "${exclude_opts[@]}" \
        --mount=pub/media/ \
        --target=pub/media/ \
        -y \
        || true

    if [[ "$DUMP_INCLUDE_PRODUCT" -eq "0" ]]; then
        magento-cloud mount:download -p "$CLOUD_PROJECT" \
            --environment="$ENV_SOURCE_HOST" \
            --mount=pub/media/catalog/product/placeholder/ \
            --target=pub/media/catalog/product/placeholder/ \
            -y \
            || true
    fi
}

function dumpPremise () {
    echo -e "⌛ \033[1;32mDownloading files from $ENV_SOURCE_HOST\033[0m ..."
    warden env exec php-fpm rsync -azvP -e "${SSH_COMMAND} -p $ENV_SOURCE_PORT" \
        "${exclude_opts[@]}" \
        $ENV_SOURCE_USER@$ENV_SOURCE_HOST:$ENV_SOURCE_DIR/pub/media/ pub/media/ || true

    if [[ "$DUMP_INCLUDE_PRODUCT" -eq "0" ]]; then
        warden env exec php-fpm rsync -azvP -e "${SSH_COMMAND} -p $ENV_SOURCE_PORT" \
            $ENV_SOURCE_USER@$ENV_SOURCE_HOST:$ENV_SOURCE_DIR/pub/media/catalog/product/placeholder/ pub/media/catalog/product/placeholder/ \
            || true
    fi
}

DUMP_INCLUDE_PRODUCT=0

while (( "$#" )); do
    case "$1" in
        --include-product)
            DUMP_INCLUDE_PRODUCT=1
            shift
            ;;
        *)
            shift
            ;;
    esac
done

EXCLUDE=('*.gz' '*.zip' '*.tar' '*.7z' '*.sql' 'tmp' 'itm' 'import' 'export' 'importexport' 'captcha' 'analytics' 'catalog/product/cache' 'catalog/product.rm' 'catalog/product/product' 'opti_image' 'webp_image' 'webp_cache' 'shoppingfeed' 'amasty/blog/cache')
exclude_opts=()

if [[ "$DUMP_INCLUDE_PRODUCT" -eq "0" ]]; then
    EXCLUDE+=('catalog/product')
fi

for item in "${EXCLUDE[@]}"; do
    exclude_opts+=( --exclude="$item" )
done

if [ -z ${CLOUD_PROJECT+x} ]; then
    dumpPremise
else
    dumpCloud
fi
