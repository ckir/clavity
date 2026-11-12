# Verification playbook

A claim is folded only after you have seen the thing it is about. These are the measurements that
settled claims in practice; reach for the same ones.

## Licence texts

- Fetch the exact text. Project sites break; the SPDX mirror does not:
  `https://raw.githubusercontent.com/spdx/license-list-data/main/text/<SPDX-ID>.txt`
  (for example `PolyForm-Noncommercial-1.0.0.txt`, `FSL-1.1-MIT.txt`, `Elastic-2.0.txt`).
- Save it under the session scratchpad and copy it into `.clavity/scratch/<topic>/` so the peer can
  read the same bytes; record its sha256 in the brief.
- Quote clause headings, not paraphrases. "Noncommercial Purposes", "Permitted Purpose",
  "Limitations", "Grant of Future License" are the sentences that decide who may do what.
- Remember what a licence cannot tell you: enforceability, adoption effects, and what a company's
  compliance scanner does with it are claims about the world, not the text. Mark them `[CLAIM]`.

## Libraries and services

- Version and currency: `npm view <pkg> version time.modified`; a package untouched for a year is a
  finding. Licence field: `npm view <pkg> license`, and when it says "SEE LICENSE", fetch the raw
  licence file from the repository.
- Existence of a named package or API: `npm view <pkg>` or a listing of actual members. Never accept
  a name because it reads plausibly; the peer fabricates the thing, not only the citation.
- Integration claims: read the provider's own docs page (a web-fetch subagent on the exact URL, with
  the question in the prompt so the answer comes back, not the page). Record which URL served.
- Runtime capability: a one-line `node -e` or equivalent proves a built-in exists (for example that
  `node:crypto` verifies Ed25519) without adding a dependency.

## Storage designs

- Build the proposed DDL verbatim in a throwaway database at the target scale with generated data,
  run the real read and write queries under `EXPLAIN (ANALYZE, BUFFERS, SUMMARY)`, probe the
  constraints (insert the row that must be rejected), and drop the database afterwards.
- Probe the edges the design's own rules imply: a JSON null in a merge, a second head where only one
  is allowed, a concurrent write. A hundred-out-of-a-hundred reproduction is what makes a rule a
  contract.
- Report timings as single samples on a shared machine unless you controlled the machine; quote the
  plan shape (index scan versus sequential scan) as the measured fact.

## Postgres is usually already there

Check `pg_lsclusters` and `pg_isready`; if the role you run as does not exist, `sudo -n -u postgres
psql` is often permitted. Create a scratch database, never touch an existing one, and drop it at
the end of the same script.

## Market, adoption and pricing

- Downloads, stars, waitlists and demo clicks measure reach or curiosity, not willingness to pay.
  Commitment with a cost attached (a pre-order with a price, a trial request from a company domain,
  a purchase) is the only signal worth a gate.
- Thresholds are the owner's and are written before the release ships. Label any number you or the
  peer propose `[PROPOSED, UNMEASURED]`.
- A self-hosted product that phones home nothing cannot measure usage; replace every usage metric
  with a purchase, a ticket, a registry count or a request, and say so in the artifact.

## Peer claims about its own actions

If the peer says it wrote, ran or benchmarked something, list the directory, read the file, or run
the command yourself. Its account of an action is a claim like any other.

## Recording

Every measurement that settles a claim goes in the artifact's review ledger with the command or the
quote, so the next reader does not have to redo it to trust it.
