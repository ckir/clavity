# Copyright (c) 2026 Costas Kirgoussios
#
# This software is licensed under the PolyForm Noncommercial License 1.0.0.
# You may obtain a copy of the License at:
# https://polyformproject.org/licenses/noncommercial/1.0.0/

"""Unit tests for check_site.py (structural checks 1-5, README parity checks 6-7)."""

import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

try:
    import yaml
except ImportError:  # CI installs nothing; WorkflowShape is skipped without PyYAML.
    yaml = None

from check_site import (
    CannotAnswer,
    check_site,
    check_structure,
    fold,
    parse_page,
    readme_install_commands,
    readme_quote_units,
)

SCRIPT = Path(__file__).with_name("check_site.py")
yaml_available = yaml is not None
WORKFLOW = Path(__file__).resolve().parents[1] / "workflows" / "pages.yml"
PAGES_PATHS = [
    "site/**",
    "README.md",
    ".github/workflows/pages.yml",
    ".github/site-checks/**",
]
ACTION_NAMES = {
    "actions/checkout",
    "actions/upload-pages-artifact",
    "actions/deploy-pages",
}
ACTION_REF = re.compile(r"^actions/(checkout|upload-pages-artifact|deploy-pages)@v\d+$")

def make_site(
    tmp: Path, html: str, css: str = "", files: dict[str, bytes] | None = None
) -> Path:
    """Write index.html, style.css and any extra files under tmp/site."""
    site = tmp / "site"
    site.mkdir(parents=True, exist_ok=True)
    (site / "index.html").write_text(html, encoding="utf-8")
    (site / "style.css").write_text(css, encoding="utf-8")
    for name, data in (files or {}).items():
        path = site / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    return site


def page(body: str, head: str = "") -> str:
    return (
        f"<!doctype html><html lang='en'><head>{head}</head><body>{body}</body></html>"
    )


CLEAN_COMMANDS = [
    "claude plugin marketplace add ckir/clavity",
    "claude plugin install clavity@clavity",
    "claude plugin install agy-autotrain@clavity",
    "claude plugin install commonmemory@clavity",
    "claude plugin install review-relay@clavity",
]
README_COMMANDS = [
    CLEAN_COMMANDS[0],
    CLEAN_COMMANDS[1] + "          # clavity-dotnet",
    *CLEAN_COMMANDS[2:],
]
WAIVER_1 = (
    "All the above can be waived by prompts. "
    'Say for example "Waive agy for this step" and claude will execute the step solo.'
)
WAIVER_2 = (
    "In case you have problem to start agy (e.g. quota exhausted, Google's servers "
    "are down) you can switch to subagents mode by prompt."
)

def make_readme(
    commands=README_COMMANDS,
    waivers=(WAIVER_1, WAIVER_2),
    eol="\n",
) -> str:
    """A README shaped like the real one (fenced install block, waivers)."""
    lines = ["# Title", "", "## HUMAN ONLY", ""]
    lines += [
        "### What it does",
        "Prose.",
        "",
        *waivers,
        "",
        "### How to start",
    ]
    if commands is not None:
        lines += ["", "```", *commands, "```"]
    return eol.join(lines) + eol


def install_html(commands=CLEAN_COMMANDS) -> str:
    items = "".join(
        f"<li><code data-cmd>{c}</code> <span>note</span>"
        f'<button data-copy="{c}">Copy</button></li>'
        for c in commands
    )
    return f'<section id="install"><ul>{items}</ul></section>'


def index_body(
    install: str | None = None,
    w1: str = WAIVER_1,
    w2: str = WAIVER_2,
) -> str:
    return (
        (install if install is not None else install_html())
        + f"<p data-readme-quote='waiver-1'>{w1}</p>"
        + f"<p data-readme-quote='waiver-2'>{w2}</p>"
    )


def quote1_body(quote_html: str) -> str:
    """index_body with a hand-built waiver-1 element in place of the default <p>."""
    return (
        install_html()
        + quote_html
        + f"<p data-readme-quote='waiver-2'>{WAIVER_2}</p>"
    )


def run_checker(site: Path, readme: Path):
    return subprocess.run(
        [sys.executable, str(SCRIPT), "--site", str(site), "--readme", str(readme)],
        capture_output=True,
        text=True,
    )


