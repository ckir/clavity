#!/usr/bin/env python3
"""Structural (1-5) and README parity (6-7) checks for the one-page GitHub Pages site.

Usage: check_site.py --site site --readme README.md
Prints one `CHECK<n>: <detail>` line per problem. Exit 0 clean, 1 on any
problem, 2 when an input cannot be read (`CANNOT_ANSWER: <what>` on stderr).
Standard library only.

Maintainer notes. Checks: 1 no root-relative refs (HTML, CSS, inline styles);
2 every local ref and anchor resolves inside site/; 3 repo links stay on the
allowlist (repo root, /blob/main, /tree/main, /releases, /issues, the one raw
pairing URL); 4 rasters under site/assets/ are <= 300 KB; 5 no third-party
loads; 6 #install commands, copy buttons and pairing links equal the README;
7 the three data-readme-quote texts equal the README. Two README facts are
hard-coded here: the pairing path (RAW_PAIRING_PATH) and the two waiver opening
phrases (WAIVER_OPENINGS). Exit codes: 0 clean, 1 problems, 2 unreadable input.
Any <base href> is a problem (5 absolute, 2 relative); `claude plugin` text is
allowed only inside <code data-cmd> in #install, anywhere else on the page is
check 6 (adjacent block elements are joined with a space, so a heading "Claude"
followed by a paragraph starting "Plugin" is flagged: reword it); a repeated attribute keeps its first value (as HTML5 does); README
folding strips * and ` and understands only inline [text](url) links.
Pages nested deeper than 512 elements fail closed with exit 2.
Page loads that must not be third-party: every <link href> except canonical, and the
attributes src, srcset, poster, object data, background, and href on svg
image/use (also xlink:href, feImage href), imagesrcset and quoted image-set()
strings (a quoted string after `image-set(` in the same declaration, up to `;`,
`{` or `}`, counts as an image-set URL: put other strings in a separate declaration).
Form action, a ping and meta refresh are navigation and NOT checked.
Unit tests: python3 -m unittest discover -s .github/site-checks
"""

import argparse
import html
import posixpath
import re
import sys
from collections import Counter
from dataclasses import dataclass, field
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit

Problem = tuple[int, str]  # (check_number, "<path>: <detail>")

VOID_TAGS = frozenset(
    "area base br col embed hr img input link meta source track wbr".split()
)
RASTER_SUFFIXES = frozenset({".png", ".jpg", ".jpeg", ".webp", ".avif", ".gif"})
MAX_RASTER_BYTES = 300 * 1024
MAX_NESTING = 512  # Chromium's open-element limit; deeper input fails closed

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
CSS_IMAGE_SET = re.compile(r"""image-set\(([^;{}]*)""", re.IGNORECASE)
CSS_QUOTED = re.compile(r"""(?<!url\()(['"])(.*?)\1""", re.IGNORECASE)
SCHEME = re.compile(r"^[a-zA-Z][a-zA-Z0-9+.\-]*:")

# Tags whose boundaries separate words in quote text; inline tags add nothing.
BLOCK_TAGS = frozenset(
    "address article aside blockquote br dd details div dl dt fieldset figcaption "
    "figure footer form h1 h2 h3 h4 h5 h6 header hr li main nav ol p pre section "
    "table tbody td tfoot th thead tr ul".split()
)
QUOTE_KEYS = ("warning", "waiver-1", "waiver-2")
WAIVER_OPENINGS = {
    "waiver-1": "All the above can be waived by prompts.",
    "waiver-2": "In case you have problem to start agy",
}
COMMAND_PREFIX = "claude plugin"
CLAUDE_PLUGIN = re.compile(r"claude\s+plugin", re.IGNORECASE)
PAIRING_FILE = "agy-pairing-INSTALL.md"


class CannotAnswer(Exception):
    """An input the checks need is missing or unreadable (fail closed)."""


@dataclass
class Capture:
    """Text (and `<a href>`s) collected while one element is open."""

    kind: str  # quote | cmd
    key: str  # data-readme-quote value ("" otherwise)
    li: int | None  # enclosing `<li>` of an #install element
    parts: list[str] = field(default_factory=list)
    hrefs: list[str] = field(default_factory=list)

    @property
    def text(self) -> str:
        return fold("".join(self.parts))


@dataclass
class Frame:
    """One open element: its tag, #install context and the captures it started."""

    tag: str
    in_install: bool
    li: int | None
    captures: list[Capture]


