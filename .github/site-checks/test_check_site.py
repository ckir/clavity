"""Unit tests for check_site.py (structural checks 1-5, README parity checks 6-7)."""

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from check_site import (
    CannotAnswer,
    check_site,
    check_structure,
    fold,
    readme_install_commands,
    readme_pairing_url,
    readme_quote_units,
)

SCRIPT = Path(__file__).with_name("check_site.py")
PAIRING = (
    "https://raw.githubusercontent.com/ckir/clavity/refs/heads/main/"
    "clavity-dotnet/pairing/agy-pairing-INSTALL.md"
)


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
README_WARNING = (
    'In Latest versions of Antigravity the "--prompt-interactive" option is not '
    "working as expected. The workaround until I fix it is simple.\n"
    "Copy/paste the exact content of this file "
    f"**[pairing]({PAIRING})** to Antigravity's prompt before start your work."
)
WAIVER_1 = (
    "All the above can be waived by prompts. "
    'Say for example "Waive agy for this step" and claude will execute the step solo.'
)
WAIVER_2 = (
    "In case you have problem to start agy (e.g. quota exhausted, Google's servers "
    "are down) you can switch to subagents mode by prompt."
)
PAGE_WARNING = (
    "<div data-readme-quote='warning'><p>In Latest versions of Antigravity the "
    "&quot;--prompt-interactive&quot; option is not working as expected. "
    "The workaround until I fix it is simple.</p><p>Copy/paste the exact content of "
    f"this file <a href='{PAIRING}'>pairing</a> to Antigravity's prompt before "
    "start your work.</p></div>"
)


