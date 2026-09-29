# review-relay

Review a spec, plan, document or code change with web AI models (ChatGPT, Meta AI, Gemini, or any other)
in copy-paste rounds. Claude plays the main role: it prepares each round's prompt, checks every finding
against the real text, and folds the true ones. You carry the text to the sites and save the replies with
the bundled AiSaveDev browser extension (plain AiSave also works). Part of the clavity umbrella.

## How it works

1. `new-round.ps1` snapshots the artifact, appends a random end-of-document marker, and writes two ways to
   hand it over: a file to upload with a short prompt, and one all-in-one text (also put on the clipboard).
2. You paste or upload into the sites you choose and save each reply with AiSave.
3. `collect.ps1` finds the new AiSave captures, checks that each reviewer quoted the end marker (proof it
   read the whole artifact), and lays out each verdict and its findings side by side.
4. Claude verifies and folds, records a ledger, and starts the next round.

## What's in here

- `skills/review-relay/SKILL.md` - how Claude runs the rounds.
- `scripts/new-round.ps1`, `scripts/collect.ps1`, `scripts/lib/relay-lib.ps1` - the deterministic parts.
- `templates/spec-review.md`, `templates/code-review.md` - the round prompts.
- `extension/aisavedev/` - the AiSaveDev capture extension; `scripts/install-extension.ps1` installs it.

## Install

    claude plugin marketplace add ckir/clavity
    claude plugin install review-relay@clavity

Install at user scope to use it in every project. Each review keeps its files in the reviewed project,
under `.review-relay/<review-name>/`.

## Install the capture extension (AiSaveDev)

AiSaveDev saves each reply with per-turn markers that a reply's own text cannot fake, so `collect.ps1`
always finds the real reply. It is not in the Chrome Web Store; on Windows, "Load unpacked" is the only way
Chrome installs an extension from outside the store.

1. Ask Claude to "install the review-relay capture extension", or run
   `pwsh -File <plugin folder>/scripts/install-extension.ps1` yourself. It copies the extension to
   `%LOCALAPPDATA%\review-relay\aisavedev`, a folder that never moves, and prints the next step.
2. Once: open `chrome://extensions` (or `edge://extensions`), turn on Developer mode, click
   **Load unpacked**, and pick that folder.
3. After a review-relay update: repeat step 1, then click **Reload** on AiSaveDev.

`-Destination <folder>` installs somewhere else, and `-WhatIf` shows what it would do. It refuses to write
into any folder that holds anything but its own files.

## Configuration

- `REVIEW_RELAY_INBOX` - where `collect.ps1` looks for AiSave captures (default: your Downloads folder).
- `.review-relay/templates/spec-review.md` or `code-review.md` in a project overrides the bundled template.

## Troubleshooting

- **`collect.ps1` exits 2**: no AiSave capture was saved after the round started. Check where AiSave saves
  (`-Inbox <folder>`), and that you saved after running `new-round.ps1`.
- **A reviewer shows `NO-MARKER`**: its copy was probably cut off, or it skipped Step 0. Re-send the upload
  variant, or treat its findings with caution.
- **`collect.ps1` exits 1 naming a file it could not read**: the capture is still downloading or open in
  another program. Nothing was written; run `collect.ps1` again once the file is free.
- **A reply saved late, after the next round started**: it is still collected into its own round when its
  prompt carried the `review-relay tag:` line (run `collect.ps1 -Round <n>`). An untagged capture goes by
  file time instead.
- **Counts show `unknown`**: the reply did not use a recognised finding format; read it in `collected.md`.
- **A finished reply shows "This capture has no reply"**: the reply probably quotes a `## Human` heading
  (a transcript in a code block, say). A plain AiSave capture has no unambiguous turn delimiter, so that
  heading looks like a new turn. Save it again with AiSaveDev, an AiSave variant that writes per-turn
  markers (`format: aisave-dev/1`). `collect.ps1` reads those markers in place of the headings. See "Install the capture extension" above.
- **A count includes an example**: a finding written inside a closed code fence is not counted, but one in
  plain text or a quote is. Check it against `collected.md`.

## Docs

- `ROADMAP.md` - open decisions and the paused automated design.

## License

PolyForm Noncommercial 1.0.0 - see [LICENSE](LICENSE).
