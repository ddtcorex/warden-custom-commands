PV=$(which pv 2>/dev/null || which cat)
STREAM_DB=
DUMP_FILENAME=

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
        --stream-db)
            STREAM_DB=1
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

if [[ -z "$DUMP_FILENAME" ]] && [[ -z "$STREAM_DB" ]]; then
    echo -e "😮 \033[31mPlease specify a dump file or use --stream-db\033[0m"
    exit 1
fi

if [[ -n "$DUMP_FILENAME" ]] && [[ ! -f "$DUMP_FILENAME" ]]; then
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

DB_USER=${DB_USER:-laravel}
DB_PASS=${DB_PASS:-laravel}
DB_NAME=${DB_NAME:-laravel}

warden env exec db mysql -u "$DB_USER" -p"$DB_PASS" -e "drop database if exists ${DB_NAME}; create database ${DB_NAME} character set = \"utf8mb4\" collate = \"utf8mb4_unicode_ci\";"

# Standard SQL cleanup filters (definers and common collation fixes)
SED_FILTERS=(
    -e '/999999.*sandbox/d'
    -e 's/DEFINER=[^*]*\*/\*/g'
    -e 's/utf8mb4_0900_ai_ci/utf8mb4_general_ci/g'
    -e 's/utf8mb4_unicode_520_ci/utf8mb4_general_ci/g'
    -e 's/utf8_unicode_520_ci/utf8_general_ci/g'
)

if [[ ${STREAM_DB} ]]; then
    if [[ "$ENV_SOURCE" == "local" ]] || [[ -z "${ENV_SOURCE_HOST+x}" ]]; then
        echo -e "😮 \033[31mStreaming requires a remote environment. Specify one with -e (e.g. -e staging)\033[0m"
        exit 1
    fi

    :: "Streaming database from ${ENV_SOURCE} (direct import)"
    # Fetch DB creds via SSH (using logic from db-dump.cmd)
    db_info=$($SSH_COMMAND -p $ENV_SOURCE_PORT $ENV_SOURCE_USER@$ENV_SOURCE_HOST "grep -E '^DB_(HOST|PORT|DATABASE|USERNAME|PASSWORD)=' $ENV_SOURCE_DIR/.env")
    db_host=$(echo "$db_info" | grep DB_HOST | cut -d= -f2 | tr -d '"'"'")
    db_port=$(echo "$db_info" | grep DB_PORT | cut -d= -f2 | tr -d '"'"'")
    db_name=$(echo "$db_info" | grep DB_DATABASE | cut -d= -f2 | tr -d '"'"'")
    db_user=$(echo "$db_info" | grep DB_USERNAME | cut -d= -f2 | tr -d '"'"'")
    db_pass=$(echo "$db_info" | grep DB_PASSWORD | cut -d= -f2 | tr -d '"'"'")

    db_host=${db_host:-127.0.0.1}
    db_port=${db_port:-3306}
    
    echo "Streaming mysqldump from ${ENV_SOURCE_HOST}:${db_name} ..."
    $SSH_COMMAND -p $ENV_SOURCE_PORT $ENV_SOURCE_USER@$ENV_SOURCE_HOST \
        "export MYSQL_PWD='${db_pass}'; mysqldump --single-transaction --no-tablespaces --routines -h$db_host -P$db_port -u$db_user $db_name" \
        | sed "${SED_FILTERS[@]}" \
        | warden db import --force
else
    echo -e "🔥 \033[1;32mImporting database...\033[0m"
    if gzip -t "$DUMP_FILENAME" 2>/dev/null; then
        $PV "$DUMP_FILENAME" | gunzip -c | sed "${SED_FILTERS[@]}" | warden db import --force
    else
        $PV "$DUMP_FILENAME" | sed "${SED_FILTERS[@]}" | warden db import --force
    fi
fi

[[ $launchedDatabaseContainer = 1 ]] && warden env stop db

echo -e "✅ \033[32mDatabase import complete!\033[0m"
