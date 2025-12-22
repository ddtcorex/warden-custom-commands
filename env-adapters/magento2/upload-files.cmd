#!/usr/bin/env bash
[[ ! ${WARDEN_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

function dumpCloud () {
    echo -e "\033[1;32mUploading files to \033[33mAdobe Commerce Cloud \033[1;36m${ENV_SOURCE}\033[0m ..."
    magento-cloud mount:upload -p "$CLOUD_PROJECT" \
        --environment="$ENV_SOURCE_HOST" \
        "${exclude_opts[@]}" \
        --mount=$UPLOAD_PATH \
        --target=$UPLOAD_PATH \
        -y \
        || true
}

function dumpPremise () {
    echo -e "⌛ \033[1;32mUploading files to $ENV_SOURCE_HOST\033[0m ..."
    warden env exec php-fpm rsync -azvP -e "${SSH_COMMAND} -p $ENV_SOURCE_PORT" \
        "${exclude_opts[@]}" \
        $UPLOAD_PATH $ENV_SOURCE_USER@$ENV_SOURCE_HOST:$ENV_SOURCE_DIR/$UPLOAD_PATH
}

# env-variables is already sourced by the root dispatcher

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

if [ -z ${CLOUD_PROJECT+x} ]; then
    dumpPremise
else
    dumpCloud
fi
