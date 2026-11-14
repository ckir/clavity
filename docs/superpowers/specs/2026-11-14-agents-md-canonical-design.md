# AGENTS.md as the canonical agent-instruction file — design

Status: DRAFT for owner approval (2026-11-14). Size: small change.

## Intent

The repo root gained an `AGENTS.md` (uncommitted, this session). Its readers are **both** contributors'
non-Claude agents (Codex, Cursor, ...) **and** the agy review peer (owner, 2026-11-14). Today the shared repo
facts live partly in `CLAUDE.md` and partly in `AGENTS.md`, and Claude Code never loads `AGENTS.md` here.
Goal: one source for shared repo facts that every agent loads, without the agy peer ever being pointed at
anything the owner has placed in `.antigravityignore`.

## Measured facts this rests on

1. agy 1.5.9 loads a workspace `AGENTS.md` as always-on rules and re-reads it every turn. Measured: a marker
   line appended mid-conversation was quoted back with no tool steps.
2. `.antigravityignore` does NOT keep `AGENTS.md` out of agy's rules. Measured twice, including after a full
   agy restart with the ignore entry present before startup (marker `JADE-2264` quoted, no tool steps).
3. Claude Code 2.1.325 loads `AGENTS.md` only where a project has no `CLAUDE.md`; a file `CLAUDE.md` imports
   is not loaded twice (binary strings, doc-level). So today Claude sessions here do not see `AGENTS.md`.
4. `git check-ignore --no-index`, run in an empty temporary repo whose `.gitignore` is a copy of
   `.antigravityignore`, matches the owner's hidden paths (`clavity-dotnet/pairing/`, the pairing-bridge plan,
   `.clavity/`) and not ordinary paths. A directory named without its trailing `/` does not match unless
   tested with one (measured in a scratch probe).
5. agy does NOT load `CLAUDE.md`. Measured: with a marker line in `CLAUDE.md`, agy asked for any
   "probe token" line from any file in its context answered NONE; the same question format had quoted
   `AGENTS.md` markers back three times. So a "Claude sessions only" section in `CLAUDE.md` stays Claude-only.