class PageParser(HTMLParser):
    """Collects elements, ids, quote/command text and #install button payloads."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.stack: list[Frame] = []
        self.elements: list[tuple[str, dict[str, str]]] = []
        self.ids: set[str] = set()
        self.lis = 0
        self.quotes: list[Capture] = []
        self.commands: list[Capture] = []  # <code data-cmd> in #install
        self.copies: list[tuple[int | None, str]] = []  # (li, data-copy) in #install
        self.page_text: list[str] = []  # all text except <code data-cmd> in #install
        self.hrefs: list[tuple[str, bool]] = []  # (href, inside #install), any tag
        self.inline_css: list[str] = []  # <style> texts and style="" values

    def _active(self) -> list[Capture]:
        return [c for frame in self.stack for c in frame.captures]

    def _space(self) -> None:
        self.page_text.append(" ")
        for capture in self._active():
            capture.parts.append(" ")

    def handle_starttag(self, tag, attrs):
        values: dict[str, str] = {}
        for name, value in attrs:  # HTML5: the first of a repeated attribute wins
            values.setdefault(name, value or "")
        self.elements.append((tag, values))
        if "id" in values:
            self.ids.add(values["id"])
        parent = self.stack[-1] if self.stack else None
        in_install = (parent is not None and parent.in_install) or (
            values.get("id") == "install"
        )
        li = parent.li if parent else None
        if tag == "li" and in_install:
            li = self.lis
            self.lis += 1
        captures: list[Capture] = []
        if "data-readme-quote" in values:
            captures.append(Capture("quote", values["data-readme-quote"], None))
            self.quotes.append(captures[-1])
        if "href" in values:
            self.hrefs.append((values["href"], in_install))
        if "style" in values:
            self.inline_css.append(values["style"])
        if tag == "style":
            self.inline_css.append("")
        if in_install:
            if "data-cmd" in values:
                captures.append(Capture("cmd", "", li))
                self.commands.append(captures[-1])
            if "data-copy" in values:
                self.copies.append((li, values["data-copy"]))
        if tag == "a" and "href" in values:
            for capture in self._active():
                if capture.kind == "quote":
                    capture.hrefs.append(values["href"])
        if tag not in VOID_TAGS:
            if len(self.stack) >= MAX_NESTING:
                raise CannotAnswer(
                    f"page nests elements deeper than {MAX_NESTING} levels"
                )
            self.stack.append(Frame(tag, in_install, li, captures))
        if tag in BLOCK_TAGS:
            self._space()

    def handle_endtag(self, tag):
        if tag in VOID_TAGS or not any(f.tag == tag for f in self.stack):
            return
        if tag in BLOCK_TAGS:
            self._space()
        while self.stack.pop().tag != tag:
            pass

    def handle_data(self, data):
        if self.stack and self.stack[-1].tag == "style":
            self.inline_css[-1] += data
        active = self._active()
        if not any(c.kind == "cmd" for c in active):
            self.page_text.append(data)
        for capture in active:
            capture.parts.append(data)


def parse_page(text: str) -> PageParser:
    parser = PageParser()
    parser.feed(text)
    parser.close()
    return parser


def fold(text: str) -> str:
    """Decode entities, fold curly quotes to straight, collapse whitespace."""
    text = html.unescape(text)
    text = text.translate(
        str.maketrans({"\u2018": "'", "\u2019": "'", "\u201c": '"', "\u201d": '"'})
    )
    return " ".join(text.split())


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
    ref = ref.strip()
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
        for attr in ("href", "xlink:href"):
            if attr in attrs:
                is_link = attr == "href" and tag == "link" and "canonical" not in rels
                is_load = is_link or tag in ("image", "use", "feimage")
                refs.append((attr, attrs[attr], is_load))
        if "src" in attrs:
            refs.append(("src", attrs["src"], True))
        for attr in ("poster", "data", "background"):
            if attr in attrs and (attr != "data" or tag == "object"):
                refs.append((attr, attrs[attr], True))
        for attr in ("srcset", "imagesrcset"):
            if attr in attrs:
                refs.extend((attr, url, True) for url in srcset_urls(attrs[attr]))
        if "content" in attrs and classify(attrs["content"]) == "root":
            refs.append(("content", attrs["content"], False))
    return refs


def css_refs(css: str) -> list[tuple[str, str, bool]]:
    refs = [("url()", m.group(2).strip(), True) for m in CSS_URL.finditer(css)]
    refs += [("@import", m.group(2).strip(), True) for m in CSS_IMPORT.finditer(css)]
    for group in CSS_IMAGE_SET.finditer(css):
        for m in CSS_QUOTED.finditer(group.group(1)):
            refs.append(("image-set()", m.group(2).strip(), True))
    return refs


def check_base(parser: PageParser, name: str, problems: list[Problem]) -> None:
    """A <base href> re-bases every relative URL, so the other checks would be void."""
    for tag, attrs in parser.elements:
        if tag != "base" or "href" not in attrs:
            continue
        value = attrs["href"]
        if classify(value) == "absolute":
            problems.append((5, f"{name}: <base href> {value!r} re-bases every URL"))
        else:
            problems.append((2, f"{name}: <base href> {value!r} voids relative checks"))


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


def check_structure(site: Path) -> list[Problem]:
    """Run structural checks 1-5 over every page and stylesheet in site/."""
    read_text(site / "index.html", "site/index.html")
    problems: list[Problem] = []
    for page in sorted(site.glob("*.html")):
        parser = parse_page(read_text(page, f"site/{page.name}"))
        check_refs(html_refs(parser), parser.ids, site, page.name, problems)
        check_base(parser, page.name, problems)
        for css in parser.inline_css:
            label = f"{page.name} (inline style)"
            check_refs(css_refs(css), set(), site, label, problems)
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


def readme_lines(readme_text: str) -> list[str]:
    return readme_text.splitlines()  # copes with LF and CRLF alike


def readme_install_commands(readme_text: str) -> list[str]:
    """`claude plugin` lines of the first fenced block with `marketplace add`."""
    blocks: list[list[str]] = []
    inside = False
    for line in readme_lines(readme_text):
        if line.lstrip().startswith("```"):
            inside = not inside
            if inside:
                blocks.append([])
        elif inside:
            blocks[-1].append(line)
    for block in blocks:
        if any("claude plugin marketplace add" in line for line in block):
            break
    else:
        raise CannotAnswer(
            "README.md has no fenced block with `claude plugin marketplace add`"
        )
    commands = []
    for line in block:
        line = line.strip()
        if line.startswith(COMMAND_PREFIX):
            commands.append(re.sub(r"\s+#.*$", "", line).strip())
    return commands


def readme_warning_lines(readme_text: str) -> list[str]:
    """Lines between `### WARNING` and the next heading (heading excluded)."""
    lines = readme_lines(readme_text)
    for start, line in enumerate(lines):
        if line.strip() == "### WARNING":
            break
    else:
        raise CannotAnswer("README.md has no `### WARNING` section")
    body = []
    for line in lines[start + 1 :]:
        if re.match(r"#{1,3}\s", line):
            break
        body.append(line)
    return body


def readme_pairing_url(readme_text: str) -> str:
    """The raw pairing URL from the markdown link in the `### WARNING` section."""
    link = re.compile(
        r"\[[^\]]*\]\((https://raw\.githubusercontent\.com/ckir/clavity/[^)\s]*)\)"
    )
    for line in readme_warning_lines(readme_text):
        match = link.search(line)
        if match:
            return match.group(1)
    raise CannotAnswer(
        "README.md `### WARNING` section has no inline raw.githubusercontent.com link "
        "(only inline markdown links [text](url) are understood)"
    )


def plain(markdown: str) -> str:
    """Drop `[text](url)` link syntax (keeping text) and `*` emphasis, then fold."""
    markdown = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", markdown)
    return fold(markdown.replace("*", "").replace("`", ""))


def readme_quote_units(readme_text: str) -> dict[str, str]:
    """Folded README text for the `warning`, `waiver-1` and `waiver-2` quotes."""
    units = {"warning": plain(" ".join(readme_warning_lines(readme_text)))}
    if not units["warning"]:
        raise CannotAnswer("README.md `### WARNING` section is empty")
    for key, opening in WAIVER_OPENINGS.items():
        for line in readme_lines(readme_text):
            if line.startswith(opening):
                units[key] = plain(line)
                break
        else:
            raise CannotAnswer(f"README.md has no line starting {opening!r}")
    return units


def multiset_detail(page: list[str], readme: list[str]) -> list[str]:
    missing = Counter(readme) - Counter(page)
    extra = Counter(page) - Counter(readme)
    return [f"README has {c!r} x{n} more than the page" for c, n in missing.items()] + [
        f"page has {c!r} x{n} more than the README" for c, n in extra.items()
    ]


def is_pairing_link(href: str) -> bool:
    """True for a raw.githubusercontent.com link or one ending agy-pairing-INSTALL.md."""
    try:
        parts = urlsplit(href.strip())
        host = parts.hostname
    except ValueError:
        return False
    return host == "raw.githubusercontent.com" or parts.path.endswith(PAIRING_FILE)


def flag_pairing_links(parser: PageParser, pairing: str, flag) -> None:
    """Every pairing-looking link equals the README URL; one sits in #install."""
    in_install = 0
    for href, inside in parser.hrefs:
        if not is_pairing_link(href):
            continue
        if href != pairing:
            flag(f"pairing link {href!r} is not {pairing!r}")
        elif inside:
            in_install += 1
    if "install" in parser.ids and not in_install:
        flag("Install section holds no pairing link equal to the README's")


