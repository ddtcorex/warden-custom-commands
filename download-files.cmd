#!/usr/bin/env bash
[[ ! ${WARDEN_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

function dumpCloud () {
    echo -e "\033[1;32mDownloading files from \033[33mAdobe Commerce Cloud \033[1;36m${ENV_SOURCE}\033[0m ..."
    warden env exec php-fpm rsync -azvP "${exclude_opts[@]}" $(magento-cloud ssh --pipe -p "$CLOUD_PROJECT" -e "$ENV_SOURCE_HOST"):$DUMP_PATH $DUMP_PATH || true
}

function dumpPremise () {
    echo -e "⌛ \033[1;32mDownloading files from $ENV_SOURCE_HOST\033[0m ..."
    warden env exec php-fpm rsync -azvP -e 'ssh -p '"$ENV_SOURCE_PORT" \
        "${exclude_opts[@]}" \
        $ENV_SOURCE_USER@$ENV_SOURCE_HOST:$ENV_SOURCE_DIR/$DUMP_PATH $DUMP_PATH
}

SUBCOMMAND_DIR=$(dirname "${BASH_SOURCE[0]}")
source "${SUBCOMMAND_DIR}"/env-variables

if [ -z ${!ENV_SOURCE_HOST_VAR+x} ]; then
    echo "Invalid environment '${ENV_SOURCE}'"
    exit 2
fi

DUMP_PATH=pub/media/

while (( "$#" )); do
    case "$1" in
        --path=*|-p=*|--p=*)
            DUMP_PATH="${1#*=}"
            shift
            ;;
        -p)
            DUMP_PATH="${2}"
            shift 2
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
