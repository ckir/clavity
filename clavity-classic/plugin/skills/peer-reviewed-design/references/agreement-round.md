# The agreement round

Run this when the owner asks for a "common agreed recommendation", a joint review of their
decisions, or any text both reviewers should sign. The point is to replace "Claude's summary of
what agy said" with a text the peer has committed to line by line, and to force at least one
finding neither reviewer would volunteer.

## Brief

Write the draft to `.clavity/seams/<topic>-agreement-first.md` (the `first` word is what the
recovery hook recognises; the discipline is `agy-first`), prepared through the marker writer, with
a scratch area `.clavity/scratch/<topic>-agreement/` and a named reply file. The payload carries the
same review-only banner, scratch sanction and reply contract as the fork brief (see
`<BASE>/references/fork-brief.md`, "The payload"); only the seats, the instruction and the terminal line differ.

Write the draft as numbered points (P1 to Pn). Each point is one executable claim:
a licence structure, an enforcement mechanism, a pricing axis, a first adopter, a metric. Add the
fixed facts and the owner's ruling verbatim, and state that the ruling itself is not under review,
only its execution.

Then the instruction, verbatim in spirit:

> For EACH point return exactly one of AGREE, AMEND, or DISSENT. AMEND must carry the replacement
> wording in full. DISSENT must carry the reason and the clause, measurement or precedent it rests
> on, marked [CLAIM] with a date if it is not in the files here. A verdict that merely restates the
> point, or agrees without saying what you checked, does not count; for each AGREE name the one
> thing you checked.

Then three questions:

1. Name at least one point where BOTH reviewers are wrong or have not looked, and what would settle
   it. "None" is not acceptable: two reviewers who built the text together are the least likely to
   see its gap.
2. If you could change exactly one point to improve the owner's stated outcome (for example: a first
   paying customer within twelve months), which and to what?
3. Which of your verdicts rest on a [CLAIM] you cannot verify from the files here?

Seat two lenses only: the Signatory (will have its name on the text and signs nothing it has not
checked against a file or a stated measurement) and the Outsider (has read none of the prior rounds
and judges only the owner's outcome and whether the decisions cohere). Where they differ, the peer
gives the reconciled verdict. Terminal line: `VERDICT: AGREE n, AMEND m, DISSENT k`.

## Reading the reply

- An AGREE whose "thing I checked" cites a number or line that does not exist in the artifact is a
  fabricated receipt. The verdict may still stand; note the fabrication in the report and do not
  carry the number anywhere.
- An AMEND that names task numbers, sections or files must be checked against the real artifact
  before folding; the peer invents plausible references.
- A DISSENT is verified like any finding. When it is right (it often is), say so plainly to the
  owner: "agy dissented on my draft, and it was right".
- The "both wrong" answer is the most valuable line in the reply. Verify it; it is usually a real
  gap that both reviewers' shared framing hid.

## Presenting

Give the owner the agreed text as numbered points in final wording, with the dissent and the
both-wrong finding shown plainly and the claims neither reviewer could verify listed at the end.
Then the question: approve this text, or change which point? Fold amendments into the artifacts
only after the owner approves the agreed text.