def check_install(parser: PageParser, readme_text: str, name: str) -> list[Problem]:
    """Check 6: install commands, copy buttons and pairing link match the README."""
    problems: list[Problem] = []

    def flag(detail: str) -> None:
        problems.append((6, f"{name}: {detail}"))

    if "install" not in parser.ids:
        flag('no element with id="install"')
    page_cmds = [c.text for c in parser.commands]
    readme_cmds = readme_install_commands(readme_text)
    if not page_cmds:
        flag("Install section holds no <code data-cmd> commands")
    if sorted(page_cmds) != sorted(readme_cmds):
        for detail in multiset_detail(page_cmds, readme_cmds):
            flag(detail)
    for index in {c.li for c in parser.commands} | {li for li, _ in parser.copies}:
        cmds = [c.text for c in parser.commands if c.li == index]
        copies = [value for li, value in parser.copies if li == index]
        if index is None or len(cmds) != 1 or len(copies) != 1:
            flag(
                f"<li> #{index} must hold exactly one data-cmd and one data-copy "
                f"(has {len(cmds)} and {len(copies)})"
            )
        elif copies[0] != cmds[0]:
            flag(f"data-copy {copies[0]!r} differs from displayed command {cmds[0]!r}")
    pairing = readme_pairing_url(readme_text)
    flag_pairing_links(parser, pairing, flag)
    text = fold("".join(parser.page_text))
    hit = CLAUDE_PLUGIN.search(text)
    if hit:
        near = text[hit.start() : hit.start() + 60]
        flag(
            f"page text mentions `claude plugin` outside an #install data-cmd: {near!r}"
        )
    for quote in (q for q in parser.quotes if q.key == "warning"):
        if len(quote.hrefs) != 1:
            flag(f"warning quote must hold exactly one <a> (has {len(quote.hrefs)})")
        elif quote.hrefs[0] != pairing:
            flag(f"pairing href {quote.hrefs[0]!r} is not {pairing!r}")
    return problems


