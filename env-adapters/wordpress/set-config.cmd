#!/usr/bin/env bash
# Strict mode inherited from env-variables

# env-variables is already sourced by the root dispatcher

# Only proceed if WP-CLI is available
if ! warden env exec php-fpm command -v wp &>/dev/null; then
    printf "ℹ️  WP-CLI not available in container - skipping WordPress-specific configuration\n"
    printf "   Database and Redis can be configured manually in wp-config.php\n"
    return 0
fi

# Update wp-config.php database settings
if warden env exec php-fpm test -f wp-config.php; then
    # Configuring database
    warden env exec php-fpm wp config set DB_NAME wordpress --type=constant
    warden env exec php-fpm wp config set DB_USER wordpress --type=constant
    warden env exec php-fpm wp config set DB_PASSWORD wordpress --type=constant
    warden env exec php-fpm wp config set DB_HOST db --type=constant
fi

# Configure Redis if available
if [[ "${WARDEN_REDIS:-0}" == "1" ]]; then
    # Configuring Redis
    warden env exec php-fpm wp config set WP_REDIS_HOST redis --type=constant || true
    warden env exec php-fpm wp config set WP_REDIS_PORT 6379 --raw --type=constant || true
fi

# Flush Redis cache
if warden env exec php-fpm wp plugin is-active redis-cache 2>/dev/null; then
    # Flushing Redis cache
    warden env exec php-fpm wp redis flush || true
fi

# Clear WordPress cache
# Clearing cache
warden env exec php-fpm wp cache flush || true

printf "✅ Configuration updated successfully!\n"
