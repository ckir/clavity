# review-relay changelog

## 0.2.0 - 2026-10-01

### Features
- feat(review-relay): install-extension.ps1 - mirror AiSaveDev into a fixed folder for Load unpacked
- feat(review-relay): bundle the AiSaveDev capture extension (runtime files)
- feat(review-relay): read AiSaveDev's per-turn markers (format aisave-dev/1)
- feat(review-relay): add member manifests, docs and roadmap (vendor APIs open decision)
- feat(review-relay): add the review-relay skill
- feat(review-relay): add collect (AiSave captures, read proof, verdicts, findings)
- feat(review-relay): add new-round (snapshot, end marker, both prompt variants)
- feat(review-relay): add spec and code review templates (end-marker read proof)
- feat(review-relay): add the relay library (read proof, templates, capture parsing)

### Fixes
- fix(repo): check every text file out as LF (ROADMAP section 58)
- fix(review-relay): ROADMAP D2 cited two files that are not in the repository
- fix(review-relay): emit the Playground's User turn as role=human
- fix(review-relay): keep every AiSaveDev marker role to [a-z]+
- fix(review-relay): revoke the capture blob after a delay, not at once
- fix(review-relay): final-review folds - name AiSaveDev in the descriptions, exact README guard wording, -WhatIf names the marker
- fix(review-relay): README install path had a CR and a BEL instead of backslashes
- fix(review-relay): capstone round 7 - drop the dead "later Human turn" cut
- fix(review-relay): test-audit - fence-aware finding count, actionable no-reply hint, garbled review.json writes nothing
- fix(review-relay): capstone round 6 - only a later Human turn ends an AiSave reply
- fix(review-relay): capstone round 5 - tag from the current exchange only, atomic review.json, bold severity tags
- fix(review-relay): capstone substitute round 4 - real reply boundary, review.json written last, -Round validated
- fix(review-relay): capstone substitute round 3 - one collect per round, fail closed on any unreadable capture, honest cleanup
- fix(review-relay): capstone substitute round 2 - no git option injection, atomic round reservation, honest no-reply captures
- fix(review-relay): capstone substitute round (ChatGPT via review-relay) - round tags, refuse unreadable captures, UNKNOWN column
- fix(review-relay): capstone R1 - a round's capture window ends at the next round, rounds number from the highest, honest inline read proof
- fix(review-relay): qualify runtime-file references in SKILL.md
- fix(review-relay): collect survives an unreadable capture, clear errors for garbled metadata, kind follows the source, LF json, no stale reply copies
- fix(review-relay): verdict from the last line only, null-safe counts, finding headings by level

<!-- `just release` prepends each new release section immediately after the H1 above.
     Do NOT remove the H1 and do NOT demote it to `##`: scripts/lib/release-lib.ps1
     injects using the regex `(?s)^(#[^\n]*\n+)(.*)$`, which also matches `##`, so a
     demoted title makes the injector write the new release INSIDE the previous
     release's body and silently reattribute its entries. -->
