"""Unit tests for check_site.py (structural checks 1-5)."""

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from check_site import check_site

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


class StructuralChecks(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.tmp = Path(self._tmp.name)
        self.count = 0
        self.readme = self.tmp / "README.md"
        self.readme.write_text("# fixture\n", encoding="utf-8")

    def problems(self, html, css="", files=None):
        self.count += 1
        site = make_site(self.tmp / f"case{self.count}", html, css, files)
        return check_site(site, self.readme)

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
        return subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "--site",
                str(site),
                "--readme",
                str(self.readme),
            ],
            capture_output=True,
            text=True,
        )

    def test_cli_exit_codes(self):
        clean = make_site(self.tmp / "clean", page("<p>hi</p>"))
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


if __name__ == "__main__":
    unittest.main()
