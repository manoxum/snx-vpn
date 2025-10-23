#!/bin/bash

cd "$(dirname "$(readlink -f "$0")")"

docker build -t inic-vpn .
chmod +x run.sh
rm -rf ~/.local/bin/snx
ln -s $(pwd)/run.sh ~/.local/bin/snx
