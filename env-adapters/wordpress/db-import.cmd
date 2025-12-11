#!/usr/bin/env bash
[[ ! ${WARDEN_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

source "${WARDEN_HOME_DIR:-~/.warden}/commands/env-variables"

DUMP_FILENAME=
PV=`which pv || which cat`

while (( "$#" )); do
    case "$1" in
        -f|--file)
            if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
                DUMP_FILENAME="$2"
                shift 2
            else
                echo "Error: Argument for $1 is missing" >&2
                exit 1
            fi
            ;;
        --file=*|-f=*)
            DUMP_FILENAME="${1#*=}"
            shift
            ;;
        *)
            shift
            ;;
    esac
done

if [[ -z "$DUMP_FILENAME" ]] && [[ -n "${WARDEN_PARAMS[0]+1}" ]]; then
    DUMP_FILENAME="${WARDEN_PARAMS[0]}"
fi

if [ ! -f "$DUMP_FILENAME" ]; then
    echo -e "😮 \033[31mDump file $DUMP_FILENAME not found\033[0m"
    exit 1
fi

# Ensure database service is running
launchedDatabaseContainer=0
DB_CONTAINER_ID=$(warden env ps --filter status=running -q db 2>/dev/null || true)
if [[ -z "$DB_CONTAINER_ID" ]]; then
    warden env up db
    DB_CONTAINER_ID=$(warden env ps --filter status=running -q db 2>/dev/null || true)
    if [[ -z "$DB_CONTAINER_ID" ]]; then
        echo -e "😮 \033[31mDatabase container failed to start\033[0m"
        exit 1
    fi
    launchedDatabaseContainer=1
fi

echo -e "⌛ \033[1;32mDropping and initializing database...\033[0m"
DB_USER=$(warden env exec db printenv MYSQL_USER)
DB_PASS=$(warden env exec db printenv MYSQL_PASSWORD)
DB_NAME=$(warden env exec db printenv MYSQL_DATABASE)

DB_USER=${DB_USER:-wordpress}
DB_PASS=${DB_PASS:-wordpress}
DB_NAME=${DB_NAME:-wordpress}

warden env exec db mysql -u "$DB_USER" -p"$DB_PASS" -e "drop database if exists ${DB_NAME}; create database ${DB_NAME} character set = \"utf8mb4\" collate = \"utf8mb4_unicode_ci\";"

echo -e "🔥 \033[1;32mImporting database...\033[0m"
if gzip -t "$DUMP_FILENAME" 2>/dev/null; then
    $PV "$DUMP_FILENAME" | gunzip -c | warden db import --force
else
    $PV "$DUMP_FILENAME" | warden db import --force
fi

[[ $launchedDatabaseContainer = 1 ]] && warden env stop db

echo -e "✅ \033[32mDatabase import complete!\033[0m"

# Search-replace URLs if WP-CLI is available
if warden env exec php-fpm wp --info &>/dev/null; then
    echo ""
    echo "💡 Don't forget to run search-replace if needed:"
    echo "   warden env exec php-fpm wp search-replace 'old-domain.com' '${TRAEFIK_SUBDOMAIN:-app}.${TRAEFIK_DOMAIN:-test.test}'"
fi