def make_readme(
    commands=README_COMMANDS,
    warning=README_WARNING,
    waivers=(WAIVER_1, WAIVER_2),
    eol="\n",
) -> str:
    """A README shaped like the real one (fenced install block, WARNING, waivers)."""
    lines = ["# Title", "", "## HUMAN ONLY", "", "### WARNING", *warning.split("\n")]
    lines += [
        "",
        "",
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
    warning: str = PAGE_WARNING,
    w1: str = WAIVER_1,
    w2: str = WAIVER_2,
) -> str:
    return (
        (install if install is not None else install_html())
        + warning
        + f"<p data-readme-quote='waiver-1'>{w1}</p>"
        + f"<p data-readme-quote='waiver-2'>{w2}</p>"
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

    def test_raw_url_only_the_pairing_install_file(self):
        self.assertEqual(self.problems(page(f'<a href="{PAIRING}">p</a>')), [])
        other = (
            "https://raw.githubusercontent.com/ckir/clavity/refs/heads/main/README.md"
        )
        self.assertIn(3, self.numbers(page(f'<a href="{other}">o</a>')))

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

    # -- check 6 -----------------------------------------------------------

    def test_install_parity_clean(self):
        self.assertEqual(self.run_case(), [])

    def test_comment_stripped_from_readme_line_before_comparing(self):
        self.assertIn("# clavity-dotnet", make_readme())
        self.assertEqual(self.run_case(), [])

    def test_extra_readme_command_missing_from_page_flagged(self):
        readme = make_readme(README_COMMANDS + ["claude plugin install extra@clavity"])
        self.assertEqual(self.numbers(readme=readme), [6])

    def test_extra_page_command_missing_from_readme_flagged(self):
        body = index_body(
            install_html(CLEAN_COMMANDS + ["claude plugin install extra@clavity"])
        )
        self.assertEqual(self.numbers(body), [6])

    def test_empty_install_section_flagged(self):
        body = index_body('<section id="install"><ul></ul></section>')
        self.assertEqual(self.numbers(body), [6])

    def test_missing_install_section_flagged(self):
        self.assertEqual(self.numbers(index_body(install="")), [6])

    def test_duplicate_page_command_flagged(self):
        body = index_body(install_html(CLEAN_COMMANDS + [CLEAN_COMMANDS[1]]))
        self.assertEqual(self.numbers(body), [6])

    def test_duplicate_readme_command_flagged(self):
        readme = make_readme(README_COMMANDS + [CLEAN_COMMANDS[1]])
        self.assertEqual(self.numbers(readme=readme), [6])

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

    def test_pairing_href_must_equal_readme_raw_url(self):
        other = PAIRING.replace("INSTALL", "OTHER")
        warning = PAGE_WARNING.replace(f"href='{PAIRING}'", f"href='{other}'")
        self.assertNotEqual(warning, PAGE_WARNING)
        self.assertIn(6, self.numbers(index_body(warning=warning)))

    def test_warning_quote_without_link_flagged(self):
        warning = PAGE_WARNING.replace(f"<a href='{PAIRING}'>pairing</a>", "pairing")
        problems = self.run_case(index_body(warning=warning))
        self.assertIn(6, [n for n, _ in problems])

    def test_claude_plugin_text_without_data_cmd_flagged(self):
        extra = "<code>claude plugin install x@y</code>"
        html = install_html().replace("</ul>", f"</ul>{extra}")
        self.assertEqual(self.numbers(index_body(html)), [6])

    # -- check 7 -----------------------------------------------------------

    def test_exactly_three_quote_elements_required(self):
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

    def test_quote_matches_after_folding(self):
        warning = f"Intro “quoted” it’s fine.\r\nCopy **[pairing]({PAIRING})** now."
        readme = make_readme(warning=warning, eol="\r\n")
        page_warning = (
            "<p data-readme-quote='warning'>Intro &quot;quoted&quot; it's fine. "
            f"Copy <b><a href='{PAIRING}'>pairing</a></b> now.</p>"
        )
        self.assertEqual(self.run_case(index_body(warning=page_warning), readme), [])

    def test_one_word_edit_flagged(self):
        body = index_body(w1=WAIVER_1.replace("solo", "alone"))
        self.assertEqual(self.numbers(body), [7])

    def test_block_boundaries_separate_words(self):
        readme = make_readme(
            warning=f"This is simple.\nCopy/paste **[pairing]({PAIRING})** now."
        )
        tight = (
            "<div data-readme-quote='warning'><p>This is simple.</p>"
            f"<p>Copy/paste <a href='{PAIRING}'>pair</a><b>ing</b> now.</p></div>"
        )
        self.assertEqual(self.run_case(index_body(warning=tight), readme), [])

    def test_text_after_child_element_is_kept(self):
        readme = make_readme(warning=f"See [pairing]({PAIRING}) for the rest of it.")
        full = (
            f"<p data-readme-quote='warning'>See <a href='{PAIRING}'>pairing</a>"
            " for the rest of it.</p>"
        )
        self.assertEqual(self.run_case(index_body(warning=full), readme), [])
        cut = full.replace(" for the rest of it.", "")
        self.assertEqual(self.numbers(index_body(warning=cut), readme), [7])

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

    def test_warning_heading_excluded(self):
        warning = PAGE_WARNING.replace(
            "<p>In Latest", "<h3>WARNING</h3><p>In Latest", 1
        )
        self.assertEqual(self.numbers(index_body(warning=warning)), [7])

    # -- README parsers ----------------------------------------------------

    def test_readme_parsers(self):
        text = make_readme()
        self.assertEqual(readme_install_commands(text), CLEAN_COMMANDS)
        self.assertEqual(readme_pairing_url(text), PAIRING)
        self.assertEqual(
            sorted(readme_quote_units(text)), ["waiver-1", "waiver-2", "warning"]
        )
        self.assertEqual(fold("a  &quot;b&quot;\n‘c’"), "a \"b\" 'c'")

    def test_readme_without_pairing_link_cannot_answer(self):
        with self.assertRaises(CannotAnswer):
            readme_pairing_url(make_readme(warning="No link here."))

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


if __name__ == "__main__":
    unittest.main()
