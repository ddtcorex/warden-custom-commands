
DB_DUMP=""

while (( "$#" )); do
    case "$1" in
        -f|--file)
            DB_DUMP="$2"
            shift 2
            ;;
        --file=*)
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
    gunzip -c "$DB_DUMP" | warden db connect -e "SET FOREIGN_KEY_CHECKS=0; SOURCE /dev/stdin; SET FOREIGN_KEY_CHECKS=1;"
else
    warden db connect < "$DB_DUMP"
fi

echo "✅ Database imported successfully"
