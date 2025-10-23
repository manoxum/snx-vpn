#!/bin/bash

cd "$(dirname "$(readlink -f "$0")")"

docker build -t inic-vpn .
chmod +x snx.sh
rm -rf ~/.local/bin/snx
ln -s $(pwd)/snx.sh ~/.local/bin/snx
