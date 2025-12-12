#!/usr/bin/env bash
[[ ! ${WARDEN_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

# env-variables is already sourced by the root dispatcher

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

# Ensure the database service is started for this environment
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

echo -e "⌛ \033[1;32mDropping and initializing docker database ...\033[0m"
warden db connect -e 'drop database magento; create database magento character set = "utf8" collate = "utf8_general_ci";'

echo -e "🔥 \033[1;32mImporting database ...\033[0m"
if gzip -t "$DUMP_FILENAME"; then
    $PV "$DUMP_FILENAME" | gunzip -c | sed -e '/999999.*sandbox/d' -e 's/DEFINER=[^*]*\*/\*/g' -e 's/ROW_FORMAT=FIXED//g' | warden db import --force
else
    $PV "$DUMP_FILENAME" | sed -e '/999999.*sandbox/d' -e 's/DEFINER=[^*]*\*/\*/g' -e 's/ROW_FORMAT=FIXED//g' | warden db import --force
fi

[[ $launchedDatabaseContainer = 1 ]] && warden env stop db

echo -e "✅ \033[32mDatabase import complete!\033[0m"
