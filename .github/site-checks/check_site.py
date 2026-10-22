#!/usr/bin/env python3
"""Structural checks for the one-page GitHub Pages site (checks 1-5).

Usage: check_site.py --site site --readme README.md
Prints one `CHECK<n>: <detail>` line per problem. Exit 0 clean, 1 on any
problem, 2 when an input cannot be read (`CANNOT_ANSWER: <what>` on stderr).
Standard library only.
"""

import argparse
import posixpath
import re
import sys
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit

Problem = tuple[int, str]  # (check_number, "<path>: <detail>")

VOID_TAGS = frozenset(
    "area base br col embed hr img input link meta source track wbr".split()
)
LOAD_LINK_RELS = frozenset({"stylesheet", "icon", "preload"})
RASTER_SUFFIXES = frozenset({".png", ".jpg", ".jpeg", ".webp", ".avif", ".gif"})
MAX_RASTER_BYTES = 300 * 1024

REPO_PATH = "/ckir/clavity"
GITHUB_PREFIXES = (
    f"{REPO_PATH}/blob/main",
    f"{REPO_PATH}/tree/main",
    f"{REPO_PATH}/releases",
    f"{REPO_PATH}/issues",
)
RAW_PAIRING_PATH = (
    f"{REPO_PATH}/refs/heads/main/clavity-dotnet/pairing/agy-pairing-INSTALL.md"
)

CSS_URL = re.compile(r"""url\(\s*(['"]?)(.*?)\1\s*\)""", re.IGNORECASE)
CSS_IMPORT = re.compile(r"""@import\s+(['"])(.*?)\1""", re.IGNORECASE)
SCHEME = re.compile(r"^[a-zA-Z][a-zA-Z0-9+.\-]*:")


class CannotAnswer(Exception):
    """An input the checks need is missing or unreadable (fail closed)."""


