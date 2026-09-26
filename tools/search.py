#!/usr/bin/env python3
"""Ranked keyword search over the skill (handbook, recipes, references, tracks, SKILL.md, evals).

Sections (a heading + its text) are indexed with SQLite FTS5 (BM25 ranking). The index is rebuilt automatically when
any Markdown file is newer than it. Keyword search, not embeddings: use the words the docs would use
("session locking", "RaycastParams", "flicker").

  python tools/search.py "session locking"            top sections with path:line and a snippet
  python tools/search.py "flashlight shadows" -n 5
  python tools/search.py --rebuild
"""
from __future__ import annotations

import argparse
import re
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INDEX = ROOT / "indexes" / "search.sqlite"
INCLUDE = ("SKILL.md", "handbook", "recipes", "references", "tracks", "evals/README.md", "README.md")
HEADING = re.compile(r"^(#{1,4})\s+(.*)")


def sources() -> list[Path]:
    files: list[Path] = []
    for inc in INCLUDE:
        p = ROOT / inc
        if p.is_file():
            files.append(p)
        elif p.is_dir():
            files.extend(sorted(p.rglob("*.md")))
    return files


def sections(path: Path) -> list[tuple[int, str, str]]:
    """(line, heading path, text) per section; code blocks are kept (API names are searchable)."""
    out, title, start, buf = [], path.stem, 1, []
    stack: list[str] = []
    for i, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        m = HEADING.match(line)
        if m:
            if buf:
                out.append((start, " › ".join(stack) or title, "\n".join(buf)))
            level = len(m.group(1))
            stack = stack[: level - 1] + [m.group(2).strip()]
            start, buf = i, []
        else:
            buf.append(line)
    if buf:
        out.append((start, " › ".join(stack) or title, "\n".join(buf)))
    return out


def stale() -> bool:
    if not INDEX.exists():
        return True
    built = INDEX.stat().st_mtime
    return any(p.stat().st_mtime > built for p in sources())


def build() -> int:
    INDEX.parent.mkdir(exist_ok=True)
    if INDEX.exists():
        INDEX.unlink()
    con = sqlite3.connect(INDEX)
    con.execute("CREATE VIRTUAL TABLE s USING fts5(path UNINDEXED, line UNINDEXED, heading, body, "
                "tokenize='porter unicode61')")
    n = 0
    for path in sources():
        rel = path.relative_to(ROOT).as_posix()
        for line, heading, body in sections(path):
            con.execute("INSERT INTO s VALUES (?, ?, ?, ?)", (rel, line, heading, body))
            n += 1
    con.commit()
    con.close()
    return n


def fts_query(text: str) -> str:
    # Quote every token so punctuation (Class.Member, *Async) can't break FTS syntax; implicit AND between tokens.
    tokens = re.findall(r"[\w.:@-]+", text)
    return " ".join('"' + t.replace('"', "") + '"' for t in tokens)


def search(text: str, limit: int) -> list[tuple[str, int, str, str]]:
    con = sqlite3.connect(INDEX)
    q = fts_query(text)
    if not q:
        return []
    rows = con.execute(
        "SELECT path, line, heading, snippet(s, 3, '[', ']', ' … ', 18) FROM s WHERE s MATCH ? "
        "ORDER BY bm25(s, 0, 0, 4.0, 1.0) LIMIT ?", (q, limit)).fetchall()
    if not rows:  # fall back to OR when nothing matches every token
        q_or = " OR ".join(q.split(" "))
        rows = con.execute(
            "SELECT path, line, heading, snippet(s, 3, '[', ']', ' … ', 18) FROM s WHERE s MATCH ? "
            "ORDER BY bm25(s, 0, 0, 4.0, 1.0) LIMIT ?", (q_or, limit)).fetchall()
    con.close()
    return rows


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("query", nargs="*")
    ap.add_argument("-n", type=int, default=8, help="number of results")
    ap.add_argument("--rebuild", action="store_true")
    a = ap.parse_args()
    if a.rebuild or stale():
        count = build()
        if a.rebuild:
            print(f"indexed {count} sections -> {INDEX.relative_to(ROOT)}")
    if not a.query:
        return 0 if a.rebuild else (ap.print_help() or 0)
    results = search(" ".join(a.query), a.n)
    if not results:
        print("no results (try other words; this is keyword search)")
        return 1
    for path, line, heading, snip in results:
        print(f"{path}:{line}  {heading}")
        print("    " + " ".join(snip.split()))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except BrokenPipeError:
        sys.exit(0)
