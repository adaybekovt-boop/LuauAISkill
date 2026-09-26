#!/usr/bin/env python3
"""Check relative links and #anchors in all Markdown files (GitHub-style heading slugs).

  python tools/check_links.py            exit 1 on any broken link
External (http/https/mailto) links are not fetched; only their syntax is checked.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SKIP_DIRS = {".cache", ".git", "node_modules", "__pycache__"}
LINK = re.compile(r"(?<!!)\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
FENCE = re.compile(r"^\s*```")


def slug(heading: str) -> str:
    """GitHub anchor: lowercase, drop punctuation except - and _, spaces → -."""
    h = re.sub(r"<[^>]+>", "", heading).strip().lower()
    h = re.sub(r"[^\w\- ]", "", h, flags=re.UNICODE)
    return h.replace(" ", "-")


def anchors(path: Path) -> set[str]:
    seen: dict[str, int] = {}
    out = set()
    in_code = False
    for line in path.read_text(encoding="utf-8").splitlines():
        if FENCE.match(line):
            in_code = not in_code
            continue
        if in_code:
            continue
        m = re.match(r"^#{1,6}\s+(.*)", line)
        if m:
            base = slug(m.group(1))
            n = seen.get(base, 0)
            out.add(base if n == 0 else f"{base}-{n}")
            seen[base] = n + 1
    return out


def md_files() -> list[Path]:
    return sorted(p for p in ROOT.rglob("*.md") if not (set(p.relative_to(ROOT).parts) & SKIP_DIRS))


def main() -> int:
    cache: dict[Path, set[str]] = {}
    broken = 0
    checked = 0
    for md in md_files():
        in_code = False
        for n, line in enumerate(md.read_text(encoding="utf-8").splitlines(), 1):
            if FENCE.match(line):
                in_code = not in_code
                continue
            if in_code:
                continue
            for target in LINK.findall(re.sub(r"`[^`]*`", "", line)):
                if target.startswith(("http://", "https://", "mailto:")):
                    continue
                checked += 1
                path_part, _, frag = target.partition("#")
                dest = (md.parent / path_part).resolve() if path_part else md
                if not dest.exists():
                    print(f"{md.relative_to(ROOT)}:{n}: missing target {target}")
                    broken += 1
                    continue
                if frag and dest.is_file() and dest.suffix == ".md":
                    if dest not in cache:
                        cache[dest] = anchors(dest)
                    if frag not in cache[dest]:
                        print(f"{md.relative_to(ROOT)}:{n}: missing anchor #{frag} in {dest.relative_to(ROOT)}")
                        broken += 1
    print(f"links: {checked} checked, {broken} broken")
    return 1 if broken else 0


if __name__ == "__main__":
    sys.exit(main())
