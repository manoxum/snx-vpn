#!/bin/bash
set -e

cd "$(dirname "$(readlink -f "$0")")"

exec bash ./snx.sh install
