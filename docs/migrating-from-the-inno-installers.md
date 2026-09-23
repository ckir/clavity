# Migrating from the Inno Setup installers

On 2026-09-14, three members retired their Windows Inno Setup installers in favour of
`claude plugin` installation: **clavity-dotnet**, **agy-autotrain**, **commonmemory**.

**clavity-classic keeps its installer.** It is not affected by this migration.

This applies to you if you installed clavity-dotnet, agy-autotrain, or commonmemory from a
`<member>-setup-<version>.exe`.

## What the old installer did

All three installed the same way:

- Per-user install to `%LOCALAPPDATA%\Programs\<member>` (`PrivilegesRequired=lowest`). It
  shows under Windows Settings > Apps for your user account, not machine-wide.
- Registered the plugin against a local, scoped marketplace shipped inside the install
  directory.

clavity-dotnet additionally:

- Put `clavity-ls.exe` in `%LOCALAPPDATA%\Programs\clavity-dotnet\` and added that directory
  to your per-user PATH.
- On uninstall, removed the PATH entry, ran `clavity-ls uninstall --agent all` to deregister
  from detected agents, and asked whether to also delete the `.clavity` data folder in your
  profile (the golden-header seed and learned growth). Default answer is No (keep) — keep it
  unless you want a clean slate.

## Before you uninstall

1. Close Claude Code completely. The uninstaller refuses to run while it is open, and a
   running Claude Code restores the plugin registration on exit, then loads deleted files.
2. clavity-dotnet only: also close any live pairing session (`clavity-ls --mcp`). The
   uninstaller refuses while it holds the binary.

Run the old `<member>-setup-<version>.exe`'s uninstaller (or use Windows Settings > Apps)
before installing the plugin below.

## Install the plugin

Cross-platform — Windows, Linux, macOS:

```
claude plugin marketplace add ckir/clavity
claude plugin install clavity@clavity          # clavity-dotnet
claude plugin install agy-autotrain@clavity
claude plugin install commonmemory@clavity
```

## The binary change (clavity-dotnet)

This is the part that most affects a working setup.

- **Old:** `clavity-ls.exe` lived in `%LOCALAPPDATA%\Programs\clavity-dotnet\`, on your PATH.
  You ran `clavity-ls start C:\path\to\your\project` from a terminal.
- **New:** the plugin fetches the platform-matched binary on first session start into
  `${CLAUDE_PLUGIN_DATA}/bin/clavity-ls.exe`, and the plugin's MCP server launches it by that
  fixed path. It is **not** placed on your PATH.

Consequences:

- After migrating, typing `clavity-ls` in a terminal no longer resolves. Update any script,
  alias, or shortcut that invoked it directly.
- The fetch needs `curl` and `tar`. If either is missing, the fetch fails open with a note on
  stderr, and the MCP server will not start until you place the binary by hand.
- The download is keyed by a version stamp, so a plugin upgrade re-fetches. It is
  checksum-verified when a `.sha256` companion asset is published and `sha256sum` is on PATH;
  otherwise the fetch proceeds unverified.

## See also

- [`clavity-dotnet/plugin/README.md`](../clavity-dotnet/plugin/README.md) — current plugin
  install and configuration.
- [`README.md`](../README.md) — product overview and install matrix.
