"""Verify a peer reply's quoted_line fields against a NAMED SHA.

Prototype of the checker that must ship alongside the JSON contract - without a reader,
the ten-key array is "a field no rule reads", which the capstone skill already forbids.

Usage: python check_quoted_lines.py <reply.json> <sha>
Exit 0 = every quoted_line matches; 1 = at least one drifted or is unverifiable.
"""
import io, json, subprocess, sys

TEN_KEYS = ["seat", "id", "file", "line", "quoted_line", "disposition",
            "confidence", "trigger", "severity", "detail"]

reply_path, sha = sys.argv[1], sys.argv[2]
rows = json.load(io.open(reply_path, encoding="utf-8"))

bad = 0
print("checking %d rows against %s" % (len(rows), sha))
print()

for i, r in enumerate(rows):
    rid = r.get("id", "<no id>")

    missing = [k for k in TEN_KEYS if k not in r]
    if missing:
        print("  [SCHEMA] %-22s missing keys: %s" % (rid, ",".join(missing)))
        bad += 1
        continue

    f, ln, quoted = r["file"], r["line"], r["quoted_line"]
    if not f or not ln or not quoted:
        print("  [SKIP]   %-22s no file/line/quoted_line to check (empty is legal)" % rid)
        continue

    try:
        blob = subprocess.run(["git", "show", "%s:%s" % (sha, f)],
                              capture_output=True, text=True, check=True).stdout
    except subprocess.CalledProcessError:
        print("  [BAD]    %-22s %s does not exist at %s" % (rid, f, sha))
        bad += 1
        continue

    lines = blob.split("\n")
    n = int(ln)
    if n < 1 or n > len(lines):
        print("  [BAD]    %-22s line %d out of range (file has %d lines at %s)"
              % (rid, n, len(lines), sha))
        bad += 1
        continue

    actual = lines[n - 1]
    if actual.rstrip("\r") == quoted.rstrip("\r"):
        print("  [OK]     %-22s %s:%d" % (rid, f.split("/")[-1], n))
    else:
        bad += 1
        print("  [DRIFT]  %-22s %s:%d" % (rid, f.split("/")[-1], n))
        print("             claimed: %r" % quoted)
        print("             actual : %r" % actual)

print()
print("%d row(s) failed" % bad)
sys.exit(1 if bad else 0)
