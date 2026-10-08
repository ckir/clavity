#!/usr/bin/env python3
"""One-time normalisation of the four trackers to docs/tracker-format.md (Branch T, Task 4).

Run:  python -I docs/superpowers/plans/2026-10-08-branch-t-normalise.py <repo-root> <table.tsv> <sha-overrides.tsv> [--dry-run]

The table (2026-10-08-branch-t-normalisation-table.tsv) is the DECISION: tracker, id, line (informational), token, note.
This script only APPLIES it. It never guesses a token and never invents a sha: anything it cannot resolve is reported and NOTHING is
written (all-or-nothing). Headings are located BY ID, never by the table's line column. History is kept verbatim: the old status
tail of a heading becomes a '> **Legacy status (verbatim, ...):**' line under the new status line.
Exit: 0 applied (or dry-run clean) | 3 unresolved items reported, nothing written | 2 bad input.
"""
import re, sys, os, io, glob, subprocess

NORMALISED = '2026-10-08'
TOKENS = ('OPEN', 'SCHEDULED', 'IMPLEMENTED', 'SHIPPED', 'CLOSED-BY-RULING', 'KILLED')
DATE = re.compile(r'\d{4}-\d{2}-\d{2}')
SHA = re.compile(r'`([0-9a-fA-F]{7,40})(?:\.\.([0-9a-fA-F]{7,40}))?`')
BARE_SHA = re.compile(r'\b[0-9a-f]{7,40}\b')
# A heading's status tail starts at the FIRST separator that is followed by a status glyph or a strike-through.
SEP = re.compile(r'\s+[—·]\s+(?=[~*]*(?:✅|▶|🔴|🚫|⚠|~~))')
LEGACY = '> **Legacy status (verbatim, before the 2026-10-08 normalisation):** '
STATUS_LINE = re.compile(r'^\*\*Status:\*\* (' + '|'.join(TOKENS) + r') \d{4}-\d{2}-\d{2} - \S')
FIXED_REOPEN = {
    'agent-shell-layer-corrupts-commands-and-probes.md': 'the shell tool layer is fixed upstream, or the Write-tool workaround stops working',
    'cross-project-anomalies-have-no-cross-project-home.md': 'a defect that spans two repositories costs a session to rediscover',
}
# Non-goals bullets the owner batch ruling requires (full text; id is the bullet key the gate matches).
BULLETS = {
    'item 7 (b)': "- **item 7 (b) - the five coverage gaps backfilled onto the conveyor** (closed by ruling 2026-10-08): `docs/coverage-debt.md` tracks the gaps instead. Reopen if that file stops being maintained.",
    'item 13c': "- **item 13c - does a growth-region write append or replace?** (closed by ruling 2026-10-08, answered by reading): `GoldenHeader.cs:286-287` writes a temp file then `File.Move(tmp, path, overwrite: true)` - a REPLACE; the classic writer was re-checked during normalisation. Reopen if either writer changes.",
    '§15': "- **§15 - the spec section 3b-vs-6 ordering tension** (closed by ruling 2026-10-08): the build follows 3b; the shipped behaviour is the ruling. Reopen if the two sections are ever made to disagree in code.",
    '§21': "- **§21 - whether the anti-wrap-up clause is sufficient** (closed by ruling 2026-10-08): the clause stays as necessary; isolating it is a quota-costing experiment. Reopen if a report is displaced despite the clause.",
    '§37': "- **§37 - release notes from commit subjects** (closed by ruling 2026-10-08): the convention stays. Reopen on a reader complaint.",
    '§58': "- **§58 - older clones keep CRLF until refreshed** (closed by ruling 2026-10-08): measured 2026-10-08, this clone shows only the two declared CRLF exceptions in `git ls-files --eol`; the refresh procedure stays documented. Reopen if a fresh clone shows CRLF blobs.",
}

problems = []
consumed = set()      # (tracker, id) of every table row some handler actually looked at
# Ids contain the section sign: never let the Windows console code page mangle them on the way out (they are copied into the overrides file).
for _s in (sys.stdout, sys.stderr): _s.reconfigure(encoding="utf-8")


def rd(p):
    with io.open(p, encoding='utf-8', newline='') as f:
        t = f.read()
    assert '\r' not in t, 'CR in ' + p
    return t


def git_has(root, sha):
    return subprocess.run(['git', '-C', root, 'cat-file', '-e', sha + '^{commit}'], capture_output=True).returncode == 0


