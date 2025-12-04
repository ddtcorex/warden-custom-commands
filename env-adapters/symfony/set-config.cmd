
:: Updating Symfony configuration

# Configure database if needed
if warden env exec php-fpm test -f config/packages/doctrine.yaml; then
    if warden env exec php-fpm test -f .env; then
        :: Configuring database
        warden env exec php-fpm sed -i '/DATABASE_URL=/d' .env
        echo "DATABASE_URL=mysql://symfony:symfony@db:3306/symfony" | warden env exec php-fpm tee -a .env
    fi
fi

# Configure Redis if available
if warden env exec php-fpm test -f config/packages/framework.yaml; then
    if [[ "${WARDEN_REDIS}" == "1" ]]; then
        :: Configuring Redis
        if ! warden env exec php-fpm grep -q "REDIS_URL=" .env 2>/dev/null; then
            echo "REDIS_URL=redis://redis:6379" | warden env exec php-fpm tee -a .env
        fi
    fi
fi

# Clear cache
:: Clearing cache
warden env exec php-fpm php bin/console cache:clear

echo "✅ Configuration updated successfully!"
