# Divergent design consult — clavity-dotnet "consumer-experience" trio

PERSONA: bold, inventive systems-designer. Generate RADICAL / orthogonal alternatives, first-principles
reframes, "10x-simpler or wholly-different" designs, invert the constraints. NOT incremental critique.

## Who consumes clavity
clavity-dotnet lets a **Claude** drive a live **Antigravity (agy)** peer over agy's local Language Server
(gRPC/h2c). Claude calls three MCP tools: `agy_look` (read the conversation trajectory, size-bounded),
`agy_status` (cascade id + step count), `agy_ask` (send a message, wait for the conversation to go idle,
return agy's reply). The consumer IS an LLM, not a human at a screen.

## The three wants (design ALL three; #1 is the hard one)
1. **Liveness during agy_ask.** Today agy_ask = send + ONE blocking `WaitForConversationFullyIdle` RPC +
   read reply. KEY CONSTRAINT: agy_ask is a SYNCHRONOUS MCP tool call — the calling Claude is BLOCKED and
   receives ONLY the final return value. So a stderr "heartbeat" helps a HUMAN at the terminal, NOT the
   Claude consumer. To give the LLM consumer mid-flight insight the CALL CONTRACT itself must change
   (bounded-wait + resume? async handle + poll? streaming? something else?). The LS offers
   `GetCascadeTrajectory` (pollable; steps append oldest-first) and
   `WaitForConversationFullyIdle{inactivity, stabilization} -> timed_out`. INVENT the best contract(s) so an
   LLM consumer is never "driving blind" — INCLUDING reframes where "blindness" is the wrong problem to solve.
2. **Clean typed reply from agy_ask.** Today it returns a flat list of {Kind:int, Text?:string} steps —
   tool/intermediate steps (Kind 90/8, null text) mixed with the answer (Kind 15). The consumer must
   pattern-match reverse-engineered Kind codes to find "the answer." INVENT the ideal typed result for an
   LLM consumer (answer vs reasoning vs tool-activity vs errors; how to bound size; how to signal
   truncation/continuation).
3. **agy_status busy/idle/stuck.** Today returns {CascadeId, TotalSteps, Truncated} — does NOT say whether
   agy is idle / working / modal-stuck RIGHT NOW (the one thing a caller checks before firing an ask).
   INVENT the cheapest reliable liveness/busy probe over the LS, and what status should report.

## What I want back
For EACH of the three: 2–4 genuinely DIFFERENT designs (not variations), each with the core idea, the
contract/shape, the LS mechanism it leans on, and its main risk. Flag any place where my framing is the
wrong frame. Terse. You MAY challenge the premise that all three are worth building.