class StructuralChecks(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.tmp = Path(self._tmp.name)
        self.count = 0
        self.readme = self.tmp / "README.md"
        self.readme.write_text(make_readme(), encoding="utf-8")

    def problems(self, html, css="", files=None):
        self.count += 1
        site = make_site(self.tmp / f"case{self.count}", html, css, files)
        return check_structure(site)

    def numbers(self, html, css="", files=None):
        return [n for n, _ in self.problems(html, css, files)]

    # -- clean -------------------------------------------------------------

    def test_clean_site_has_no_problems(self):
        html = page(
            '<a href="#top">up</a><div id="top"></div><img src="./assets/a.webp">',
            '<link rel=stylesheet href="./style.css">',
        )
        self.assertEqual(self.problems(html, files={"assets/a.webp": b"x"}), [])

    # -- check 1 -----------------------------------------------------------

    def test_root_relative_href_src_srcset_content_flagged(self):
        cases = {
            "href": '<a href="/x">a</a>',
            "src": '<img src="/x.png">',
            "srcset": '<img srcset="/x.png 1x">',
            "content": '<meta name="m" content="/x">',
        }
        for attr, body in cases.items():
            with self.subTest(attr=attr):
                self.assertIn(1, self.numbers(page(body)))

    def test_css_url_root_relative_flagged_with_and_without_quotes(self):
        for url in ("url(/x.png)", 'url("/x.png")', "url('/x.png')"):
            with self.subTest(url=url):
                self.assertIn(
                    1, self.numbers(page(""), css=f"a {{ background: {url}; }}")
                )

    def test_inline_style_is_scanned(self):
        cases = {
            "import": (
                page(
                    "", "<style>@import url(https://fonts.googleapis.com/css);</style>"
                ),
                5,
            ),
            "attr": (
                page("", "").replace(
                    "<body>",
                    "<body style='background:url(https://evil.example/x.png)'>",
                ),
                5,
            ),
            "root": (page("<p style='background:url(/x.png)'>a</p>"), 1),
            "missing": (page("<style>a{background:url(./nope.png)}</style>"), 2),
        }
        for name, (html, number) in cases.items():
            with self.subTest(name=name):
                self.assertIn(number, self.numbers(html))

    def test_base_href_is_flagged(self):
        absolute = page("", "<base href='https://attacker.example/'>")
        self.assertIn(5, self.numbers(absolute))
        self.assertIn(5, self.numbers(page("", "<base href='//attacker.example/'>")))
        self.assertIn(2, self.numbers(page("", "<base href='./sub/'>")))
        self.assertEqual(self.problems(page("", "<base target='_blank'>")), [])

    def test_duplicate_attribute_first_wins(self):
        evil = "https://evil.example/x"
        for tag in (
            f'<script src="{evil}.js" src="./style.css" defer></script>',
            f'<img src="{evil}.png" src="./style.css">',
        ):
            with self.subTest(tag=tag):
                self.assertIn(5, self.numbers(page(tag)))
        local_first = f'<img src="./style.css" src="{evil}.png">'
        self.assertEqual(self.problems(page(local_first)), [])
        dup_a = f'<a href="./nope.html" href="{evil}">x</a>'
        self.assertEqual(self.numbers(page(dup_a)), [2])

    def test_harmless_inline_style_passes(self):
        html = page("<p style='color:red'>a</p>", "<style>a{color:red}</style>")
        self.assertEqual(self.problems(html), [])

    def test_protocol_relative_is_not_check_1(self):
        numbers = self.numbers(page('<script src="//cdn.x/y.js"></script>'))
        self.assertIn(5, numbers)
        self.assertNotIn(1, numbers)

    # -- check 2 -----------------------------------------------------------

    def test_bare_hash_and_empty_href_ignored(self):
        self.assertEqual(self.problems(page('<a href="#">a</a><a href="">b</a>')), [])

    def test_missing_local_file_flagged(self):
        self.assertIn(2, self.numbers(page('<img src="./assets/nope.webp">')))

    def test_anchor_without_matching_id_flagged(self):
        self.assertIn(
            2, self.numbers(page('<a href="#nowhere">a</a><p id="other"></p>'))
        )

    def test_hash_anchor_with_matching_id_not_resolved_as_file(self):
        self.assertEqual(
            self.problems(page('<a href="#top">a</a><p id="top"></p>')), []
        )

    def test_query_and_fragment_stripped_before_resolving(self):
        html = page(
            '<img src="./assets/a.webp#x">',
            '<link rel=stylesheet href="./style.css?v=2">',
        )
        self.assertEqual(self.problems(html, files={"assets/a.webp": b"x"}), [])

    def test_srcset_descriptors_dropped_and_each_candidate_resolved(self):
        html = page('<img srcset="./a.webp 1x, ./b.webp 640w">')
        found = self.problems(html, files={"a.webp": b"x"})
        self.assertEqual([n for n, _ in found], [2])
        self.assertIn("b.webp", found[0][1])
        self.assertNotIn("a.webp", found[0][1])

    def test_mailto_tel_data_not_local(self):
        html = page(
            '<a href="mailto:x@y">m</a><a href="tel:1">t</a>'
            '<img src="data:image/png;base64,AA==">'
        )
        numbers = self.numbers(html)
        self.assertNotIn(2, numbers)
        self.assertNotIn(5, numbers)

    def test_css_import_local_resolved(self):
        self.assertIn(2, self.numbers(page(""), css='@import "./nope.css";'))

    # -- check 3 -----------------------------------------------------------

    def test_dotdot_escape_flagged(self):
        self.assertIn(3, self.numbers(page('<a href="../README.md">r</a>')))

    def test_escape_after_normalisation_flagged(self):
        self.assertIn(3, self.numbers(page('<a href="./assets/../../README.md">r</a>')))

    def test_github_url_allowlist_accepts(self):
        for url in (
            "https://github.com/ckir/clavity",
            "https://github.com/ckir/clavity/blob/main/LICENSE",
            "https://github.com/ckir/clavity/blob/main/clavity-dotnet/README.md",
            "https://github.com/ckir/clavity/",
            "https://github.com/ckir/clavity/tree/main/docs",
            "https://github.com/ckir/clavity/releases",
            "https://github.com/ckir/clavity/releases/latest",
            "https://github.com/ckir/clavity/issues",
        ):
            with self.subTest(url=url):
                self.assertEqual(self.problems(page(f'<a href="{url}">x</a>')), [])

    def test_github_lookalike_rejected(self):
        for url in (
            "https://github.com/ckir/clavity-evil/blob/main/x",
            "https://github.com/ckir/clavity.git",
            "https://github.com/ckir/clavity/blob/dev/x",
            "https://github.com/ckir/clavity/pulls",
            "https://github.com:443/ckir/clavity/pulls",
            "https://GitHub.com/ckir/clavity/pulls",
        ):
            with self.subTest(url=url):
                self.assertIn(3, self.numbers(page(f'<a href="{url}">x</a>')))

    def test_allowlisted_prefix_must_end_at_a_path_boundary(self):
        base = "https://github.com/ckir/clavity"
        for url in (
            f"{base}/issues-evil/1",
            f"{base}/releases_fake",
            f"{base}/blob/mainx/LICENSE",
            f"{base}/tree/main-x",
        ):
            with self.subTest(bad=url):
                problems = self.problems(page(f'<a href="{url}">x</a>'))
                self.assertEqual([n for n, _ in problems], [3])
                self.assertIn("github.com URL is not", problems[0][1])
        for url in (
            f"{base}/issues",
            f"{base}/issues/12",
            f"{base}/releases/latest",
            f"{base}/blob/main",
            f"{base}/blob/main/LICENSE",
        ):
            with self.subTest(good=url):
                self.assertEqual(self.problems(page(f'<a href="{url}">x</a>')), [])

    def test_percent_encoded_local_reference_resolves_to_the_decoded_file(self):
        html = page('<img src="./assets/test%20file.png">')
        self.assertEqual(self.problems(html, files={"assets/test file.png": b"x"}), [])

    def test_percent_encoded_dotdot_escape_is_still_an_escape(self):
        html = page('<img src="./assets/%2e%2e/%2e%2e/README.md">')
        # src climbing out of site/ is check 2 (an href would be check 3).
        self.assertIn(2, self.numbers(html), "decoded ../.. escape must be check 2")

    def test_non_utf8_readme_is_cannot_answer_exit_2(self):
        site = make_site(self.tmp / "bad_readme", page(index_body()))
        bad = self.tmp / "bad_readme" / "README.md"
        bad.write_bytes(b"# T\n\xff\xfe\x80 not utf-8\n")
        with self.assertRaises(CannotAnswer) as ctx:
            check_site(site, bad)
        self.assertIn(
            "README.md cannot be read (UnicodeDecodeError)", str(ctx.exception)
        )
        result = run_checker(site, bad)
        self.assertEqual(result.returncode, 2)
        self.assertIn("CANNOT_ANSWER", result.stderr)

    def test_nesting_limit_is_exact(self):
        ok = make_site(self.tmp / "deep_ok", "<div>" * 512)
        self.assertEqual(check_structure(ok), [])
        deep = make_site(self.tmp / "deep_bad", "<div>" * 513)
        with self.assertRaises(CannotAnswer) as ctx:
            check_site(deep, self.readme)
        self.assertIn("512", str(ctx.exception))
        result = run_checker(deep, self.readme)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, "")
        self.assertTrue(result.stderr.startswith("CANNOT_ANSWER: "), result.stderr)
        self.assertIn("512", result.stderr)

    def test_external_raw_githubusercontent_url_is_permitted(self):
        other = "https://raw.githubusercontent.com/external/repo/main/p.sh"
        self.assertEqual(self.problems(page(f'<a href="{other}">o</a>')), [])

    def test_raw_githubusercontent_urls_are_flagged(self):
        raw = "https://raw.githubusercontent.com/ckir/clavity/refs/heads/main/README.md"
        self.assertIn(3, self.numbers(page(f'<a href="{raw}">r</a>')))

    def test_malformed_absolute_url_never_raises(self):
        cases = (
            ('<a href="http://[::1">x</a>', 3),
            ('<a href="https://[">x</a>', 3),
            ('<a href="//[::1">x</a>', 3),
            ('<link rel="stylesheet" href="http://[::1">', 5),
        )
        for body, number in cases:
            with self.subTest(body=body):
                self.assertIn(number, self.numbers(page(body)))

    # -- check 4 -----------------------------------------------------------

    def test_raster_size_boundary(self):
        ok = {"assets/ok.webp": b"x" * (300 * 1024)}
        self.assertNotIn(4, self.numbers(page(""), files=ok))
        big = {"assets/big.webp": b"x" * (300 * 1024 + 1)}
        self.assertIn(4, self.numbers(page(""), files=big))
        svg = {"assets/logo.svg": b"x" * (2 * 1024 * 1024)}
        self.assertNotIn(4, self.numbers(page(""), files=svg))

    def test_uppercase_raster_suffix_still_measured(self):
        files = {"assets/banner.WEBP": b"x" * (300 * 1024 + 1)}
        self.assertIn(4, self.numbers(page(""), files=files))

    def test_unreferenced_oversized_raster_still_flagged(self):
        files = {"assets/unused.webp": b"x" * (300 * 1024 + 1)}
        self.assertIn(4, self.numbers(page("<p>no images</p>"), files=files))

    def test_missing_assets_dir_is_not_a_crash(self):
        self.assertNotIn(4, self.numbers(page("")))

    # -- check 5 -----------------------------------------------------------

    def test_third_party_loads_flagged(self):
        cases = {
            "script": '<script src="https://x/y.js"></script>',
            "stylesheet": '<link rel=stylesheet href="https://x/y.css">',
            "icon": '<link rel=icon href="//x/i.png">',
            "preload": '<link rel=preload href="https://x/f.woff2">',
            "srcset": '<img srcset="./a.webp 1x, https://x/b.webp 2x">',
        }
        for name, body in cases.items():
            with self.subTest(load=name):
                self.assertIn(5, self.numbers(page(body), files={"a.webp": b"x"}))
        self.assertIn(
            5, self.numbers(page(""), css="a { background: url(https://x/y.png); }")
        )

    def test_css_import_bare_string_third_party_flagged(self):
        self.assertIn(5, self.numbers(page(""), css='@import "https://cdn.x/y.css";'))

    def test_plain_anchor_to_other_site_ok(self):
        self.assertEqual(
            self.problems(page('<a href="https://example.com/">e</a>')), []
        )

    def test_og_meta_and_canonical_absolute_urls_ok(self):
        head = (
            '<meta property="og:image" content="https://ckir.github.io/clavity/assets/og.jpg">'
            '<link rel="canonical" href="https://ckir.github.io/clavity/">'
        )
        self.assertEqual(self.problems(page("", head)), [])

    # -- CLI ---------------------------------------------------------------

    def run_cli(self, site: Path):
        return run_checker(site, self.readme)

    def test_cli_exit_codes(self):
        clean = make_site(self.tmp / "clean", page(index_body()))
        result = self.run_cli(clean)
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "", ""))

        bad = make_site(self.tmp / "bad", page('<img src="/x.png">'))
        result = self.run_cli(bad)
        self.assertEqual(result.returncode, 1)
        self.assertIn("CHECK1:", result.stdout)

        empty = self.tmp / "empty" / "site"
        empty.mkdir(parents=True)
        result = self.run_cli(empty)
        self.assertEqual(result.returncode, 2)
        self.assertTrue(result.stderr.startswith("CANNOT_ANSWER: "), result.stderr)
        self.assertIn("site/index.html", result.stderr)


