#!/usr/bin/env sh
set -eu
cd "$(dirname "$0")"
python3 tools/publish_github.py
