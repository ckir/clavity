# Archived Inno Setup installers (pre-retirement snapshot)

These are the **Inno Setup installer sources** for the three members whose Windows `.exe`
installers were **retired** in favour of `claude plugin` marketplace installation
(clavity-dotnet + a fetch-on-first-run binary hook; agy-autotrain and commonmemory as pure
plugins). Kept here so we can revert if the new install model proves inadequate.

**clavity-classic is NOT here** — it KEEPS its Inno installer, unchanged, at
`clavity-classic/installer/`.

## Source of truth for a full revert

- **Git tag:** `pre-inno-retirement-2026-09-14`
- **Commit:** `a45892f` (the last commit where all three members still shipped Inno installers)

The tag is the authoritative, complete snapshot — it captures the installers **and** their
surrounding context (CI workflows, release scripts, version gates, and the shared includes).
The copies in this directory are a convenience for reading/diffing the retired `.iss` sources
without git archaeology; they are NOT self-contained (the `.iss` files `#include` shared
helpers — see below).

## What is archived here

| Member | Files |
|--------|-------|
| clavity-dotnet | `clavity-dotnet/clavity-dotnet.iss`, `marketplace.install.json` |
| agy-autotrain  | `agy-autotrain/agy-autotrain.iss`, `marketplace.install.json` |
| commonmemory   | `commonmemory/commonmemory.iss`, `marketplace.install.json` |

## Shared includes stay LIVE (not copied here)

The retired `.iss` files reference `installer/_shared/*.iss` and `installer/_shared/register-plugin.ps1`.
Those shared helpers are **still in the tree** because clavity-classic's installer uses them, so
they are not archived here. If they drift after this snapshot, recover the exact
pre-retirement versions from the tag.

## How to revert a retired installer

```bash
# One member's installer back to its pre-retirement state:
git checkout pre-inno-retirement-2026-09-14 -- clavity-dotnet/installer

# Or the whole pre-retirement state of everything that changed in the migration:
git checkout pre-inno-retirement-2026-09-14 -- \
  clavity-dotnet/installer agy-autotrain/installer commonmemory/installer \
  installer/_shared \
  .github/workflows scripts build/members.json
```

After restoring the `.iss` sources, also restore the CI + version-gate + release-script changes
the migration made (the tag has them), then rebuild the installer via its `build-*.yml` workflow.
