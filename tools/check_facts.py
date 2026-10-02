#!/usr/bin/env python3
"""Validate dated facts against immutable source pins (offline; no live-page claims).

  python tools/check_facts.py
  python tools/check_facts.py --as-of 2026-10-02

Missing pinned sources, changed pins, expired facts, unresolved references, and
missing evidence all fail. Fetch the baseline with tools/fetch_sources.py first.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import hashlib
import math
import re
import subprocess
import sys
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path, PurePosixPath
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]
FACTS = ROOT / "references" / "facts.json"
STATUSES = {
    "documented": "explicit statement in the pinned source",
    "approximate": "the source qualifies the number as approximate",
    "default": "documented default, not an unconditional hard limit",
    "beta": "source explicitly calls the feature beta",
    "ga": "source explicitly announces general availability",
    "deprecated": "source explicitly marks the API deprecated",
}
REQUIRED = {"id", "section", "statement", "value", "unit", "status", "source", "checked_on", "expires_after", "evidence"}
SHA = re.compile(r"[0-9a-f]{40}\Z")
ID = re.compile(r"[a-z][a-z0-9]*(?:-[a-z0-9]+)*\Z")


def normalize(text: str) -> str:
    """Ignore source wrapping, but retain words, punctuation and qualifiers."""
    return " ".join(text.split())


def load_json(path: Path):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f"duplicate JSON key: {key}")
            result[key] = value
        return result
    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique,
                      parse_constant=lambda value: (_ for _ in ()).throw(ValueError(f"invalid JSON number: {value}")))


def parse_date(value: str) -> dt.date:
    if not isinstance(value, str) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", value):
        raise ValueError("expected YYYY-MM-DD")
    return dt.date.fromisoformat(value)


def valid_value(value) -> bool:
    if isinstance(value, str):
        return bool(value.strip())
    if isinstance(value, bool):
        return True
    if isinstance(value, int):
        return True
    if isinstance(value, float):
        return math.isfinite(value)
    if isinstance(value, list):
        return bool(value) and all(valid_value(v) for v in value)
    if isinstance(value, dict):
        return bool(value) and all(isinstance(k, str) and k and valid_value(v) for k, v in value.items())
    return False


@dataclass(frozen=True)
class ResolvedSource:
    text: str
    repository: str
    path: str
    url: str


class SourceResolver:
    """Resolve locked corpus/API entries or hash-pinned reviewed announcement extracts.

    git show reads the immutable blob, never a potentially edited working-tree
    document. URL sources must map to that same pinned corpus, not arbitrary web
    pages unless backed by a registered announcement extract. Engine API references
    are resolved directly in the pinned dump.
    """
    def __init__(self, root: Path = ROOT, url_sources: dict | None = None):
        self.root = root
        self.url_sources = url_sources or {}
        self.lock = load_json(root / "sources" / "lock.json")
        self.pins = self.lock["sources"]

    @lru_cache(maxsize=None)
    def blob(self, repository: str, path: str) -> str:
        pin = self.pins.get(repository, {})
        sha = pin.get("sha", "")
        if not SHA.fullmatch(sha):
            raise ValueError(f"missing/invalid pin for {repository}")
        repo = self.root / ".cache" / "sources" / repository
        if not (repo / ".git").exists():
            raise ValueError(f"pinned corpus missing for {repository}; run python tools/fetch_sources.py")
        out = subprocess.run(["git", "show", f"{sha}:{path}"], cwd=repo, text=True, capture_output=True)
        if out.returncode:
            raise ValueError(f"no pinned source {repository}@{sha[:12]}:{path}")
        return out.stdout

    def pinned_url(self, repository: str, path: str) -> str:
        url = self.pins[repository]["url"].removesuffix(".git")
        return f"{url}/blob/{self.pins[repository]['sha']}/{path}"

    @staticmethod
    def safe_path(path: str) -> str:
        if not path or path.startswith("/") or "\\" in path or any(p in (".", "..", "") for p in path.split("/")):
            raise ValueError("unsafe/empty source path")
        return PurePosixPath(path).as_posix()

    def document(self, repository: str, path: str, extensions: tuple[str, ...]) -> ResolvedSource:
        path = self.safe_path(path)
        for suffix in extensions:
            candidate = path + suffix
            try:
                return ResolvedSource(self.blob(repository, candidate), repository, candidate,
                                      self.pinned_url(repository, candidate))
            except ValueError as error:
                if "corpus missing" in str(error) or "invalid pin" in str(error):
                    raise
        raise ValueError(f"unresolved document {repository}:{path}")

    @lru_cache(maxsize=1)
    def api_dump(self) -> dict:
        return json.loads(self.blob("api-dump", "Full-API-Dump.json"))

    def engine_api(self, ref: str) -> ResolvedSource:
        parts = ref.replace(":", ".").split(".")
        if not 1 <= len(parts) <= 3 or not all(re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", p) for p in parts):
            raise ValueError(f"invalid API reference {ref}")
        data, found = self.api_dump(), None
        if parts[0] == "Enum":
            if len(parts) < 2:
                raise ValueError("API enum reference needs a name")
            enum = next((e for e in data["Enums"] if e["Name"] == parts[1]), None)
            if enum:
                found = enum if len(parts) == 2 else next((i for i in enum["Items"] if i["Name"] == parts[2]), None)
        elif len(parts) <= 2:
            classes = {c["Name"]: c for c in data["Classes"]}
            cls, seen = parts[0], set()
            while cls in classes and cls not in seen:
                seen.add(cls)
                if len(parts) == 1:
                    found = classes[cls]
                else:
                    found = next((m for m in classes[cls]["Members"] if m["Name"] == parts[1]), None)
                if found is not None:
                    break
                cls = classes[cls].get("Superclass", "")
        if found is None:
            raise ValueError(f"unresolved API reference {ref}")
        path = "Full-API-Dump.json"
        return ResolvedSource(json.dumps(found, sort_keys=True, ensure_ascii=False), "api-dump", path,
                              self.pinned_url("api-dump", path))

    @lru_cache(maxsize=None)
    def resolve(self, source: str) -> ResolvedSource:
        if source.startswith("cd:"):
            return self.document("creator-docs", "content/en-us/" + self.safe_path(source[3:]),
                                 (".md", ".yaml", "/index.md"))
        if source.startswith("api:"):
            return self.engine_api(source[4:])
        if source in self.url_sources:
            spec = self.url_sources[source]
            filename = self.safe_path(spec["file"])
            if not filename.startswith("references/fact-sources/") or not filename.endswith(".json"):
                raise ValueError("URL evidence must be in references/fact-sources/*.json")
            path = (self.root / filename).resolve()
            if not path.is_relative_to((self.root / "references" / "fact-sources").resolve()):
                raise ValueError("URL evidence path escapes its directory")
            raw = path.read_bytes()
            if hashlib.sha256(raw).hexdigest() != spec.get("sha256"):
                raise ValueError("URL evidence hash mismatch; reverify the dated source")
            extract = load_json(path)
            if extract.get("source") != source:
                raise ValueError("URL evidence source mismatch")
            parse_date(extract.get("published_on"))
            parse_date(extract.get("retrieved_on"))
            return ResolvedSource(json.dumps(extract, ensure_ascii=False), "url", filename, source)
        url = urlsplit(source)
        if url.scheme != "https" or url.query or url.username or url.password or url.port:
            raise ValueError("source must use cd:, api:, or a supported HTTPS corpus URL")
        path = unquote(url.path).strip("/")
        if url.netloc == "create.roblox.com" and path.startswith("docs/"):
            return self.resolve("cd:" + path[5:])
        if url.netloc == "luau.org":
            return self.document("luau-site", "src/content/docs/" + self.safe_path(path), (".md", ".mdx"))
        if url.netloc == "github.com":
            for repository, pin in self.pins.items():
                repo_path = urlsplit(pin["url"].removesuffix(".git")).path.strip("/")
                prefix = f"{repo_path}/blob/{pin['sha']}/"
                if path.startswith(prefix):
                    filename = self.safe_path(path[len(prefix):])
                    # The URL is a corpus document, not an arbitrary file in the source repository.
                    allowed = ((repository == "creator-docs" and filename.startswith("content/en-us/") and
                                filename.endswith((".md", ".yaml", ".json"))) or
                               (repository == "luau-site" and filename.startswith("src/content/docs/") and
                                filename.endswith((".md", ".mdx"))))
                    if allowed:
                        text = self.blob(repository, filename)
                        # Decode JSON string escapes so excerpts match the actual source text.
                        if filename.endswith(".json"):
                            text = json.dumps(json.loads(text), ensure_ascii=False, indent=2).replace("\\n", "\n")
                        return ResolvedSource(text, repository, filename, self.pinned_url(repository, filename))
        raise ValueError("URL does not resolve to a document in the pinned corpus")


def validate(data, *, as_of: dt.date | None = None, resolver: SourceResolver | None = None) -> list[str]:
    """Validate structure and expiry; additionally validate pins/evidence with a resolver."""
    as_of = as_of or dt.datetime.now(dt.timezone.utc).date()
    errors = []
    if not isinstance(data, dict):
        return ["facts must be a JSON object"]
    if data.get("schema_version") != 1 or isinstance(data.get("schema_version"), bool):
        errors.append("schema_version must be 1")
    pins = data.get("source_pins")
    if not isinstance(pins, dict) or not pins:
        errors.append("source_pins must be a nonempty object")
        pins = {}
    for repo, sha in pins.items():
        if not isinstance(sha, str) or not SHA.fullmatch(sha):
            errors.append(f"invalid source pin: {repo}")
        elif resolver and resolver.pins.get(repo, {}).get("sha") != sha:
            errors.append(f"source pin changed for {repo}; reverify facts before updating source_pins")
    urls = data.get("url_sources", {})
    if not isinstance(urls, dict):
        errors.append("url_sources must be an object")
    else:
        for url, spec in urls.items():
            if (not isinstance(url, str) or not url.startswith("https://") or not isinstance(spec, dict) or
                    not isinstance(spec.get("file"), str) or
                    not isinstance(spec.get("sha256"), str) or
                    not re.fullmatch(r"[0-9a-f]{64}", spec.get("sha256", ""))):
                errors.append("invalid URL source pin")
    facts = data.get("facts")
    if not isinstance(facts, list) or not facts:
        return errors + ["facts must be a nonempty array"]
    seen = set()
    for index, fact in enumerate(facts):
        if not isinstance(fact, dict):
            errors.append(f"fact[{index}] must be an object")
            continue
        label = fact.get("id", f"fact[{index}]")
        missing = REQUIRED - fact.keys()
        if missing:
            errors.append(f"{label}: missing {', '.join(sorted(missing))}")
        fid = fact.get("id")
        if not isinstance(fid, str) or not ID.fullmatch(fid):
            errors.append(f"fact[{index}]: invalid id")
        elif fid in seen:
            errors.append(f"{fid}: duplicate id")
        else:
            seen.add(fid)
        for field in ("section", "statement", "unit", "source"):
            if not isinstance(fact.get(field), str) or not fact[field].strip():
                errors.append(f"{label}: {field} must be a nonempty string")
        if not valid_value(fact.get("value")):
            errors.append(f"{label}: value must be a nonempty finite JSON value")
        status = fact.get("status")
        if not isinstance(status, str) or status not in STATUSES:
            errors.append(f"{label}: unknown status {status!r}")
        lifetime = fact.get("expires_after")
        valid_lifetime = type(lifetime) is int and 1 <= lifetime <= 366
        if not valid_lifetime:
            errors.append(f"{label}: expires_after must be an integer from 1 to 366 days")
        try:
            checked = parse_date(fact.get("checked_on"))
            if checked > as_of:
                errors.append(f"{label}: checked_on is in the future relative to {as_of}")
            if valid_lifetime and as_of >= checked + dt.timedelta(days=lifetime):
                errors.append(f"{label}: expired on {checked + dt.timedelta(days=lifetime)}; reverify source")
        except (ValueError, TypeError, OverflowError):
            errors.append(f"{label}: invalid checked_on or expiry date; expected representable YYYY-MM-DD")
        evidence = fact.get("evidence")
        valid_evidence = (isinstance(evidence, list) and bool(evidence) and
                          all(isinstance(e, str) and len(normalize(e)) >= 8 for e in evidence))
        if not valid_evidence:
            errors.append(f"{label}: evidence must contain source excerpts of at least 8 characters")
        if status in ("beta", "ga", "deprecated") and valid_evidence:
            markers = {"beta": r"\bbeta\b", "ga": r"\b(generally available|general availability|full release)\b",
                       "deprecated": r"\bdeprecated\b"}
            if not re.search(markers[status], " ".join(evidence), flags=re.I):
                errors.append(f"{label}: {status} requires explicit status evidence")
        if resolver and isinstance(fact.get("source"), str):
            try:
                source = resolver.resolve(fact["source"])
                if source.repository != "url" and source.repository not in pins:
                    errors.append(f"{label}: source repository {source.repository} is not in source_pins")
                if valid_evidence:
                    for excerpt in evidence:
                        if normalize(excerpt) not in normalize(source.text):
                            errors.append(f"{label}: evidence not found in pinned source: {excerpt[:90]}")
            except (ValueError, KeyError, OSError, TypeError) as error:
                errors.append(f"{label}: {error}")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--as-of", type=parse_date, help="reproducible YYYY-MM-DD validation date; defaults to UTC today")
    parser.add_argument("--facts", type=Path, default=FACTS)
    args = parser.parse_args()
    try:
        data = load_json(args.facts)
        errors = validate(data, as_of=args.as_of, resolver=SourceResolver(url_sources=data.get("url_sources", {}) if isinstance(data, dict) else {}))
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"ERROR {error}", file=sys.stderr)
        return 1
    for error in errors:
        print("ERROR", error)
    count = len(data.get("facts", [])) if isinstance(data, dict) else 0
    print(f"facts: {count} checked, {len(errors)} error(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