def pick_sha(root, eid, overrides, *texts):
    cands = []
    if eid in overrides: cands.append(overrides[eid])
    for t in texts:
        for m in SHA.finditer(t):
            cands.append(m.group(2) or m.group(1))
    for c in cands:
        if git_has(root, c): return c
    return None


def clean(s):
    return re.sub(r'\s+', ' ', re.sub(r'\*\*|~~|`|[✅▶🔴🚫⚠]|\[[xX ]\]', '', s)).strip(' -*·—')


def first_date(*texts):
    for t in texts:
        m = DATE.search(t)
        if m: return m.group(0)
    return NORMALISED


def status_text(token, note, tail, kind, sha):
    if token == 'SHIPPED': return 'merged to main in `%s`' % sha
    if token == 'CLOSED-BY-RULING': return 'closed by ruling, see Non-goals / accepted limitations' if kind == 'roadmap' else 'closed by ruling, see Reopen if below'
    if token == 'KILLED':
        r = clean(tail)[:100]
        return 'will not be done - ' + (r if len(r) >= 12 else 'see the legacy status below')
    if token == 'SCHEDULED': return 'scheduled - ' + (note or 'see the legacy status below')
    if token == 'IMPLEMENTED': return 'built on an unmerged branch'
    return 'not yet scheduled'


