#!/usr/bin/env sh
set -eu
cd "$(dirname "$0")"
echo "Harmony Music is available at http://127.0.0.1:8000"
python3 -m http.server 8000 --bind 127.0.0.1