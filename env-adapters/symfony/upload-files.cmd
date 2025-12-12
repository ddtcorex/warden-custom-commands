#!/usr/bin/env bash
[[ ! ${WARDEN_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

source "${WARDEN_HOME_DIR:-~/.warden}/commands/env-variables"

if [ -z ${!ENV_SOURCE_HOST_VAR+x} ]; then
    echo "Invalid environment '${ENV_SOURCE}'"
    exit 2
fi

UPLOAD_PATH=./

while (( "$#" )); do
    case "$1" in
        -p|--path)
            if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
                UPLOAD_PATH="$2"
                shift 2
            else
                echo "Error: Argument for $1 is missing" >&2
                exit 1
            fi
            ;;
        --path=*|-p=*)
            UPLOAD_PATH="${1#*=}"
            shift
            ;;
        *)
            shift
            ;;
    esac
done

echo -e "⌛ \033[1;32mUploading files to $ENV_SOURCE_HOST\033[0m ..."
warden env exec php-fpm rsync -azvP -e 'ssh -p '"$ENV_SOURCE_PORT" \
    $UPLOAD_PATH $ENV_SOURCE_USER@$ENV_SOURCE_HOST:$ENV_SOURCE_DIR/$UPLOAD_PATH

echo -e "✅ \033[32mUpload complete!\033[0m"
