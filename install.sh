#!/bin/bash

cd "$(dirname "$(readlink -f "$0")")"

docker run --rm -it \
  --privileged \
  --cap-add=NET_ADMIN \
  -p 2222:22 \
  -d  \
  -v /lib/modules:/lib/modules:ro \
  --device /dev/net/tun \
  --env-file .env.local \
  --name inic-vpn \
  inic-vpn:latest

chmod +x run.sh
ln -s $(pwd)/run.sh ~/.local/bin/snx
