# Backlog stub — dependency pins are never re-resolved, and nothing schedules a check

**Status:** 🔴 **OPEN.** Verified by measurement. **CROSS-PROJECT** — the owner has confirmed this is not
clavity-specific ("it happens to other projects as well").
**Raised:** 2026-08-19, during the actions dependency sweep. Promoted from `.clavity/local-anomalies.md`
at the 2026-08-25 triage, which merged five separate captures into this one item.

## The defect, in four parts that share one root

1. **Pins are never re-resolved.** A version is pinned once and nothing ever re-checks it against the
   registry. MEASURED here: **16 of 25 pins stale.**
2. **Adoption skips the changelog.** A dependency is adopted without reading the changelog of the version
   actually pinned, so code gets written against a *remembered* older API idiom and the pinned version's
   real capabilities go unused. Bumping the pin later does not fix code already written to the old shape.
3. **Version and REF FORM are independent axes.** Verifying a version against the registry does NOT verify
   the ref resolves. MEASURED: `astral-sh/setup-uv` v5 -> v10 was correct on the version axis (v10.0.1,
   published 2026-08-12) and WRONG on the ref axis — that publisher ships `refs/tags/v5` but no floating
   `v9`/`v10`, so `uses: astral-sh/setup-uv@v10` fails with "unable to resolve action". A major tag
   tracking its releases is a **per-publisher convention, not a GitHub Actions guarantee.**
   It survived ten local lefthook gates and was caught only by the first CI execution on the branch.
   ⚠ A tags-only sweep reports branch-style refs (`dtolnay/rust-toolchain@stable`) as broken — a control
   that fails for the wrong reason. Resolve `git/ref/tags/<r>` AND `git/ref/heads/<r>`.
4. **ROOT CAUSE, measured:** this repo has **no dependabot/renovate config and no scheduled workflow of
   any kind** — all 21 workflows are push/PR/dispatch/tag triggered. Nothing can notice drift, because
   nothing ever runs without a human pushing.

## Why it is one item

(1) and (2) are the same omission at different times; (3) is the check that catches what (1) misses; (4)
is why none of them ever fire. Fixing (4) alone does not cover (3), and fixing (3) alone leaves nothing
scheduled to run it.

## The fix direction (agreed with the peer, never built)

A scheduled workflow that re-resolves every pin on BOTH axes, plus an adoption rule that reading the
pinned version's changelog is part of adopting it. Dependabot covers (1) and (4); it does **not** cover
(3), so the ref-form resolve has to be explicit.

## Known limitation

Review is **structurally blind** to this class: nothing in a diff shows that a pin which was current when
written has since gone stale.
