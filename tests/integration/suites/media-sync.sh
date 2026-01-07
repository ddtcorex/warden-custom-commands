#!/usr/bin/env bash
header "Media Sync Tests"
test_media_sync_structure() {
    local media_root="/var/www/html/$(get_media_path)"
    create_test_file "${LOCAL_PHP}" "${media_root}/test_media/image.jpg" "test image"
    remove_file "${DEV_PHP}" "${media_root}/test_media"
    run_sync_confirmed -s local -d dev -m > /dev/null 2>&1
    if file_exists "${DEV_PHP}" "${media_root}/test_media/image.jpg"; then
        pass "Media sync structure - directory structure preserved"
    else
        fail "Media sync structure" "Media files not synced to correct location"
    fi
}
test_media_sync_structure

# Test Magento 2 Product Media Inclusion
test_media_sync_product_inclusion() {
    [[ "${TEST_ENV_TYPE}" != "magento2" ]] && return 0

    local media_root=$(get_media_path)
    local prod_img="catalog/product/test-image.jpg"
    local cache_img="catalog/product/cache/test-cache.jpg"
    
    # Setup source files (use absolute path for create_test_file)
    create_test_file "${LOCAL_PHP}" "/var/www/html/${media_root}/${prod_img}" "PRODUCT IMAGE"
    create_test_file "${LOCAL_PHP}" "/var/www/html/${media_root}/${cache_img}" "CACHE IMAGE"
    
    # Clear destination
    remove_file "${DEV_PHP}" "/var/www/html/${media_root}/${prod_img}"
    remove_file "${DEV_PHP}" "/var/www/html/${media_root}/${cache_img}"

    # 1. Test Default Behavior (Should exclude catalog/product)
    run_sync_confirmed -s local -d dev --media > /dev/null 2>&1
    
    if ! file_exists "${DEV_PHP}" "/var/www/html/${media_root}/${prod_img}"; then
        pass "Default media sync - catalog/product excluded"
    else
        fail "Default media sync" "catalog/product was incorrectly synced"
    fi

    # 2. Test --include-product (Should include product, but exclude cache)
    run_sync_confirmed -s local -d dev --media --include-product > /dev/null 2>&1
    
    if file_exists "${DEV_PHP}" "/var/www/html/${media_root}/${prod_img}"; then
        pass "--include-product sync - product image synced"
    else
        fail "--include-product sync" "Product image was NOT synced"
    fi

    if ! file_exists "${DEV_PHP}" "/var/www/html/${media_root}/${cache_img}"; then
        pass "--include-product sync - cache still excluded"
    else
        fail "--include-product sync" "Cache image was incorrectly synced"
    fi
}
test_media_sync_product_inclusion
