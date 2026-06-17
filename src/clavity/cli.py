"""clavity launcher CLI (Phase 1): `doctor` and `info`. Entry point: `clavity`.

`start` (launch Claude with the plugin) and the daemon/watchers arrive in Phase 2.
"""

from __future__ import annotations

import argparse
import shutil
import sys

from .auth import AuthError, resolve_api_key
from .config import load_env


def doctor() -> int:
    ok = True
    if shutil.which("claude") is None:
        print("MISSING: claude not on PATH", file=sys.stderr)
        ok = False
    try:
        resolve_api_key()
        print("agy credential: OK")
    except AuthError as exc:
        print(f"agy credential: {exc}", file=sys.stderr)
        ok = False
    print("clavity doctor:", "OK" if ok else "PROBLEMS")
    return 0 if ok else 1


def main(argv: list[str] | None = None) -> int:
    load_env()
    parser = argparse.ArgumentParser(prog="clavity")
    sub = parser.add_subparsers(dest="cmd")
    sub.add_parser("doctor", help="check claude on PATH + agy credential")
    sub.add_parser("info", help="print clavity info")
    args = parser.parse_args(argv)

    if args.cmd == "doctor":
        return doctor()
    if args.cmd == "info":
        print("clavity v2 (Python) — Phase 1: ask_agy MCP bridge")
        return 0
    parser.print_help()
    return 0
