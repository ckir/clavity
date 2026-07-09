# Antigravity bridge — first-run setup (delegate_to_antigravity)

This folder is the opt-in bridge. It is INACTIVE until you finish these steps **in a terminal opened HERE**
(in Explorer: type `cmd` in the address bar and press Enter, or Shift+Right-click -> "Open in Terminal").

1. Install uv if you don't have it: https://docs.astral.sh/uv/

2. Materialize the environment from the pinned lockfile (do NOT use a bare `uv sync` — it may re-resolve):

       uv sync --frozen

   *(If the installer already ran this for you during setup — it does when uv was already installed — you can
   skip this step.)*

3. Create your secret file (use `copy`, which works in both cmd and PowerShell; do NOT rename in Explorer — it
   blocks dot-leading names):

       copy .env.example .env

   then open `.env` and paste your `GEMINI_API_KEY` (the SDK does NOT reuse agy's OAuth login).

4. Register the bridge MCP with your agent, DIRECTORY-ANCHORED so it finds its env + `.env` regardless of the
   agent's working directory (paste into the agent's MCP config, adjusting the path). **Use FORWARD slashes** in
   the path — a Windows path with single `\` backslashes is INVALID JSON (e.g. `\U` is a bad escape) and will
   corrupt your agent config:

       "agy-bridge": { "command": "uv",
         "args": ["--directory", "C:/Users/<You>/AppData/Local/Programs/clavity-classic/agy-mcp-bridge",
                  "run", "C:/Users/<You>/AppData/Local/Programs/clavity-classic/agy-mcp-bridge/server.py"] }

   Replace the path with THIS directory's absolute path (shown in the Explorer address bar), converting `\` to `/`.

> Do NOT run `start-claudavity.ps1` by hand — the MCP server is launched in the background by the host agent;
> running it manually just hangs the terminal.
