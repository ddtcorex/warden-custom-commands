
DB_DUMP=""

while (( "$#" )); do
    case "$1" in
        -f|--file)
            if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
                DB_DUMP="$2"
                shift 2
            else
                echo "Error: Argument for $1 is missing" >&2
                exit 1
            fi
            ;;
        --file=*|-f=*)
            DB_DUMP="${1#*=}"
            shift
            ;;
        *)
            shift
            ;;
    esac
done

if [[ -z "$DB_DUMP" ]]; then
    echo "Error: Database dump file required"
    echo "Usage: warden db-import --file=<dump.sql>"
    exit 1
fi

if [[ ! -f "$DB_DUMP" ]]; then
    echo "Error: File not found: $DB_DUMP"
    exit 1
fi

:: Importing database dump

# Decompress if gzipped
if [[ "$DB_DUMP" =~ \.gz$ ]]; then
    gunzip -c "$DB_DUMP" | warden db connect
else
    warden db connect < "$DB_DUMP"
fi

echo "✅ Database imported successfully"

# Search-replace URLs if WP-CLI is available
if warden env exec php-fpm wp --info &>/dev/null; then
    echo ""
    echo "💡 Don't forget to run search-replace if needed:"
    echo "   warden env exec php-fpm wp search-replace 'old-domain.com' '${TRAEFIK_SUBDOMAIN:-app}.${TRAEFIK_DOMAIN:-test.test}'"
fi
