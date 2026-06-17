---
name: ask-agy
description: Use to delegate a task or review to Antigravity (agy) from Claude; calls the ask_agy MCP tool.
---

# Ask agy

When the user says "ask agy to …" (review, second opinion, analysis, etc.), call the
`ask_agy` tool exposed by the `clavity` MCP server with a clear `task` string, then
report agy's returned result. agy runs headlessly in the current project folder
(read-only in Phase 1) and returns its findings.
