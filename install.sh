#!/bin/bash

cd "$(dirname "$(readlink -f "$0")")"

chmod +x run.sh
ln -s $(pwd)/run.sh ~/.local/bin/snx
