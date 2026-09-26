#!/usr/bin/env bash
# Downloads the Luau CLI (luau, luau-analyze, luau-compile) and luau-lsp with the
# Roblox API type definitions into ./.toolchain (git-ignored). Needs curl + unzip.
# This is what lets an agent REALLY typecheck Roblox code against the engine API.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${LUAU_TOOLCHAIN:-$ROOT/.toolchain}"
mkdir -p "$DEST"
cd "$DEST"
case "$(uname -s)" in
  Linux)  LUAU_ASSET=luau-ubuntu.zip;  LSP_ASSET=luau-lsp-linux-x86_64.zip ;;
  Darwin) LUAU_ASSET=luau-macos.zip;   LSP_ASSET=luau-lsp-macos.zip ;;
  *) echo "Unsupported OS; on Windows use tools/setup_luau_toolchain.ps1 or download manually" >&2; exit 2 ;;
esac
curl -fsSL -o luau.zip "https://github.com/luau-lang/luau/releases/latest/download/$LUAU_ASSET"
curl -fsSL -o lsp.zip  "https://github.com/JohnnyMorganz/luau-lsp/releases/latest/download/$LSP_ASSET"
unzip -oq luau.zip && unzip -oq lsp.zip && rm -f luau.zip lsp.zip
curl -fsSL -o globalTypes.d.luau "https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau"
chmod +x luau luau-analyze luau-compile luau-lsp 2>/dev/null || true
echo "Toolchain ready in $DEST"
echo "Typecheck a Roblox file:  $DEST/luau-lsp analyze --definitions=$DEST/globalTypes.d.luau path/to/file.luau"
echo "Run pure Luau:            $DEST/luau file.luau"
