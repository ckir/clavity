# Video Production Specifications

Creative briefs and technical recording guidelines for Clavity product demonstrations.

## 1. Video 1: "The 60-Second Terminal Split" (Short-Form Demo)

- **Target Platforms:** YouTube Shorts, X (Twitter), LinkedIn, Reddit.
- **Ratios:** 1080x1920 (9:16 Vertical) and 1920x1080 (16:9 Landscape).
- **Target Duration:** 45–60 seconds.
- **Status:** **Scripted Specification** (Awaiting screen recording).

### Script & Scene Breakdown
- **0:00–0:10 (The Problem):** Developer prompts Claude Code to implement a caching algorithm. Claude generates the implementation and a unit test that naively passes.
- **0:11–0:25 (The Peer Intervenes):** The terminal splits. The Antigravity peer triggers `agy-capstone`. The peer highlights that cache eviction under concurrent access causes race conditions, citing the exact file:line.
- **0:26–0:42 (The Adversarial Fold):** Claude Code acknowledges the peer citation, rewrites the locking primitive, and adds a multi-threaded stress test.
- **0:43–0:55 (Green Gate & Hardened Tests):** Antigravity confirms: `VERDICT: GREEN`. `agy-test-audit` confirms all mutation probes pass.
- **0:56–1:00 (Call to Action):** On-screen text: "Two agents, one folder. Install free: `claude plugin install clavity@clavity`".

## 2. Video 2: "Deep-Dive Architecture & Real-World Pairing" (Long-Form)

- **Target Platform:** YouTube, Developer Documentation.
- **Format:** 1920x1080 Landscape, 60fps, crisp 4K capture recommended.
- **Target Duration:** 8–12 minutes.
- **Status:** Planned.

### Outline
1. Architecture of `clavity-ls` and stdio MCP bridging.
2. Walking through the 6 lifecycle stages from brainstorm to test audit.
3. Managing quota waivers and fallback modes.
4. Auto-training Antigravity knowledge with `agy-autotrain`.
