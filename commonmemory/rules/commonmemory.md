# commonmemory — proactive recall

At the START of a task, and whenever picking up handed-off work, run
`memory_smart_search query="[common] <repo>"` (where `<repo>` is the current repository's name) and
read the other agent's notes BEFORE acting. Prefer the most recent note (check its timestamp), honor
its `Status:`, and do not act on a superseded handoff.
