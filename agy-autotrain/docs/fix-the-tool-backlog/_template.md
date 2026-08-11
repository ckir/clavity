---
slug: <kebab-case-unique-slug>
variant: <clavity-dotnet | clavity-classic | both>
observed: <YYYY-MM-DD>
source-inbox-entry: "<verbatim first ~12 words of the agy-observations bullet>"
status: open        # open | fixed-in-repo | released | wont-fix
# On `fixed-in-repo` or `released`, ALSO add:  fixed-by: <sha, sha>   fixed-on: <YYYY-MM-DD>
# On `released`, ALSO add:  released-in: <release tag or sha range>
#
# `fixed-in-repo` vs `released` is the distinction this enum exists to force, and it is MEASURABLE, not a
# judgement call: an item is `released` when its fix commits are ANCESTORS OF THE LATEST RELEASE TAG, and
# `fixed-in-repo` when they are not. Check it, do not infer it from a commit date - a commit can predate
# the last release and still not be in it:
#     git merge-base --is-ancestor <fix-sha> "$(git tag --sort=-creatordate | head -1)"
# The old single `fixed` value conflated the two, and the conflation was REACHABLE: on 2026-08-11 the
# installed plugin tree was missing the UserPromptSubmit hook whose backlog item read `status: fixed`.
---

<!-- CLOSING AN ITEM. Until 2026-08-03 this template offered only `open`, so nothing ever prompted an
     author to come back and close one - measured that day, an item sat `open` for a whole day after its
     fix had shipped AND reached capstone GREEN. Update the item in the same commit range as the fix.

     Two SEPARATE gates, do not conflate them. Marking this item `fixed` records that the CODE is fixed.
     RETIRING the corresponding driver-cheatsheet rule is a later, deliberate decision requiring BOTH a
     committed green CI regression test on every variant the quirk reproduced on, AND wide end-user
     adoption (agy-curate skill, spec 5.C-B / 5.C-D). Closing this item does NOT authorise stripping the
     rule - an end user on an older build still needs it. -->

# <one-line title of the quirk>

## Steps to Reproduce
<the exact reproduction on the named variant's bridge - concrete, runnable>

## Code-level Mitigation
<the specific change to the bridge/tool execution path that removes the quirk. If you cannot state one,
this entry does NOT belong in the backlog - it is a driver-cheatsheet rule instead.>

## Notes
<per-variant determinism, retirement gating, links to the carried cheatsheet rule>
