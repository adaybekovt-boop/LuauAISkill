#!/usr/bin/env sh
set -eu
cd "$(dirname "$0")"
python3 -c 'import sys; assert sys.version_info >= (3,10), "Python 3.10+ required"'
python3 tools/fetch_corpus.py
python3 tools/release_pack.py --require-corpus --out ../LuauAISkill-Full.zip