def main():
    root, table, ovr = sys.argv[1], sys.argv[2], sys.argv[3]
    dry = '--dry-run' in sys.argv
    rows = [l.rstrip('\n').split('\t') for l in rd(table).split('\n')[1:] if l.strip()]
    rows = [r + [''] * (5 - len(r)) for r in rows]
    for r in rows:     # a table-supplied file name is a plain name, never a path (defence in depth: the table is committed, but it is also edited by hand)
        if r[0] in ('backlog-stub', 'fix-the-tool') and (os.path.basename(r[1]) != r[1] or not r[1].endswith('.md')):
            print('BAD-TABLE-NAME ' + r[1]); return 2
    overrides = {}
    for l in rd(ovr).split('\n'):
        if l.strip() and not l.startswith('#'):
            k, v = l.split('\t')[:2]; overrides[k] = v
    out = {}                                                   # path -> new text (written only if nothing is unresolved)

    # ---------- clavity-dotnet ROADMAP (+ agy-autotrain / review-relay: same heading engine) ----------
    def heading_engine(rel, tracker, head_re, id_of, kind):
        p = os.path.join(root, *rel.split('/'))
        if not os.path.exists(p): return
        lines = rd(p).split('\n')
        want = {r[1]: r for r in rows if r[0] == tracker and r[2] != 'NEW' and r[3] != 'NONE'}
        seen = set()
        i = 0
        new = []
        # entry boundaries for body scans
        heads = [k for k, l in enumerate(lines) if head_re.match(l)]
        ends = {h: (heads[n + 1] if n + 1 < len(heads) else len(lines)) for n, h in enumerate(heads)}
        k = 0
        while k < len(lines):
            l = lines[k]
            if not head_re.match(l):
                new.append(l); k += 1; continue
            eid = id_of(l)
            r = want.get(eid)
            if r is None:
                problems.append('NOT-IN-TABLE %s %s' % (rel, eid)); new.append(l); k += 1; continue
            seen.add(eid); consumed.add((tracker, eid))
            token, note = r[3], r[4]
            if token not in TOKENS:
                problems.append('NEEDS-RULING %s %s token=%s (%s)' % (rel, eid, token, note)); new.append(l); k += 1; continue
            # already normalised? (idempotence)
            j = k + 1
            while j < len(lines) and lines[j].strip() == '': j += 1
            if j < len(lines) and STATUS_LINE.match(lines[j]):
                new.append(l); k += 1; continue
            m = SEP.search(l)
            head, tail = (l[:m.start()], l[m.end():]) if m else (l, '')
            head = head.replace('~~', '').rstrip()
            body = lines[k + 1:ends[k]]
            legacy_status = ''
            # a following '**Status:**' line (review-relay / agy-autotrain) is the legacy status
            b = 0
            while b < len(body) and body[b].strip() == '': b += 1
            if b < len(body) and body[b].startswith('**Status:**'):
                legacy_status = body[b][len('**Status:** '):]
                body = body[:b] + body[b + 1:]
                tail = (tail + ' ' + legacy_status).strip()
            sha = None
            if token == 'SHIPPED':
                closure = [x for x in body[:400] if re.search(r'SHIPPED|FIXED|CLOSED|MERGED|BUILT|DONE', x)]
                sha = pick_sha(root, eid, overrides, tail, '\n'.join(closure))
                if not sha:
                    problems.append('NOSHA %s %s' % (rel, eid)); new.append(l); k += 1; continue
            date = first_date(tail, '\n'.join(body[:40]))
            sl = '**Status:** %s %s - %s' % (token, date, status_text(token, note, tail, kind, sha))
            new.append(head); new.append(''); new.append(sl)
            if tail: new.append(LEGACY + tail)
            rel_line = [x for x in [tail] if re.search(r'clavity-v\d+', x) and token == 'SHIPPED']
            if rel_line and re.search(r'releas', tail, re.I):
                v = re.search(r'clavity-v(\d+)', tail).group(0)
                new.append('**Released:** ' + v)
            new.extend(body if body and body[0].strip() == '' else [''] + body)
            k = ends[k]
        missing = [i for i in want if i not in seen]
        for i in missing: problems.append('TABLE-ROW-NOT-FOUND %s %s' % (rel, i))
        out[p] = '\n'.join(new)

    heading_engine('clavity-dotnet/ROADMAP.md', 'dotnet-roadmap', re.compile(r'^### (?:~~)?(?:§\d+ |\d+\. )'),
                   lambda l: (re.match(r'^### (?:~~)?(§\d+) ', l) or [None, None])[1] or 'item ' + re.match(r'^### (?:~~)?(\d+)\. ', l).group(1), 'roadmap')
    heading_engine('review-relay/ROADMAP.md', 'review-relay', re.compile(r'^### [DR]\d+ '), lambda l: re.match(r'^### ([DR]\d+) ', l).group(1), 'roadmap')
    heading_engine('agy-autotrain/ROADMAP.md', 'agy-autotrain-roadmap', re.compile(r'^## AT-\d+ '), lambda l: re.match(r'^## (AT-\d+) ', l).group(1), 'roadmap')

    # ---------- splits (rows with line == NEW) + Non-goals bullets, on the dotnet ROADMAP ----------
    rm = os.path.join(root, 'clavity-dotnet', 'ROADMAP.md')
    text = out.get(rm)
    if text is not None:
        orig = rd(rm)
        for r in rows:
            if r[0] == 'dotnet-roadmap' and r[2] == 'NEW':
                sid = r[1].split(' ')[0]
                consumed.add((r[0], r[1]))
                if re.search(r'^### ' + re.escape(sid) + ' ', text, re.M): continue
                if '29b' in r[1]:
                    m = re.search(r'^(> 🔴 \*\*§29b .*(?:\n>.*)*)', orig, re.M)
                    if not m: problems.append('SPLIT-SOURCE-NOT-FOUND §29b'); continue
                    title = '### §79 — The 13b completeness false-flag whose cause is not determined (formerly §29b)'
                    body = ['Split out of §29 on 2026-10-08 so an open sub-item does not hide inside a shipped section. The original paragraph, verbatim:', '', m.group(1)]
                else:
                    m = re.search(r'⚠ \*\*OPEN, deliberately not decided here: [^⚠]*', orig)
                    if not m: problems.append('SPLIT-SOURCE-NOT-FOUND §31 .no-agy'); continue
                    title = '### §80 — `.no-agy` should make `agy-liveness-check.sh` silent (formerly §31)'
                    body = ['Split out of §31 on 2026-10-08. The original sentence, verbatim from §31\'s header:', '', '> ' + m.group(0).strip()]
                block = [title, '', '**Status:** %s %s - %s' % (r[3], NORMALISED, status_text(r[3], r[4], '', 'roadmap', None)), ''] + body + ['', '']
                text = text.replace('\n## Non-goals / accepted limitations', '\n' + '\n'.join(block) + '## Non-goals / accepted limitations', 1)
        ng = text.index('## Non-goals / accepted limitations')
        for key, bullet in BULLETS.items():
            if re.search(r'^- \*\*' + re.escape(key) + r'(?![0-9A-Za-z])', text[ng:], re.M): continue
            anchor = text.find('\n_(The former', ng)
            if anchor < 0: anchor = len(text.rstrip('\n'))
            text = text[:anchor].rstrip('\n') + '\n' + bullet + '\n' + text[anchor:].lstrip('\n') if text[anchor:].strip() else text.rstrip('\n') + '\n' + bullet + '\n'
        out[rm] = text

    # ---------- backlog stubs ----------
    for r in rows:
        if r[0] != 'backlog-stub': continue
        consumed.add((r[0], r[1]))
        p = os.path.join(root, 'docs', 'backlog', r[1])
        lines = rd(p).split('\n')
        t = 0
        while t < len(lines) and lines[t].strip() == '': t += 1
        j = t + 1
        while j < len(lines) and lines[j].strip() == '': j += 1
        if STATUS_LINE.match(lines[j]): continue
        if not lines[j].startswith('**Status:**'):
            problems.append('STUB-SHAPE ' + r[1]); continue
        old = lines[j][len('**Status:** '):]
        token = r[3]
        if token not in TOKENS: problems.append('NEEDS-RULING %s token=%s (%s)' % (r[1], token, r[4])); continue
        sha = None
        if token == 'SHIPPED':
            sha = pick_sha(root, r[1], overrides, old, '\n'.join(lines[j + 1:j + 60]))
            if not sha: problems.append('NOSHA ' + r[1]); continue
        add = [STATUS_LINE_FMT(token, first_date(old), status_text(token, r[4], old, 'file', sha)), LEGACY + old]
        if j + 1 < len(lines) and lines[j + 1].strip(): add.append('')   # all 19 stubs have a non-blank line right after the status line; a blockquote line would swallow it (lazy continuation)
        if token == 'CLOSED-BY-RULING':
            if r[1] not in FIXED_REOPEN: problems.append('NEED-REOPEN ' + r[1]); continue
            add += ['', '**Reopen if:** ' + FIXED_REOPEN[r[1]]]
        out[p] = '\n'.join(lines[:j] + add + lines[j + 1:])

    # ---------- fix-the-tool frontmatter ----------
    for r in rows:
        if r[0] != 'fix-the-tool': continue
        consumed.add((r[0], r[1]))
        p = os.path.join(root, 'agy-autotrain', 'docs', 'fix-the-tool-backlog', r[1])
        lines = rd(p).split('\n')
        close = lines.index('---', 1)
        fm = lines[1:close]
        if any(re.match(r'status:\s*(' + '|'.join(TOKENS) + r')\b', x) for x in fm): continue
        token = r[3]
        if token not in TOKENS: problems.append('NEEDS-RULING %s token=%s' % (r[1], token)); continue
        keep = [x for x in fm if not re.match(r'(status|fixed-by|fixed-on|reason):', x)]
        fixed_by = next((x.split(':', 1)[1].strip() for x in fm if x.startswith('fixed-by:')), '')
        fixed_on = next((x.split(':', 1)[1].strip() for x in fm if x.startswith('fixed-on:')), NORMALISED)
        add = ['status: ' + token]
        if token == 'SHIPPED':
            sha = pick_sha(root, r[1], overrides, ' '.join('`%s`' % s for s in BARE_SHA.findall(fixed_by)))
            if not sha: problems.append('NOSHA ' + r[1]); continue
            add += ['fixed-by: ' + sha, 'fixed-on: ' + fixed_on]
        if token == 'KILLED':
            mk = re.search(r'\*\*KILLED\s*[-—]+\s*([^*]+?)\.?\*\*', '\n'.join(lines[close + 1:]))
            reason = clean(mk.group(1))[:120] if mk else clean(r[4])
            if len(reason) < 12 or reason.startswith('#'):
                problems.append('NEED-REASON ' + r[1]); continue
            add += ['reason: ' + reason]
        out[p] = '\n'.join(['---'] + keep + add + lines[close:])

    # A table row that NO handler consumed (its tracker file is missing, or the tracker is not handled at all) must never pass silently.
    for r in rows:
        if r[3] != 'NONE' and (r[0], r[1]) not in consumed: problems.append('TABLE-ROW-UNHANDLED %s %s' % (r[0], r[1]))
    if problems:
        for x in problems: print(x)
        print('UNRESOLVED: %d - nothing written' % len(problems)); return 3
    for p, t in out.items():
        assert '\r' not in t
        print(('would write ' if dry else 'wrote ') + os.path.relpath(p, root))
        if not dry:
            with io.open(p, 'w', encoding='utf-8', newline='') as f: f.write(t if t.endswith('\n') else t + '\n')
    return 0


def STATUS_LINE_FMT(token, date, text):
    return '**Status:** %s %s - %s' % (token, date, text)


if __name__ == '__main__':
    sys.exit(main())
