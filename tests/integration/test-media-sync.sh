#!/usr/bin/env bash
# test-media-sync.sh - Media sync integration tests

header "Media Sync Tests"

# Test 1: Media sync creates correct directory structure
test_media_sync_structure() {
    create_test_file "${LOCAL_PHP}" "/var/www/html/pub/media/test_media/image.jpg" "test image"
    remove_file "${DEV_PHP}" "/var/www/html/pub/media/test_media"
    
    run_sync_confirmed -s local -d dev -m > /dev/null 2>&1
    
    if file_exists "${DEV_PHP}" "/var/www/html/pub/media/test_media/image.jpg"; then
        pass "Media sync structure - directory structure preserved"
    else
        fail "Media sync structure" "Media files not synced to correct location"
    fi
}

# Test 2: Media sync excludes catalog/product by default
test_media_sync_excludes_product() {
    create_test_file "${LOCAL_PHP}" "/var/www/html/pub/media/catalog/product/test.jpg" "product image"
    remove_file "${DEV_PHP}" "/var/www/html/pub/media/catalog/product/test.jpg"
    
    run_sync_confirmed -s local -d dev -m > /dev/null 2>&1
    
    if file_exists "${DEV_PHP}" "/var/www/html/pub/media/catalog/product/test.jpg"; then
        fail "Media sync product exclusion" "catalog/product was not excluded"
    else
        pass "Media sync product exclusion - catalog/product excluded by default"
    fi
}

# Test 3: Media sync includes product images with --include-product
test_media_sync_includes_product() {
    create_test_file "${LOCAL_PHP}" "/var/www/html/pub/media/catalog/product/included.jpg" "included product"
    remove_file "${DEV_PHP}" "/var/www/html/pub/media/catalog/product/included.jpg"
    
    run_sync_confirmed -s local -d dev -m --include-product > /dev/null 2>&1
    
    if file_exists "${DEV_PHP}" "/var/www/html/pub/media/catalog/product/included.jpg"; then
        pass "Media sync --include-product - catalog/product included"
    else
        fail "Media sync --include-product" "catalog/product was not included with flag"
    fi
}

# Test 4: Media sync excludes tmp directory
test_media_sync_excludes_tmp() {
    create_test_file "${LOCAL_PHP}" "/var/www/html/pub/media/tmp/cache.dat" "temp cache"
    remove_file "${DEV_PHP}" "/var/www/html/pub/media/tmp/cache.dat"
    
    run_sync_confirmed -s local -d dev -m > /dev/null 2>&1
    
    if file_exists "${DEV_PHP}" "/var/www/html/pub/media/tmp/cache.dat"; then
        fail "Media sync tmp exclusion" "tmp directory was not excluded"
    else
        pass "Media sync tmp exclusion - tmp excluded correctly"
    fi
}

# Run all media sync tests
test_media_sync_structure
test_media_sync_excludes_product
test_media_sync_includes_product
test_media_sync_excludes_tmp

# Cleanup
remove_file "${LOCAL_PHP}" "/var/www/html/pub/media/test_media"
remove_file "${LOCAL_PHP}" "/var/www/html/pub/media/catalog/product"
remove_file "${LOCAL_PHP}" "/var/www/html/pub/media/tmp"
remove_file "${DEV_PHP}" "/var/www/html/pub/media/test_media"
remove_file "${DEV_PHP}" "/var/www/html/pub/media/catalog/product"
remove_file "${DEV_PHP}" "/var/www/html/pub/media/tmp"
