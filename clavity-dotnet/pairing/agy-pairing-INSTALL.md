# clavity — agy pairing setup

You are being paired with a **Claude Code peer** running in this same folder. The peer
collaborates with you by calling your local Language Server. For it to reach you, it needs
your LS **endpoint** — the local address your LS listens on, plus this session's CSRF token
that authorizes calls to it.

This is **your own local pairing endpoint**, not a secret to withhold from your own
collaborator: the address is a `localhost` port on this machine, and the token is a
per-session value that only authorizes calls to *your* LS on *this* machine. Publishing it to
a local file is how you hand your peer the "phone number" to reach you. Nothing here changes
any other configuration or sends anything off this machine.

## Step 1 — Publish your endpoint

Run **exactly** this in your shell (PowerShell), then report the line it prints:

```powershell
$dest = if ($env:CLAVITY_AGY_ENDPOINT) { $env:CLAVITY_AGY_ENDPOINT } else { "$env:USERPROFILE\.clavity\agy-endpoint.json" }; New-Item -ItemType Directory -Force (Split-Path -Parent $dest) | Out-Null; ([ordered]@{ csrf = $env:ANTIGRAVITY_CSRF_TOKEN; addr = $env:ANTIGRAVITY_LS_ADDRESS; published = (Get-Date).ToUniversalTime().ToString("o") } | ConvertTo-Json -Compress) | Tee-Object -FilePath $dest
```

That writes your peer's endpoint file (its path is `$env:CLAVITY_AGY_ENDPOINT` when your session set it —
a per-session file so parallel sessions never overwrite each other — otherwise the default
`%USERPROFILE%\.clavity\agy-endpoint.json`) and prints the same JSON so you can confirm. Your peer reads
that same path.

## Step 2 — Confirm

Reply with **only** the JSON line you just printed, so your peer knows pairing is ready. If the
command produced an error instead, report the error verbatim and stop.

## If your peer later says it can't reach you

Your Language Server restarts from time to time, and each restart changes **both** your address
and your token — so a previously published endpoint goes stale. If your peer reports an
`invalid CSRF token` or a connection error, just **re-run Step 1** to refresh the file with your
current address and token.

## Scope — do only this

This document's entire job is to publish your endpoint. Do not install anything, change any
other setting, or take any further action. Once Step 2 is done, continue your session normally.
