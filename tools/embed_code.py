#!/usr/bin/env python3
"""Embed example source files into Markdown recipes so an agent reads architecture + code in one file.

In Markdown:
    <!-- code: examples/interaction/ServerScriptService/Interaction.server.luau -->
    <!-- /code -->
Everything between the markers is replaced with a ```luau fence whose first line is `-- file: <path>`.
The .luau file is the single source of truth (typechecked by tools/check_code.py as part of its example project).

  python tools/embed_code.py          rewrite recipes in place
  python tools/embed_code.py --check  exit 1 if any embed is stale (CI)
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BLOCK = re.compile(r"(<!-- code: (?P<path>[^ ]+) -->\n)(?P<body>.*?)(<!-- /code -->)", re.S)


def render(match: re.Match) -> str:
    rel = match.group("path")
    src = ROOT / rel
    if not src.exists():
        raise FileNotFoundError(f"embed target missing: {rel}")
    code = src.read_text(encoding="utf-8").rstrip("\n")
    return f"{match.group(1)}```luau\n-- file: {rel}\n{code}\n```\n{match.group(4)}"


def main() -> int:
    check = "--check" in sys.argv
    stale = []
    for md in sorted(ROOT.rglob("*.md")):
        if ".cache" in md.parts or ".git" in md.parts:
            continue
        text = md.read_text(encoding="utf-8")
        if "<!-- code: " not in text:
            continue
        new = BLOCK.sub(render, text)
        if new != text:
            stale.append(md.relative_to(ROOT).as_posix())
            if not check:
                md.write_text(new, encoding="utf-8")
    if check and stale:
        print("stale embeds (run python tools/embed_code.py):", *stale, sep="\n  ")
        return 1
    print(f"embed_code: {'checked' if check else 'updated'} ({len(stale)} file(s) {'stale' if check else 'rewritten'})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