def check_quotes(parser: PageParser, readme_text: str, name: str) -> list[Problem]:
    """Check 7: exactly three data-readme-quote elements equal to the README units."""
    problems: list[Problem] = []
    units = readme_quote_units(readme_text)
    keys = sorted(q.key for q in parser.quotes)
    if keys != sorted(QUOTE_KEYS):
        problems.append(
            (
                7,
                f"{name}: data-readme-quote values are {keys}, need {sorted(QUOTE_KEYS)}",
            )
        )
    for quote in parser.quotes:
        if quote.key in units and (not quote.text or quote.text != units[quote.key]):
            problems.append(
                (
                    7,
                    f"{name}: quote {quote.key!r} is {quote.text!r}, README has {units[quote.key]!r}",
                )
            )
    return problems


def check_parity(site: Path, readme: Path) -> list[Problem]:
    """Checks 6-7: site/index.html against the README."""
    parser = parse_page(read_text(site / "index.html", "site/index.html"))
    readme_text = read_text(readme, "README.md")
    return check_install(parser, readme_text, "index.html") + check_quotes(
        parser, readme_text, "index.html"
    )


def check_site(site: Path, readme: Path) -> list[Problem]:
    """Run every check: structure (1-5), then README parity (6-7)."""
    return check_structure(site) + check_parity(site, readme)


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
