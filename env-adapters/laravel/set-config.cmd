
:: Updating Laravel configuration

# Update base URL in .env
if warden env exec php-fpm test -f .env; then
    warden env exec php-fpm sed -i "s|^APP_URL=.*|APP_URL=https://${TRAEFIK_SUBDOMAIN}.${TRAEFIK_DOMAIN}|" .env
fi

# Configure Redis if enabled
if [[ "$WARDEN_REDIS" -eq "1" ]]; then
    :: Configuring Redis
    warden env exec php-fpm sed -i "s|^CACHE_DRIVER=.*|CACHE_DRIVER=redis|" .env
    warden env exec php-fpm sed -i "s|^SESSION_DRIVER=.*|SESSION_DRIVER=redis|" .env
    warden env exec php-fpm sed -i "s|^REDIS_HOST=.*|REDIS_HOST=redis|" .env
fi

:: Clearing cache
warden env exec php-fpm php artisan cache:clear
warden env exec php-fpm php artisan config:clear
warden env exec php-fpm php artisan route:clear
warden env exec php-fpm php artisan view:clear

echo "✅ Configuration updated successfully!"