class ParityChecks(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.tmp = Path(self._tmp.name)
        self.count = 0

    def run_case(self, body=None, readme=None):
        """check_site over a fresh site (default clean index) and README."""
        self.count += 1
        base = self.tmp / f"case{self.count}"
        base.mkdir()
        readme_path = base / "README.md"
        readme_path.write_text(
            make_readme() if readme is None else readme, encoding="utf-8", newline=""
        )
        site = make_site(base, page(index_body() if body is None else body))
        return check_site(site, readme_path)

    def numbers(self, body=None, readme=None):
        return sorted({n for n, _ in self.run_case(body, readme)})

    def messages(self, body=None, readme=None):
        return [d.split(": ", 1)[1] for _, d in self.run_case(body, readme)]

    # -- check 6 -----------------------------------------------------------

    def test_install_parity_clean(self):
        self.assertEqual(self.run_case(), [])

    def test_problems_from_checks_1_6_and_7_are_reported_together(self):
        body = '<a href="/root-relative">x</a>' + index_body(
            install_html(CLEAN_COMMANDS + ["claude plugin install extra@clavity"]),
            w1="Changed waiver sentence.",
        )
        self.assertEqual(self.numbers(body), [1, 6, 7])

    def test_comment_stripped_from_readme_line_before_comparing(self):
        self.assertIn("# clavity-dotnet", make_readme())
        self.assertEqual(self.run_case(), [])

    def test_extra_readme_command_missing_from_page_flagged(self):
        readme = make_readme(README_COMMANDS + ["claude plugin install extra@clavity"])
        self.assertEqual(self.numbers(readme=readme), [6])
        self.assertIn(
            "README has 'claude plugin install extra@clavity' x1 more than the page",
            self.messages(readme=readme),
        )

    def test_extra_page_command_missing_from_readme_flagged(self):
        body = index_body(
            install_html(CLEAN_COMMANDS + ["claude plugin install extra@clavity"])
        )
        self.assertEqual(self.numbers(body), [6])
        self.assertIn(
            "page has 'claude plugin install extra@clavity' x1 more than the README",
            self.messages(body),
        )

    def test_empty_install_section_flagged(self):
        body = index_body('<section id="install"><ul></ul></section>')
        self.assertEqual(self.numbers(body), [6])

    def test_missing_install_section_flagged(self):
        self.assertEqual(self.numbers(index_body(install="")), [6])

    def test_duplicate_page_command_flagged(self):
        body = index_body(install_html(CLEAN_COMMANDS + [CLEAN_COMMANDS[1]]))
        self.assertEqual(self.numbers(body), [6])
        self.assertIn(
            f"page has {CLEAN_COMMANDS[1]!r} x1 more than the README",
            self.messages(body),
        )

    def test_duplicate_readme_command_flagged(self):
        readme = make_readme(README_COMMANDS + [CLEAN_COMMANDS[1]])
        self.assertEqual(self.numbers(readme=readme), [6])
        self.assertIn(
            f"README has {CLEAN_COMMANDS[1]!r} x1 more than the page",
            self.messages(readme=readme),
        )

    def test_button_and_code_in_different_li_flagged(self):
        c = CLEAN_COMMANDS
        items = "".join(
            f"<li><code data-cmd>{x}</code></li><li><button data-copy='{x}'>c</button></li>"
            for x in c
        )
        body = index_body(f'<section id="install"><ul>{items}</ul></section>')
        self.assertEqual(self.numbers(body), [6])

    def test_li_without_button_flagged(self):
        c = CLEAN_COMMANDS
        items = "".join(f"<li><code data-cmd>{x}</code></li>" for x in c)
        body = index_body(f'<section id="install"><ul>{items}</ul></section>')
        self.assertEqual(self.numbers(body), [6])

    def test_data_copy_must_equal_displayed_command(self):
        html = install_html().replace(
            'data-copy="claude plugin install clavity@clavity"',
            'data-copy="claude plugin install evil@clavity"',
        )
        self.assertNotEqual(html, install_html())
        self.assertEqual(self.numbers(index_body(html)), [6])

    def test_claude_plugin_text_without_data_cmd_flagged(self):
        extra = "<code>claude plugin install x@y</code>"
        html = install_html().replace("</ul>", f"</ul>{extra}")
        problems = self.run_case(index_body(html))
        self.assertEqual([n for n, _ in problems], [6])
        self.assertIn("page text mentions", problems[0][1])

    def test_claude_plugin_in_any_install_element_flagged(self):
        for extra in (
            "<pre>claude plugin install evil@x</pre>",
            "<p><kbd>claude plugin install evil@x</kbd></p>",
            "<p>Claude   Plugin install evil@x</p>",
            "<p>claude <b>plugin</b> install evil@x</p>",
        ):
            with self.subTest(extra=extra):
                html = install_html().replace("</section>", f"{extra}</section>")
                self.assertEqual(self.numbers(index_body(html)), [6])

    def test_claude_plugin_split_across_blocks_is_flagged(self):
        body = index_body() + "<p>claude</p><p>plugin install x</p>"
        problems = self.run_case(body)
        self.assertEqual([n for n, _ in problems], [6])
        self.assertIn("page text mentions", problems[0][1])

    def test_heading_then_paragraph_false_alarm_is_accepted_fail_closed(self):
        # Adjacent blocks are joined with a space, so this innocent pair reads
        # "Claude Plugin" and is flagged. Loud and rewordable: accepted trade-off.
        body = index_body() + "<h3>Claude</h3><p>Plugin names are listed below.</p>"
        problems = self.run_case(body)
        self.assertEqual([n for n, _ in problems], [6])
        self.assertIn("page text mentions", problems[0][1])

    def test_claude_plugin_text_anywhere_on_page_flagged(self):
        cases = {
            "before install": "<p><code>claude plugin install evil@clavity</code></p>"
            + index_body(),
            "footer": index_body() + "<footer><p>claude plugin install x</p></footer>",
            "title": None,
        }
        for name, body in cases.items():
            with self.subTest(name=name):
                if body is None:
                    html = page(index_body(), "<title>claude plugin</title>")
                    self.assertIn(6, self.numbers(html))
                else:
                    self.assertEqual(self.numbers(body), [6])

    def test_claude_plugin_in_html_comment_is_not_text(self):
        body = index_body() + "<!-- claude plugin install x -->"
        self.assertEqual(self.numbers(body), [])

    def test_claude_plugin_in_attribute_values_is_flagged(self):
        # ROADMAP section 96: a screen reader voices alt and aria-label, a
        # tooltip shows title, a form shows placeholder and value, and search
        # engines read <meta content>, so an install command there is a
        # rendered install line outside #install.
        carriers = {
            "img alt": '<img alt="run claude plugin install x">',
            "title": '<p title="claude plugin install x">hover</p>',
            "aria-label": '<nav aria-label="claude plugin install x"></nav>',
            "aria-description": '<p aria-description="claude plugin install x">y</p>',
            "input placeholder": '<input placeholder="claude plugin install x">',
            "input value": '<input value="claude plugin install x">',
        }
        for name, carrier in carriers.items():
            with self.subTest(name=name):
                problems = self.run_case(index_body() + carrier)
                self.assertEqual([n for n, _ in problems], [6])
                self.assertIn(name.split()[-1], problems[0][1])
                self.assertIn("mentions `claude plugin`", problems[0][1])
        with self.subTest(name="meta content"):
            html = page(
                index_body(),
                '<meta name="description" content="claude plugin install x">',
            )
            self.assertIn(6, self.numbers(html))

    def test_attribute_on_an_install_data_cmd_element_is_flagged(self):
        # Capstone round 1 (MG-1): the text of <code data-cmd> is sanctioned
        # because check 6 compares it with the README; an attribute on that
        # element, or on a child of it, is compared with nothing, so a command
        # there is an unchecked install line and is flagged like any other.
        evil = "claude plugin install evil@attacker"
        on_cmd = install_html().replace(
            "<code data-cmd>", f'<code data-cmd aria-label="{evil}">', 1
        )
        in_cmd = install_html().replace(
            "<code data-cmd>", f'<code data-cmd><span title="{evil}">', 1
        ).replace("</code>", "</span></code>", 1)
        for name, install in (("on data-cmd", on_cmd), ("inside data-cmd", in_cmd)):
            with self.subTest(name=name):
                self.assertIn(evil, install)
                self.assertEqual(self.numbers(index_body(install)), [6])

    def test_attribute_inside_a_readme_quote_is_flagged_and_quote_still_equal(self):
        quote = quote1_body(
            f"<p data-readme-quote='waiver-1'>{WAIVER_1[:10]}"
            f'<b title="claude plugin install x">{WAIVER_1[10:]}</b></p>'
        )
        self.assertEqual(self.numbers(quote), [6])

    def test_attribute_values_never_join_the_surrounding_text(self):
        # Capstone round 1 (PP-1): an attribute value is a string of its own.
        # Splicing it into the text stream hid the phrase on each side of it;
        # each is flagged exactly as it is without the attribute.
        cases = {
            "adjacent blocks": (
                '<h3>Claude</h3><p title="Section overview">Plugin names are listed.</p>'
            ),
            "inline element": '<p>claude <b title="emphasis">plugin</b> install evil@x</p>',
            "empty attribute": '<p>cla<b title="">ude</b> plugin install evil@x</p>',
        }
        for name, carrier in cases.items():
            with self.subTest(name=name):
                self.assertEqual(self.numbers(index_body() + carrier), [6])

    def test_attribute_values_do_not_join_text_or_each_other(self):
        # Nothing shows two attributes, or an element's text and its own
        # description, as one sentence: half a phrase on each side is clean.
        cases = {
            "two attributes": '<p title="run claude" aria-label="plugin install x">y</p>',
            "text then description": (
                '<p aria-description="plugin install evil@x">claude</p>'
            ),
        }
        for name, carrier in cases.items():
            with self.subTest(name=name):
                self.assertEqual(self.numbers(index_body() + carrier), [])

    def test_each_offending_attribute_value_is_its_own_problem(self):
        carrier = (
            '<p title="claude plugin install x" aria-label="claude plugin install y">'
            "z</p>"
        )
        problems = self.run_case(index_body() + carrier)
        self.assertEqual([n for n, _ in problems], [6, 6])
        self.assertIn("title", problems[0][1])
        self.assertIn("aria-label", problems[1][1])

    def test_claude_plugin_in_unlisted_attributes_is_not_page_text(self):
        # Only the attributes a visitor can see or hear are page text; data-*
        # payloads, and content off a <meta> or value off an <input>, are not
        # rendered anywhere.
        cases = {
            "data attribute": '<p data-note="claude plugin install x">y</p>',
            "content off meta": '<p content="claude plugin install x">y</p>',
            "value off input": '<p value="claude plugin install x">y</p>',
        }
        for name, carrier in cases.items():
            with self.subTest(name=name):
                self.assertEqual(self.numbers(index_body() + carrier), [])

    def test_readme_backticks_match_plain_page_text(self):
        readme = make_readme(
            waivers=(
                WAIVER_1.replace('"Waive agy for this step"', "`Waive agy for this step`"),
                WAIVER_2,
            )
        )
        self.assertNotEqual(readme, make_readme())
        code = WAIVER_1.replace(
            '"Waive agy for this step"', "<code>Waive agy for this step</code>"
        )
        self.assertEqual(self.run_case(index_body(w1=code), readme), [])

    def test_install_block_is_the_one_with_marketplace_add(self):
        readme = make_readme().replace(
            "### How to start\n",
            "### How to start\n\n```bash\nclaude plugin install other@elsewhere\nls\n```\n",
        )
        self.assertEqual(readme_install_commands(readme), CLEAN_COMMANDS)
        self.assertEqual(self.numbers(readme=readme), [])

    # -- check 7 -----------------------------------------------------------

    def test_exactly_two_quote_elements_required(self):
        two = index_body(w2="")
        two = two.replace("<p data-readme-quote='waiver-2'></p>", "")
        self.assertEqual(self.numbers(two), [7])
        four = index_body() + "<p data-readme-quote='waiver-2'>" + WAIVER_2 + "</p>"
        self.assertEqual(self.numbers(four), [7])
        dup = index_body().replace(
            "data-readme-quote='waiver-2'", "data-readme-quote='waiver-1'"
        )
        dup = dup.replace(WAIVER_2, WAIVER_1)
        self.assertEqual(self.numbers(dup), [7])

    def test_stray_warning_quote_key_flagged(self):
        stray = index_body() + "<div data-readme-quote='warning'><p>x</p></div>"
        self.assertEqual(self.numbers(stray), [7])

    def test_quote_matches_after_folding(self):
        w1 = "All the above can be waived by prompts. Say “Waive agy” it’s **fine** now."
        readme = make_readme(waivers=(w1, WAIVER_2), eol="\r\n")
        page_w1 = (
            "All the above can be waived by prompts. Say &quot;Waive agy&quot; it's <b>fine</b> now."
        )
        self.assertEqual(self.run_case(index_body(w1=page_w1), readme), [])

    def test_one_word_edit_flagged(self):
        body = index_body(w1=WAIVER_1.replace("solo", "alone"))
        self.assertEqual(self.numbers(body), [7])

    def test_block_boundaries_separate_words(self):
        readme = make_readme(
            waivers=(
                "All the above can be waived by prompts. Say it **[simply](https://github.com/ckir/clavity)** now.",
                WAIVER_2,
            )
        )
        tight = (
            "<div data-readme-quote='waiver-1'><p>All the above can be waived by prompts.</p>"
            f"<p>Say it <a href='https://github.com/ckir/clavity'>sim</a><b>ply</b> now.</p></div>"
        )
        self.assertEqual(self.run_case(quote1_body(tight), readme), [])

    def test_text_after_child_element_is_kept(self):
        readme = make_readme(
            waivers=("All the above can be waived by prompts. See [repo](https://github.com/ckir/clavity) for the rest of it.", WAIVER_2)
        )
        full = (
            "<p data-readme-quote='waiver-1'>All the above can be waived by prompts. See "
            f"<a href='https://github.com/ckir/clavity'>repo</a> for the rest of it.</p>"
        )
        self.assertEqual(self.run_case(quote1_body(full), readme), [])
        cut = full.replace(" for the rest of it.", "")
        self.assertEqual(self.numbers(quote1_body(cut), readme), [7])

    def test_empty_or_truncated_quote_flagged(self):
        for text in ("", "All", WAIVER_1[: len(WAIVER_1) // 2]):
            with self.subTest(text=text):
                self.assertEqual(self.numbers(index_body(w1=text)), [7])

    def test_waiver_lines_in_one_paragraph_extracted_separately(self):
        units = readme_quote_units(make_readme())
        self.assertEqual(units["waiver-1"], fold(WAIVER_1))
        self.assertEqual(units["waiver-2"], fold(WAIVER_2))
        self.assertNotIn("In case you have problem", units["waiver-1"])
        adjacent = f"{WAIVER_1}\n{WAIVER_2}\n"
        self.assertIn(adjacent, make_readme())

    # -- README parsers ----------------------------------------------------

    def test_readme_parsers(self):
        text = make_readme()
        self.assertEqual(readme_install_commands(text), CLEAN_COMMANDS)
        self.assertEqual(sorted(readme_quote_units(text)), ["waiver-1", "waiver-2"])
        self.assertEqual(fold("a  &quot;b&quot;\n‘c’"), "a \"b\" 'c'")

    def test_missing_readme_block_exits_2_via_cli(self):
        base = self.tmp / "cli"
        base.mkdir()
        readme = base / "README.md"
        readme.write_text(make_readme(commands=None), encoding="utf-8")
        site = make_site(base, page(index_body()))
        result = run_checker(site, readme)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, "")
        self.assertTrue(result.stderr.startswith("CANNOT_ANSWER: "), result.stderr)


BLOCK_TAG_LITERAL = (
    "address article aside blockquote br dd details div dl dt fieldset figcaption "
    "figure footer form h1 h2 h3 h4 h5 h6 header hr li main nav ol p pre section "
    "table tbody td tfoot th thead tr ul"
).split()


class SweepPins(unittest.TestCase):
    """Behaviours a line-level mutation sweep showed to be unpinned."""

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.tmp = Path(self._tmp.name)
        self.count = 0

    def case(self, html, readme=None, files=None, css=""):
        """check_site over a raw page (no wrapper) and README."""
        self.count += 1
        base = self.tmp / f"case{self.count}"
        base.mkdir()
        path = base / "README.md"
        path.write_text(make_readme() if readme is None else readme, encoding="utf-8")
        return check_site(make_site(base, html, css, files), path)

    def parity(self, body, readme=None, files=None):
        return self.case(page(body), readme, files)

    def structure(self, html, css="", files=None):
        self.count += 1
        return check_structure(make_site(self.tmp / f"s{self.count}", html, css, files))

    def numbers(self, problems):
        return [n for n, _ in problems]

    def text_flagged(self, problems):
        return any(n == 6 and "page text mentions" in d for n, d in problems)

    # -- G1 void elements stay off the stack -------------------------------

    def test_unclosed_void_elements_do_not_disturb_quote_text(self):
        voids = '<img src="./assets/a.webp" alt=""><br><meta name="m" content="c">'
        body = voids + index_body()
        self.assertEqual(self.parity(body, files={"assets/a.webp": b"x"}), [])

    def test_void_element_in_install_li_keeps_the_commands(self):
        html = install_html().replace("</li>", "<br><img src='./a.png'></li>", 1)
        problems = self.parity(index_body(html), files={"a.png": b"x"})
        self.assertEqual(problems, [])

    def test_many_void_elements_do_not_count_as_nesting(self):
        self.assertEqual(self.structure("<br>" * 600), [])

    # -- G2 / G4 block boundaries ------------------------------------------

    def test_every_block_tag_separates_words(self):
        for tag in BLOCK_TAG_LITERAL:
            with self.subTest(tag=tag):
                if tag in ("br", "hr"):
                    extra = f"claude<{tag}>plugin install x"
                else:
                    extra = f"<{tag}>claude</{tag}>plugin install x"
                self.assertTrue(
                    self.text_flagged(self.parity(index_body() + extra)), tag
                )

    def test_inline_end_tag_adds_no_space(self):
        extra = "cla<b>ude</b> plugin install x"
        self.assertTrue(self.text_flagged(self.parity(index_body() + extra)))
        readme = make_readme(waivers=("All the above can be waived by prompts. Intro abc now.", WAIVER_2))
        quote = "<p data-readme-quote='waiver-1'>All the above can be waived by prompts. Intro a<b>b</b>c now.</p>"
        self.assertEqual(self.parity(quote1_body(quote), readme), [])

    # -- G3 stray end tags -------------------------------------------------

    def test_stray_end_tag_does_not_crash_and_still_flags(self):
        extra = "<div><p>claude plugin install x</p></span>more</div>"
        self.assertTrue(self.text_flagged(self.parity(index_body() + extra)))

    def test_stray_end_tag_does_not_close_open_element(self):
        w1 = f"{WAIVER_1[:10]}</span>{WAIVER_1[10:]}"
        self.assertEqual(self.parity(index_body(w1=w1)), [])

    def test_end_tag_of_void_element_is_ignored(self):
        w1 = f"{WAIVER_1[:10]}</br></img>{WAIVER_1[10:]}"
        self.assertEqual(self.parity(index_body(w1=w1)), [])

    # -- G5 trailing text --------------------------------------------------

    def test_trailing_text_without_closing_tag_is_scanned(self):
        # A trailing "&" keeps the text buffered until parser.close() flushes it.
        html = "<!doctype html><title>t</title><p>x</p>claude plugin install x&"
        self.assertTrue(self.text_flagged(self.case(html)))

    # -- G6 / G7 whitespace and case in URL values --------------------------

    def test_whitespace_around_url_values_is_ignored(self):
        cases = {
            "script": '<script src="  https://evil.example/x.js "></script>',
            "link": '<link rel="stylesheet" href="\nhttps://evil.example/x.css">',
        }
        for name, html in cases.items():
            with self.subTest(name=name):
                self.assertIn(5, self.numbers(self.structure(page(html))))
        anchor = page('<a href=" #install "></a><div id="install"></div>')
        self.assertEqual(self.structure(anchor), [])
        self.assertEqual(self.structure(page('<a href=" # ">top</a>')), [])

    def test_whitespace_around_relative_reference_still_resolves(self):
        files = {"assets/profile.png": b"x"}
        img = page('<img src=" ./assets/profile.png">')
        self.assertEqual(self.structure(img, files=files), [])
        link = page("", '<link rel="stylesheet" href="./style.css ">')
        self.assertEqual(self.structure(link), [])
        escape = page('<a href=" ../README.md ">r</a>')
        self.assertEqual(self.numbers(self.structure(escape)), [3])
        self.assertEqual(self.structure(page('<a href="   ">e</a>')), [])

    def test_whitespace_around_local_css_reference_is_ignored(self):
        files = {"assets/a.webp": b"x"}
        inline = page("<p style=\"background:url(' ./assets/a.webp ')\">a</p>")
        self.assertEqual(self.structure(inline, files=files), [])
        imp = page("<style>@import ' ./style.css ';</style>")
        self.assertEqual(self.structure(imp), [])

    def test_repo_path_on_another_host_is_not_a_github_problem(self):
        html = page('<a href="https://example.org/ckir/clavity/anything">x</a>')
        self.assertEqual(self.structure(html), [])

    def test_whitespace_inside_css_url_values_is_ignored(self):
        url = page("<p style=\"background:url(' https://evil.example/x.png ')\">a</p>")
        imp = page('<style>@import  " https://evil.example/y.css ";</style>')
        for name, html in (("url", url), ("import", imp)):
            with self.subTest(name=name):
                self.assertIn(5, self.numbers(self.structure(html)))
        sheet = self.structure(
            page(""), css="a{background:url( https://evil.example/z.png )}"
        )
        self.assertIn(5, self.numbers(sheet))

    def test_scheme_case_does_not_hide_third_party_loads(self):
        for html in (
            '<script src="HTTPS://evil.example/x.js"></script>',
            '<img src="Http://evil.example/a.png">',
        ):
            with self.subTest(html=html):
                self.assertIn(5, self.numbers(self.structure(page(html))))

    # -- G8 case in github hosts -------------------------------------------

    def test_repo_path_case_does_not_bypass_the_allowlist(self):
        html = page('<a href="https://github.com/CKIR/Clavity/pulls">x</a>')
        self.assertEqual(self.numbers(self.structure(html)), [3])
        raw = "https://raw.githubusercontent.com/CKIR/clavity/refs/heads/main/other.md"
        problems = self.structure(page(f'<a href="{raw}">x</a>'))
        self.assertEqual(self.numbers(problems), [3])
        self.assertIn(raw, problems[0][1])
        parity = self.parity(index_body() + f"<a href='{raw}'>x</a>")
        self.assertTrue(any(raw in d for _, d in parity))

    # -- G9 / G10 link rels and absolute metadata -----------------------------

    def test_rel_case_does_not_hide_third_party_loads(self):
        for html in (
            '<link rel="STYLESHEET" href="https://evil.example/x.css">',
            '<link rel="Icon" href="https://evil.example/i.png">',
        ):
            with self.subTest(html=html):
                self.assertIn(5, self.numbers(self.structure(page("", html))))

    def test_every_loading_carrier_rejects_third_party_urls(self):
        evil = "https://evil.example/x"
        cases = {
            "poster": (f'<video poster="{evil}.png"></video>', "poster"),
            "object data": (f'<object data="{evil}"></object>', "data"),
            "table background": (
                f'<table background="{evil}.png"></table>',
                "background",
            ),
            "svg image": (f'<svg><image href="{evil}.png"/></svg>', "href"),
            "svg use": (f'<svg><use href="{evil}.svg#x"/></svg>', "href"),
        }
        for rel in ("manifest", "modulepreload", "prefetch", "preconnect", "Manifest"):
            cases[f"link {rel}"] = (f'<link rel="{rel}" href="{evil}">', "href")
        cases["link apple-touch-icon"] = (
            f'<link rel="apple-touch-icon" href="{evil}.png">',
            "href",
        )
        for name, (fragment, attr) in cases.items():
            with self.subTest(name=name):
                problems = self.structure(page(fragment))
                hits = [d for n, d in problems if n == 5 and evil in d]
                self.assertTrue(hits, problems)
                self.assertIn(f"via {attr} ", hits[0])

    def test_more_network_carriers_reject_third_party_urls(self):
        evil = "https://evil.example/x"
        style = "style=\"background:image-set('%s.webp' 1x)\""
        cases = {
            "svg use xlink": (
                f'<svg><use xlink:href="{evil}.svg#s"/></svg>',
                "xlink:href",
            ),
            "svg image xlink": (
                f'<svg><image xlink:href="{evil}.png"/></svg>',
                "xlink:href",
            ),
            "feImage href": (
                f'<svg><filter><feImage href="{evil}.png"/></filter></svg>',
                "href",
            ),
            "imagesrcset": (
                f'<link rel="preload" as="image" href="./style.css" imagesrcset="{evil}.webp 1x">',
                "imagesrcset",
            ),
            "image-set string": (f"<p {style % evil}>a</p>", "image-set()"),
            "image-set second": (
                f"<p style=\"background:image-set('./style.css' 1x, '{evil}.webp' 2x)\">a</p>",
                "image-set()",
            ),
        }
        for name, (fragment, label) in cases.items():
            with self.subTest(name=name):
                problems = self.structure(page(fragment))
                hits = [d for n, d in problems if n == 5 and evil in d]
                self.assertTrue(hits, problems)
                self.assertIn(f"via {label} ", hits[0])
        sheet = self.structure(
            page(""), css=f"a {{ background: -WEBKIT-Image-Set('{evil}.webp' 1x); }}"
        )
        self.assertIn(5, self.numbers(sheet))

    def test_more_network_carriers_resolve_local_files(self):
        files = {"assets/p.png": b"x"}
        local = {
            "use": '<svg><use xlink:href="./assets/p.png"/></svg>',
            "image": '<svg><image xlink:href="./assets/p.png"/></svg>',
            "feimage": '<svg><filter><feImage href="./assets/p.png"/></filter></svg>',
            "imagesrcset": '<link rel="preload" as="image" href="./style.css" imagesrcset="./assets/p.png 1x">',
            "image-set": "<p style=\"background:image-set('./assets/p.png' 1x)\">a</p>",
            "anchor xlink": '<a xlink:href="https://example.org/">x</a>',
        }
        for name, html in local.items():
            with self.subTest(name=name):
                self.assertEqual(self.structure(page(html), files=files), [])
        missing = {
            "use": '<svg><use xlink:href="./assets/no.png"/></svg>',
            "feimage": '<svg><filter><feImage href="./assets/no.png"/></filter></svg>',
            "imagesrcset": '<link rel="preload" as="image" href="./style.css" imagesrcset="./assets/no.png 1x">',
            "image-set": "<p style=\"background:image-set('./assets/no.png' 1x)\">a</p>",
        }
        for name, html in missing.items():
            with self.subTest(name=name):
                self.assertEqual(self.numbers(self.structure(page(html))), [2])

    def test_image_set_followed_by_a_quoted_string_in_the_same_declaration_is_an_accepted_false_alarm(
        self,
    ):
        # Fail-closed trade-off: the scan runs to the end of the declaration, so a
        # later quoted string is read as an image-set URL. Reword to avoid it.
        html = page(
            "<div style=\"background:image-set(url(./assets/profile.png) 1x) , 'Segoe UI'\">a</div>"
        )
        problems = self.structure(html, files={"assets/profile.png": b"x"})
        self.assertEqual(self.numbers(problems), [2])
        self.assertIn("image-set()", problems[0][1])

    def test_quoted_string_in_an_earlier_declaration_does_not_trigger_the_image_set_scan(
        self,
    ):
        html = page(
            "<div style=\"font-family:'Segoe UI';background:image-set(url(./assets/profile.png) 1x)\">a</div>"
        )
        self.assertEqual(self.structure(html, files={"assets/profile.png": b"x"}), [])

    def test_image_set_bare_string_resolves_like_a_url(self):
        files = {"assets/profile.png": b"x"}
        ok = page(
            "<div style='background:image-set(\"./assets/profile.png\" 1x)'>a</div>"
        )
        self.assertEqual(self.structure(ok, files=files), [])
        bad = page(
            "<div style='background:image-set(\"./assets/nope.png\" 1x)'>a</div>"
        )
        self.assertEqual(self.numbers(self.structure(bad, files=files)), [2])

    def test_css_function_and_at_rule_names_are_case_insensitive(self):
        evil = "https://evil.example/p.png"
        inline = page(f'<p style="background:URL({evil})">a</p>')
        self.assertIn(5, self.numbers(self.structure(inline)))
        self.assertIn(
            5,
            self.numbers(self.structure(page(""), css=f"a{{background:URL({evil})}}")),
        )
        imp = self.structure(page(""), css='@IMPORT "https://evil.example/y.css";')
        self.assertIn(5, self.numbers(imp))

    def test_every_raster_suffix_is_size_checked(self):
        limit = 300 * 1024
        for ext in (".png", ".jpg", ".jpeg", ".webp", ".avif", ".gif"):
            with self.subTest(ext=ext):
                big = self.structure(
                    page(""), files={f"assets/big{ext}": b"x" * (limit + 1)}
                )
                self.assertEqual(self.numbers(big), [4])
                ok = self.structure(page(""), files={f"assets/ok{ext}": b"x" * limit})
                self.assertEqual(ok, [])

    def test_non_loading_references_stay_clean(self):
        head = '<link rel="canonical" href="https://ckir.github.io/clavity/">'
        self.assertEqual(self.structure(page("", head)), [])
        upper = head.replace('"canonical"', '"Canonical"')
        self.assertEqual(self.structure(page("", upper)), [])
        self.assertEqual(
            self.structure(page('<a href="https://example.org/">x</a>')), []
        )
        files = {"assets/profile.png": b"x"}
        poster = page('<video poster="./assets/profile.png"></video>')
        self.assertEqual(self.structure(poster, files=files), [])
        missing = page('<video poster="./assets/nope.png"></video>')
        self.assertEqual(self.numbers(self.structure(missing)), [2])
        local = '<link rel="icon" href="./style.css">'
        self.assertEqual(self.structure(page("", local)), [])
        self.assertIn(
            5,
            self.numbers(
                self.structure(page("", '<link rel="icon" href="https://e.example/i">'))
            ),
        )

    def test_absolute_site_metadata_is_not_a_problem(self):
        head = (
            '<meta property="og:image" '
            'content="https://ckir.github.io/clavity/assets/og.jpg">'
            '<link rel="canonical" href="https://ckir.github.io/clavity/">'
        )
        self.assertEqual(self.structure(page("", head)), [])

    # -- G11 relative resolution and base ----------------------------------

    def test_escape_yields_exactly_one_problem(self):
        self.assertEqual(
            self.numbers(self.structure(page('<a href="../README.md">r</a>'))), [3]
        )
        self.assertEqual(
            self.numbers(self.structure(page('<img src="../x.png">'))), [2]
        )

    def test_directory_reference_needs_an_index(self):
        html = page('<a href="./assets/">a</a>')
        files = {"assets/a.webp": b"x"}
        self.assertEqual(self.numbers(self.structure(html, files=files)), [2])
        html = page('<a href="./sub/">a</a>')
        files = {"sub/index.html": b"<html></html>"}
        self.assertEqual(self.structure(html, files=files), [])

    def test_base_href_yields_exactly_one_problem(self):
        absolute = page("", "<base href='https://attacker.example/'>")
        self.assertEqual(self.numbers(self.structure(absolute)), [5])
        self.assertEqual(
            self.numbers(self.structure(page("", "<base href='./'>"))), [2]
        )

    # -- G12 README whitespace ---------------------------------------------

    def test_indented_and_padded_install_fence_lines_parse(self):
        padded = [f"    {c}   " for c in README_COMMANDS]
        readme = make_readme(commands=padded)
        self.assertNotEqual(readme, make_readme())
        self.assertEqual(readme_install_commands(readme), CLEAN_COMMANDS)
        self.assertEqual(self.parity(index_body(), readme), [])

    # -- G13 / G16 URL parsing ------------------------------------

    def test_unparseable_url_is_exactly_one_problem(self):
        problems = self.parity(index_body() + '<a href="http://[::1">x</a>')
        self.assertEqual(self.numbers(problems), [3])
        self.assertIn("unparseable URL", problems[0][1])

    # -- README dialect limits (fail closed, accepted) ----------------------

    def test_readme_tilde_fence_cannot_answer(self):
        readme = make_readme().replace("```", "~~~")
        with self.assertRaises(CannotAnswer) as ctx:
            self.parity(index_body(), readme)
        self.assertIn("only ``` backtick fences are understood", str(ctx.exception))

    def test_readme_underscore_emphasis_is_not_understood(self):
        waiver = WAIVER_1.replace("Say for example", "Say __for example__")
        self.assertNotEqual(waiver, WAIVER_1)
        problems = self.parity(index_body(), make_readme(waivers=(waiver, WAIVER_2)))
        self.assertEqual(self.numbers(problems), [7])

    def test_readme_install_comment_may_change_freely(self):
        commands = [c + "   # any new words" for c in CLEAN_COMMANDS]
        self.assertEqual(self.parity(index_body(), make_readme(commands=commands)), [])

    def test_image_set_url_function_in_any_case_is_reported_once(self):
        evil = "https://evil.example/p.png"
        html = page(f"<p style=\"background:image-set(URL('{evil}') 1x)\">a</p>")
        problems = self.structure(html)
        self.assertEqual(self.numbers(problems), [5])

    def test_xlink_href_on_a_link_element_is_not_a_load(self):
        head = '<link rel="stylesheet" xlink:href="https://evil.example/x.css">'
        self.assertEqual(self.structure(page("", head)), [])

    # -- case sensitivity of the parity gates ------------------------------

    def test_waiver_quote_differing_in_internal_case_is_flagged(self):
        w1 = WAIVER_1.replace("Say for example", "say for example")
        self.assertNotEqual(w1, WAIVER_1)
        problems = self.parity(index_body(w1=w1))
        self.assertEqual(self.numbers(problems), [7])
        self.assertIn("quote 'waiver-1'", problems[0][1])

    def test_waiver_quote_differing_only_in_case_is_flagged(self):
        problems = self.parity(index_body(w1=WAIVER_1.replace("All the", "all the")))
        self.assertEqual(self.numbers(problems), [7])
        self.assertIn("quote 'waiver-1'", problems[0][1])

    def test_readme_unit_differing_only_in_case_is_flagged(self):
        readme = make_readme(waivers=(WAIVER_1.replace("Say for", "say for"), WAIVER_2))
        self.assertNotEqual(readme, make_readme())
        problems = self.parity(index_body(), readme)
        self.assertEqual(self.numbers(problems), [7])
        self.assertIn("quote 'waiver-1'", problems[0][1])

    def test_install_command_differing_only_in_case_is_flagged(self):
        upper = "CLAUDE plugin install clavity@clavity"
        html = install_html().replace(CLEAN_COMMANDS[1], upper)
        self.assertEqual(html.count(upper), 2)  # the <code> text and its data-copy
        problems = self.parity(index_body(html))
        self.assertEqual(self.numbers(problems), [6, 6])
        details = [d for _, d in problems]
        self.assertTrue(
            any(f"README has {CLEAN_COMMANDS[1]!r} x1" in d for d in details)
        )
        self.assertTrue(any(f"page has {upper!r} x1" in d for d in details))

    # -- G14 CLI arguments -------------------------------------------------

    def test_cli_requires_site_and_readme(self):
        self.count += 1
        base = self.tmp / f"cli{self.count}"
        base.mkdir()
        site = make_site(base, page(index_body()))
        readme = base / "README.md"
        readme.write_text(make_readme(), encoding="utf-8")
        for args in (["--readme", str(readme)], ["--site", str(site)]):
            with self.subTest(args=args):
                result = subprocess.run(
                    [sys.executable, str(SCRIPT), *args], capture_output=True, text=True
                )
                self.assertEqual(result.returncode, 2)
                self.assertIn("usage", result.stderr)
                self.assertNotIn("Traceback", result.stderr)


REAL_SITE = Path(__file__).resolve().parents[2] / "site"


class RealPageContract(unittest.TestCase):
    """Accessibility contract of the real page's copy buttons (not a checker rule)."""

    @classmethod
    def setUpClass(cls):
        text = (REAL_SITE / "index.html").read_text(encoding="utf-8")
        cls.parser = parse_page(text)
        cls.buttons = [
            a for t, a in cls.parser.elements if t == "button" and "data-copy" in a
        ]
        cls.css = (REAL_SITE / "style.css").read_text(encoding="utf-8")

    def test_five_copy_buttons_with_unique_labels_starting_with_copy(self):
        self.assertEqual(len(self.buttons), 5)
        labels = [b.get("aria-label", "") for b in self.buttons]
        for label in labels:
            self.assertTrue(label.startswith("Copy"), label)
            self.assertNotIn("claude plugin", label.lower())
        self.assertEqual(len(set(labels)), 5, labels)

    def test_live_region_is_visually_hidden_by_class(self):
        regions = [a for _, a in self.parser.elements if a.get("id") == "copy-status"]
        self.assertEqual(len(regions), 1)
        self.assertIn("sr-only", regions[0].get("class", "").split())

    def test_one_live_region_outside_any_list_item(self):
        regions = [
            a
            for t, a in self.parser.elements
            if a.get("role") == "status" and a.get("id") == "copy-status"
        ]
        self.assertEqual(len(regions), 1)
        status = [a for _, a in self.parser.elements if a.get("role") == "status"]
        self.assertEqual(len(status), 1)
        text = (REAL_SITE / "index.html").read_text(encoding="utf-8")
        text = re.sub(r"<!--.*?-->", "", text, flags=re.S)
        before = text[: text.index('id="copy-status"')]
        self.assertEqual(len(re.findall(r"<li[\s>]", before)), before.count("</li>"))

    def test_sr_only_rule_hides_visually_not_from_assistive_tech(self):
        match = re.search(r"\.sr-only\s*\{([^}]*)\}", self.css)
        self.assertIsNotNone(match, ".sr-only rule missing")
        body = match.group(1).replace(" ", "")
        self.assertNotIn("display:none", body)
        self.assertNotIn("visibility:hidden", body)


@unittest.skipUnless(yaml_available, "PyYAML not installed")
class WorkflowShape(unittest.TestCase):
    """Shape of .github/workflows/pages.yml, one test per spec constraint.

    This is a LOCAL, AUTHORING-TIME gate: it needs PyYAML, and the spec forbids
    installing anything in CI, so the CI `build` job SKIPS this class when
    PyYAML is absent. A skip there is not coverage; a wrong pages.yml shows
    itself on its first run. Run locally with:
    uv run --with pyyaml python -m unittest discover -s .github/site-checks
    """

    @classmethod
    def setUpClass(cls):
        cls.wf = yaml.safe_load(WORKFLOW.read_text(encoding="utf-8"))
        cls.jobs = cls.wf["jobs"]

    def triggers(self):
        # PyYAML (YAML 1.1) parses the bare key `on` as the boolean True.
        return self.wf.get("on", self.wf.get(True))

    def test_pull_request_and_push_share_the_four_paths(self):
        on = self.triggers()
        self.assertEqual(on["pull_request"]["paths"], PAGES_PATHS)
        self.assertEqual(on["push"]["paths"], PAGES_PATHS)

    def test_push_is_scoped_to_main(self):
        self.assertEqual(self.triggers()["push"]["branches"], ["main"])

    def test_workflow_dispatch_present(self):
        self.assertIn("workflow_dispatch", self.triggers())

    def test_build_has_no_if(self):
        self.assertNotIn("if", self.jobs["build"])

    def test_deploy_needs_build(self):
        self.assertEqual(self.jobs["deploy"]["needs"], "build")

    def test_deploy_skipped_on_pull_request(self):
        self.assertEqual(
            self.jobs["deploy"]["if"], "github.event_name != 'pull_request'"
        )

    def test_deploy_environment_is_github_pages(self):
        env = self.jobs["deploy"]["environment"]
        self.assertEqual(env["name"], "github-pages")
        self.assertEqual(env["url"], "${{ steps.deployment.outputs.page_url }}")

    def test_deploy_permissions_exact(self):
        self.assertEqual(
            self.jobs["deploy"]["permissions"],
            {"contents": "read", "pages": "write", "id-token": "write"},
        )

    def test_top_level_permissions_exact(self):
        self.assertEqual(self.wf["permissions"], {"contents": "read"})

    def test_concurrency_on_deploy_only(self):
        self.assertEqual(
            self.jobs["deploy"]["concurrency"],
            {"group": "pages", "cancel-in-progress": False},
        )
        self.assertNotIn("concurrency", self.jobs["build"])
        self.assertNotIn("concurrency", self.wf)

    def test_jobs_are_build_and_deploy(self):
        self.assertEqual(set(self.jobs), {"build", "deploy"})

    def uses_by_job(self):
        return {
            name: [step["uses"] for step in job["steps"] if "uses" in step]
            for name, job in self.jobs.items()
        }

    def test_every_uses_is_a_known_action_on_a_major_tag(self):
        # Major tag shape only: Dependabot major bumps are auto-merged here.
        every = []
        for name, refs in self.uses_by_job().items():
            for ref in refs:
                self.assertRegex(ref, ACTION_REF, f"job {name!r}: {ref!r}")
                every.append(ref.split("@")[0])
        self.assertEqual(set(every), ACTION_NAMES)

    def test_deploy_step_id_deployment_uses_deploy_pages(self):
        steps = [s for s in self.jobs["deploy"]["steps"] if s.get("id") == "deployment"]
        self.assertEqual(len(steps), 1, "job 'deploy': need one step id: deployment")
        self.assertRegex(
            steps[0].get("uses", ""),
            r"^actions/deploy-pages@v\d+$",
            "job 'deploy': step 'deployment' must use actions/deploy-pages",
        )


if __name__ == "__main__":
    unittest.main()