class PageParser(HTMLParser):
    """Collects elements (tag, attrs) and element ids via an explicit stack."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.stack: list[str] = []
        self.elements: list[tuple[str, dict[str, str]]] = []
        self.ids: set[str] = set()

    def handle_starttag(self, tag, attrs):
        values = {name: value or "" for name, value in attrs}
        self.elements.append((tag, values))
        if "id" in values:
            self.ids.add(values["id"])
        if tag not in VOID_TAGS:
            self.stack.append(tag)

    def handle_endtag(self, tag):
        if tag in VOID_TAGS or tag not in self.stack:
            return
        while self.stack.pop() != tag:
            pass


def classify(value: str) -> str:
    """anchor | empty | ignore | absolute | root | relative."""
    value = value.strip()
    if not value:
        return "empty"
    if value.startswith("#"):
        return "anchor"
    if value.startswith("//") or value.lower().startswith(("http://", "https://")):
        return "absolute"
    if value.startswith("/"):
        return "root"
    if SCHEME.match(value):  # data: mailto: tel: javascript: and the like
        return "ignore"
    return "relative"


def srcset_urls(value: str) -> list[str]:
    urls = []
    for candidate in value.split(","):
        parts = candidate.split()
        if parts:
            urls.append(parts[0])
    return urls


def resolve(ref: str, referrer: str) -> str:
    """Resolve a relative ref against the referring file's directory (site-relative).

    Returns a normalised posix path; one starting with `..` escapes site/.
    """
    path = unquote(ref.split("#", 1)[0].split("?", 1)[0])
    base = posixpath.dirname(referrer)
    return posixpath.normpath(posixpath.join(base, path))


def github_problem(url: str) -> str | None:
    """Return why an absolute URL into the clavity repo is not allowed, else None."""
    try:
        parts = urlsplit(url)
    except ValueError:
        return "unparseable URL"
    host, path = parts.hostname, parts.path
    if host == "github.com" and path.lower().startswith(REPO_PATH):
        if path in (REPO_PATH, REPO_PATH + "/"):
            return None
        for prefix in GITHUB_PREFIXES:
            if path.startswith(prefix) and (
                len(path) == len(prefix) or path[len(prefix)] == "/"
            ):
                return None
        return "github.com URL is not the repo root, /blob/main, /tree/main, /releases or /issues"
    if host == "raw.githubusercontent.com" and path.lower().startswith(REPO_PATH):
        if path == RAW_PAIRING_PATH:
            return None
        return "raw.githubusercontent.com URL is not the pairing INSTALL file"
    return None


def read_text(path: Path, shown: str) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        raise CannotAnswer(
            f"{shown} cannot be read ({exc.__class__.__name__})"
        ) from exc


def check_refs(
    refs: list[tuple[str, str, bool]],
    ids: set[str],
    site: Path,
    name: str,
    problems: list[Problem],
) -> None:
    """Run checks 1, 2, 3 and 5 over (attr, value, is_load) references of one file."""
    for attr, value, is_load in refs:
        kind = classify(value)
        if kind == "root":
            problems.append((1, f"{name}: root-relative {attr} {value!r}"))
        elif kind == "absolute":
            if is_load:
                problems.append((5, f"{name}: third-party load via {attr} {value!r}"))
            if attr == "href":
                why = github_problem(value)
                if why:
                    problems.append((3, f"{name}: {why}: {value!r}"))
        elif kind == "anchor":
            if value.strip() != "#" and value.strip()[1:] not in ids:
                problems.append(
                    (2, f"{name}: anchor {value!r} matches no id in the page")
                )
        elif kind == "relative":
            target = resolve(value, name)
            if target == ".." or target.startswith("../"):
                number = 3 if attr == "href" else 2
                problems.append(
                    (number, f"{name}: {attr} {value!r} climbs out of site/")
                )
                continue
            full = site / target
            if not (
                full.is_file() or (full.is_dir() and (full / "index.html").is_file())
            ):
                problems.append(
                    (2, f"{name}: {attr} {value!r} does not resolve to a file in site/")
                )


def html_refs(parser: PageParser) -> list[tuple[str, str, bool]]:
    """(attr, value, is_load) for every reference-bearing attribute."""
    refs = []
    for tag, attrs in parser.elements:
        rels = set(attrs.get("rel", "").lower().split())
        if "href" in attrs:
            is_load = tag == "link" and bool(rels & LOAD_LINK_RELS)
            refs.append(("href", attrs["href"], is_load))
        if "src" in attrs:
            refs.append(("src", attrs["src"], True))
        if "srcset" in attrs:
            refs.extend(("srcset", url, True) for url in srcset_urls(attrs["srcset"]))
        if "content" in attrs and classify(attrs["content"]) == "root":
            refs.append(("content", attrs["content"], False))
    return refs


def css_refs(css: str) -> list[tuple[str, str, bool]]:
    refs = [("url()", m.group(2).strip(), True) for m in CSS_URL.finditer(css)]
    refs += [("@import", m.group(2).strip(), True) for m in CSS_IMPORT.finditer(css)]
    return refs


def check_rasters(site: Path, problems: list[Problem]) -> None:
    assets = site / "assets"
    if not assets.is_dir():
        return
    for path in sorted(assets.rglob("*")):
        if path.is_file() and path.suffix.lower() in RASTER_SUFFIXES:
            size = path.stat().st_size
            if size > MAX_RASTER_BYTES:
                rel = path.relative_to(site).as_posix()
                problems.append((4, f"{rel}: {size} bytes exceeds {MAX_RASTER_BYTES}"))


def check_site(site: Path, readme: Path) -> list[Problem]:
    """Run the structural checks. `readme` is reserved for the parity checks (6-7)."""
    read_text(site / "index.html", "site/index.html")
    problems: list[Problem] = []
    for page in sorted(site.glob("*.html")):
        parser = PageParser()
        parser.feed(read_text(page, f"site/{page.name}"))
        parser.close()
        check_refs(html_refs(parser), parser.ids, site, page.name, problems)
    for sheet in sorted(site.glob("*.css")):
        check_refs(
            css_refs(read_text(sheet, f"site/{sheet.name}")),
            set(),
            site,
            sheet.name,
            problems,
        )
    check_rasters(site, problems)
    return problems


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--site", type=Path, required=True)
    ap.add_argument("--readme", type=Path, required=True)
    args = ap.parse_args(argv)
    try:
        problems = check_site(args.site, args.readme)
    except CannotAnswer as exc:
        print(f"CANNOT_ANSWER: {exc}", file=sys.stderr)
        return 2
    for number, detail in problems:
        print(f"CHECK{number}: {detail}")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