6. git ignore-matching edges (git 2.53.0, measured in scratch repos): a fresh repo also applies the user's
   global ignore file (`~/.config/git/ignore` matched there); `check-ignore -v` prints a path matched only by a
   `!` re-include pattern and still exits 0; without `-z`, non-ASCII paths are octal-quoted; matching is
   case-sensitive on Linux unless `core.ignoreCase=true`; a file under an excluded directory cannot be
   re-included by `!` (git's documented rule).

## Goals

- G1. `AGENTS.md` is the single source of shared repo facts.
- G2. `CLAUDE.md` imports it (`@AGENTS.md`) and keeps only content meant for Claude sessions alone.
- G3. Instructions that tell an agent to *do* something sit under a heading scoped to sessions that make
  changes, so a review-only reader (the agy peer) is not steered into acting.
- G4. A gate fails when any agent rule file references a path that `.antigravityignore` matches.

## Non-goals

- Converting the per-product `clavity-dotnet/CLAUDE.md` / `clavity-classic/CLAUDE.md` to `AGENTS.md`
  (possible follow-up; not decided).
- Adding a `GEMINI.md`, or any attempt to hide `AGENTS.md` from agy (fact 2: no mechanism exists).
- Changing `check-injected-context` (its domain roots do not include the repo root, by design).

## Anti-goals (a failure even if everything passes)

- `AGENTS.md` names, links or quotes anything `.antigravityignore` matches.
- Claude-only driving discipline (how to consult or review with agy) lands in `AGENTS.md`, where it becomes
  agy's own always-on rules.
- Claude sessions load the shared content twice, or not at all.

## Approaches considered

- P. Two independent files — rejected: duplicated facts drift with nothing to catch it, and Claude sessions
  never see `AGENTS.md` (fact 3).
- **Q. `AGENTS.md` canonical, `CLAUDE.md` imports it — CHOSEN (owner: "Q, plus").**
- R. Committed `.claude/settings.json` option loading both files — rejected: same effect as Q, but depends on
  a recent Claude Code setting where Q uses a long-standing import.
- S. `CLAUDE.md` symlinked to `AGENTS.md` — rejected: breaks Windows checkouts without symlink support, and
  forces any Claude-only content onto every agent.
- "Plus" (agy's addition, owner-accepted): role-scoped headings (G3) and the leak gate (G4).
  agy-first consult: `.clavity/seams/agents-md-first.md`, verdict ALIGNED. Two of agy's supporting claims were
  refuted by measurement (the two build commands are identical under `just -n`; `CLAUDE.md:10-12` is not
  stale) and are not relied on.

## Design

### Root `AGENTS.md` (restructured, same facts)

Three top-level parts, in this order:
1. **About this repo** — facts only: products table (gains a column linking each product's notes), the
   `just` layout, generated/pinned files stated as facts, where agy-facing knowledge lives
   (`clavity-dotnet/plugin/knowledge/agy-assumptions.md`, `docs/agy-ls-assumptions.md`), the maintainer
   drain runbook pointer (moved from `CLAUDE.md`), further reading.
2. **Rules for every agent** — prohibitions only, safe for a review-only reader: never edit the README
   HUMAN ONLY block; never hand-edit generated files; releases and `clavity-v*` tags are owner-gated.
3. **When you are making changes** — opens with "Skip this section if your session is review-only."
   Holds every imperative: `lefthook install`, which commands and `check-*` recipes to run, the long suites
   to background, the regenerate-and-stage-together steps, licence header, Conventional Commits + DCO note,
   ASCII installer surface, new-root-file classification in `release-lib.ps1`, tracker format.

Every shared fact currently only in `CLAUDE.md` moves into part 1. No content that `.antigravityignore`
matches may appear (enforced by G4).

### Root `CLAUDE.md`

Becomes: a one-line purpose comment, `@AGENTS.md`, then a `## Claude sessions only` section. That section
starts empty apart from a sentence saying shared repo facts belong in `AGENTS.md`. Builder's call whether any
existing line is genuinely Claude-only; default is none.

### Leak gate: `scripts/check-agent-rules-ignore.ps1` + `just check-agent-rules-ignore`

- **Repo root:** the parent of the script's directory (as `scripts/check-doc-stubs.ps1` derives it); every
  git call runs with `-C <root>`, so the result does not depend on the caller's working directory.
- **Files scanned:** from `git -C <root> ls-files -z`, every tracked path whose basename is `AGENTS.md` or
  `GEMINI.md` at any depth, and every tracked `*.md` under a `rules/` directory whose parent is named
  `.agents`, `.agent`, `_agents` or `_agent` at any depth (agy accepts all four spellings:
  `~/.gemini/antigravity-cli/builtin/skills/agy-customizations/SKILL.md:41-42`; it loads rules walking up from
  the file it opens: lines 50-51). Zero files found is a pass (nothing can leak), and the census line always
  prints the file count. `CLAUDE.md` is not scanned: agy does not load it (fact 5).
- **Includes followed:** a file reached through agy's `@[label](path)` include syntax becomes part of the
  rules, so each include target is scanned too, recursively, with a visited set against cycles. agy's
  resolution base is undocumented, so a target is resolved relative to the including file first, then to the
  repo root; if neither exists the gate fails. The include target's own path is also checked as a reference.
- **References extracted, per line:** every whitespace-separated token inside an inline code span; every
  token on a line inside a fenced code block; every Markdown link target (this also covers the includes);
  and every prose token that contains a `/` or a `\`, or that starts with `.` followed by a letter (a dot-file
  or dot-folder named in prose, e.g. `.clavity`). Prose here includes HTML comments, reference-style link
  definitions and raw HTML, since agy reads the raw file. A link target is the CommonMark destination: the
  text inside `<...>` if present, otherwise up to the first whitespace, so a link title is excluded. Every
  token is also split on `=`, `[`, `]`, `(`, `)`, `{`, `}`, `<`, `>`, `"` and `'` (so `--out=path`,
  `href="path"` and a path glued to link syntax such as `Text](path` all yield `path`; measured: the glued
  form does not match until split).
- **Normalisation, in order, per reference** (a bypass found in review was measured for `#fragment` and `\`):
  (1) percent-decode (first, so an encoded `%23` fragment is stripped by step 3); (2) strip `*` and backticks
  from both ends, and sentence punctuation (`.,;:!`) from the END only, so a leading dot survives
  (`.clavity/` must stay `.clavity/`; stripping both ends would turn it into `clavity/`, which does not match); (3) drop a `#fragment` and a `?query`; (4) turn `\` into `/`; (5) skip
  `scheme://` URLs other than `file://`; rewrite a `file:` URI as a path: `file:///p` and
  `file://localhost/p` become `/p`, `file:///X:/p` and `file://X:/p` become `X:/p`, and a `file://` URI naming
  any other host is remote and skipped; (6) an absolute path inside
  the repo root is made repo-relative, comparing the prefix case-insensitively (a Windows drive letter may
  differ in case); (7) strip EVERY remaining leading `/` (GitHub resolves a root-relative link against the
  repo root, and a code comment `//` or `/*` must not reach git as a bare `/`, which makes git exit 128).
  Then build two forms independently: A = the path joined to the repo root, B = the path joined to the
  containing file's directory (a link in a nested file is relative to that file). Resolve `.` and `..` in
  each form separately; drop a form that escapes the repo root; drop a form whose result is empty or `.`;
  the root-level file has A = B, so test it once. Prose words with neither `/` nor `\` (and not a dot-file)
  are not checked, to avoid matching ordinary words against bare patterns such as `coverage/`.
- **Matching:** create an empty temporary repo with `git init --template=` (no `info/exclude`), copy
  `.antigravityignore` in as its `.gitignore`, and create an empty file to neutralise global excludes. Feed,
  in ONE git process for all references,
  every reference twice — once as written and once with a trailing `/` (fact 4) — NUL-terminated to
  `git -c core.excludesFile=<empty file> -c core.ignoreCase=true check-ignore --no-index --stdin -z -v`
  (fact 6: global excludes off, same result on every OS, unquoted paths). Parse the output as NUL-separated
  records of four fields (source, line number, pattern, path). A reference is a HIT only when its record's
  source is `.gitignore` and its pattern does NOT start with `!` (fact 6: `-v` also reports re-included
  paths). git exit 0 or 1 = ran; anything else = an error that FAILS the gate (measured: an unfiltered `/`
  reference makes git exit 128). Delete the temporary repo in a `finally`.
- **Known limit:** the gate catches path references, not prose that describes hidden content without naming
  a path. Content review remains the owner's and the reviewer's job.
- **Output and exit:** exit 0 with a one-line census (files scanned, references checked) when clean. Exit 1
  listing `file:line  reference  ->  .antigravityignore:<pattern line>` for every hit. Fail closed (exit 1
  with a reason) when `.antigravityignore` is missing, `git` is not on PATH, or git errors.
- **Baseline:** a scratch prototype of an earlier, narrower version of these rules found 181 references in
  the current draft `AGENTS.md` and no matches. The restructured `AGENTS.md` must pass the real gate
  (acceptance 1).
- **Semantics assumption:** git's ignore matching is taken as the definition of what `.antigravityignore`
  covers. agy's own matcher is closed-source; this gate enforces the owner's list as git reads it.
- **Wiring:** a `just` recipe; a lefthook `pre-push` job with a `glob` (YAML array form, both the root and
  `**/` variant of each, as `lefthook.yml`'s ruff job documents) on `AGENTS.md`, `GEMINI.md`, the four rule
  folders `.agents/`, `.agent/`, `_agents/`, `_agent/`, `.antigravityignore` and the script (seconds-range, as
  the hook header requires); a step in `.github/workflows/ci-scripts.yml` (no `paths:` filter, so it runs on every push).
  CI is the complete trigger. The pre-push glob is only a fast path: it cannot see an edit to an included file
  outside the globbed paths, and CI catches that case.
- **Tests:** a Pester suite in `scripts/tests/`, registered in `test-scripts-fast`, using the repo's
  `TestTemp.ps1` fixtures. Cases: clean file passes; leak via code span; leak via fenced block; leak via
  link target; leak via a bare prose path; directory reference without trailing `/`; leak inside an
  `@[label](path)` include target; missing include target fails; a missing ORDINARY link target does not
  fail; include cycle terminates; nested `GEMINI.md`; rules under each of `.agents/`, `.agent/`, `_agents/`,
  `_agent/`; a hidden path written with a `#fragment`, with `\` separators, with a leading `/`, as a
  `file://` URI (each of `file:///`, `file://localhost/`, `file:///X:/` forms), percent-encoded, with an encoded `%23` fragment, with a link title, glued to link syntax, or
  as `--opt=path` is flagged; a fenced block holding `// comment` and `/* comment */` passes without a git
  error; a Windows absolute path with a differently-cased drive letter is made repo-relative; a relative link in a nested rule file is
  resolved against that file's directory; an http URL, a path escaping the repo and an empty token are
  dropped without a git error; running the script from a subdirectory gives the same result; a prose word without `/` that equals a bare pattern (`coverage`) is not flagged; a file
  re-included by a file-level `!` pattern (e.g. `*.log` then `!keep.log`) is NOT flagged; a pattern in the
  test's own global-excludes fixture does not leak in; a non-ASCII hidden path is reported correctly; a
  differently-cased reference to a hidden path is flagged; missing `.antigravityignore` fails closed; a git
  error fails closed; no rule files passes with the census.
- Script follows existing conventions (licence header, `Set-StrictMode -Version Latest`, a row in
  `scripts/README.md`); the existing inventory, registration and strict-mode suites enforce these.

### Release classification

`AGENTS.md` is already added to `$DevOnlyPaths` in `scripts/lib/release-lib.ps1` (uncommitted, this session).
The new script and test live under `scripts/`, already dev-only.

## Acceptance

1. `just check-agent-rules-ignore` passes on the final tree; a temporary reference to
   `clavity-dotnet/pairing` in `AGENTS.md` makes it fail (then removed).
2. Claude Code loads the imported content: with a temporary marker line in `AGENTS.md`, a fresh
   `claude -p` in the repo quotes it without tools (then removed).
3. agy still loads `AGENTS.md` (same marker probe via `agy_ask`, then removed).
4. The repo's existing pre-push jobs, `just test-scripts-fast`, and the release-lib suite pass.

## Review record

Adversarial panel, 4 rounds (driver solo + agy escalation each round), GREEN at round 4. Briefs:
`.clavity/seams/agents-md-panel-r1.md` .. `-r4.md`. 30 findings raised: 26 folded, 4 rejected by measurement or
citation (CRLF in `.antigravityignore`, as `.gitattributes:9` forces LF; ordinary missing links failing the
gate, as only includes fail; the zero-files re-raise; naming `.clavity/scratch/` in AGENTS.md, which
`.antigravityignore:65` hides).

## Stand-downs

None: no finding was discarded below the severity floor or accepted unverified.

## Committing this doc

`docs/superpowers/specs/*` is gitignored with a per-file allowlist (`.gitignore:31-40`), so committing this
spec needs a `!docs/superpowers/specs/2026-11-14-agents-md-canonical-design.md` line added there.

## Left to the builder

Exact wording of the restructured `AGENTS.md`, the census line format, and whether any `CLAUDE.md` line is
Claude-only (default: none).
