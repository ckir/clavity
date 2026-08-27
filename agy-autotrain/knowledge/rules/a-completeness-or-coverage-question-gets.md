<!-- A rule in the agy-driving knowledge STORE (tier 2). Never injected; GROWTH selects from here.
     PURE ASCII BY POLICY, inherited from the GROWTH region this was split out of: that region is
     published through a byte transport which corrupted it once (2026-07-19 to 2026-08-01).
     The rule TEXT below is verbatim from the compiled GROWTH and must stay so - editing it is
     consolidation, which is allowed, but it is never a mechanical reformat. -->

# a completeness or coverage question gets

**Section:** CRITICAL ANTI-PATTERNS - newly learned, additive to SEED
**Origin:** split verbatim from the compiled runtime GROWTH region on 2026-08-27, when the store was
seeded. Before that this text existed ONLY at a runtime path outside version control.

- A COMPLETENESS OR COVERAGE QUESTION GETS ANSWERED AS A PRESENCE QUESTION, ACCURATELY, AND RETURNED AS
  EXHAUSTIVE - the ABSENT is what it cannot observe. Asked whether behaviours were tested it answers from
  tests that NAME them: it reported three "covered" while a mutant neutering all three call sites left the
  suite green, and it takes a HAPPY-PATH test as proof a guard is protected, which no success test can
  prove. So never ask "is anything missing" or "is this covered". Ask for the COVERED SET and compute the
  complement yourself, or the falsifiable form - "which test goes RED if I delete this call site, or
  NONE" - and settle it by neutering the site. It generates coverage HYPOTHESES well and judges coverage
  FACTS badly, because judging needs a suite it cannot run.
