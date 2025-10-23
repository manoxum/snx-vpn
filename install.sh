#!/bin/bash

cd "$(dirname "$(readlink -f "$0")")"

ENV_FILE=".env.local"
get_env_var() {
  local var_name="$1"
  grep -E "^${var_name}=" "${ENV_FILE}" 2>/dev/null | tail -n1 | cut -d '=' -f2-
}

DEFAULT_CONTAINER_IMAGE=$(get_env_var "SNX_IMAGE")
IMAGE_NAME=${DEFAULT_CONTAINER_IMAGE:-snx}

docker build -t "${IMAGE_NAME}" .
chmod +x snx.sh
rm -rf ~/.local/bin/snx
ln -s $(pwd)/snx.sh ~/.local/bin/snx
