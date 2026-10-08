"""Task 4 step 4b oracle: after the normalisation apply, EVERY line the diff REMOVED must be a tracker heading line,
a tracker status line, or a frontmatter status/fixed-by/fixed-on key. Anything else removed = body text lost.
Usage: python -I removed_oracle.py <repo-root>   (compares the working tree with HEAD)"""
import subprocess, sys, re
root = sys.argv[1]
d = subprocess.run(['git', '-C', root, 'diff', '-U0', '--no-color'], capture_output=True, text=True, encoding='utf-8').stdout
# ENTRY headings only (a body sub-heading such as '### The problem' must NOT be allowed to vanish): a section sign or numbered item,
# a review-relay D/R item, an agy-autotrain AT item; plus the status line and the frontmatter keys the script rewrites.
allowed = re.compile(r'^(### (~~)?(§\d+ |\d+\. |[DR]\d+ )|## AT-\d+ |\*\*Status:\*\*|status:|fixed-by:|fixed-on:|reason:)')
cur = None; bad = []; removed = 0
for l in d.split('\n'):
    if l.startswith('--- a/'): cur = l[6:]
    elif l.startswith('-') and not l.startswith('---'):
        if not l[1:].strip(): continue      # a removed BLANK line is whitespace, not lost text
        removed += 1
        if not allowed.match(l[1:]): bad.append('%s: %s' % (cur, l[1:][:110]))
print('removed lines: %d; not in the allow-list: %d' % (removed, len(bad)))
for b in bad[:25]: print('LOST', b)
sys.exit(1 if bad else 0)
