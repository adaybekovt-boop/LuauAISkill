#!/usr/bin/env python3
"""Download pinned Luau CLI + luau-lsp release binaries into .cache/bin (used by tools/check_code.py).

Pins live in sources/toolchain.json. Only official GitHub release assets are downloaded; nothing is installed
system-wide. Supported hosts: linux x86_64, macOS, Windows (asset names follow upstream release naming).
"""
from __future__ import annotations

import io
import json
import os
import platform
import stat
import sys
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / ".cache" / "bin"
PINS = json.loads((ROOT / "sources" / "toolchain.json").read_text(encoding="utf-8"))


def asset(tool: str) -> str:
    system = platform.system()
    if tool == "luau":
        return {"Linux": "luau-ubuntu.zip", "Darwin": "luau-macos.zip", "Windows": "luau-windows.zip"}[system]
    arch = "arm64" if platform.machine().lower() in ("arm64", "aarch64") else "x86_64"
    return {"Linux": f"luau-lsp-linux-{arch}.zip", "Darwin": "luau-lsp-macos.zip",
            "Windows": "luau-lsp-win64.zip"}[system]


def download(tool: str) -> None:
    spec = PINS[tool]
    url = f"https://github.com/{spec['repo']}/releases/download/{spec['version']}/{asset(tool)}"
    print(f"GET {url}")
    with urllib.request.urlopen(url, timeout=120) as resp:
        data = resp.read()
    with zipfile.ZipFile(io.BytesIO(data)) as zf:
        for name in zf.namelist():
            target = BIN / Path(name).name
            target.write_bytes(zf.read(name))
            target.chmod(target.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    (BIN / f".{tool}.version").write_text(spec["version"])


def main() -> int:
    BIN.mkdir(parents=True, exist_ok=True)
    for tool in ("luau", "luau-lsp"):
        marker = BIN / f".{tool}.version"
        if marker.exists() and marker.read_text().strip() == PINS[tool]["version"] and "--force" not in sys.argv:
            print(f"OK   {tool} {PINS[tool]['version']} (cached)")
            continue
        download(tool)
        print(f"OK   {tool} {PINS[tool]['version']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
