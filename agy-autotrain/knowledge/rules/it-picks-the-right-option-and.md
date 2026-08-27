<!-- A rule in the agy-driving knowledge STORE (tier 2). Never injected; GROWTH selects from here.
     PURE ASCII BY POLICY, inherited from the GROWTH region this was split out of: that region is
     published through a byte transport which corrupted it once (2026-07-19 to 2026-08-01).
     The rule TEXT below is verbatim from the compiled GROWTH and must stay so - editing it is
     consolidation, which is allowed, but it is never a mechanical reformat. -->

# it picks the right option and

**Section:** CRITICAL ANTI-PATTERNS - newly learned, additive to SEED
**Origin:** split verbatim from the compiled runtime GROWTH region on 2026-08-27, when the store was
seeded. Before that this text existed ONLY at a runtime path outside version control.

- IT PICKS THE RIGHT OPTION AND ATTACHES A WEAKER VARIANT THAT WAS NEVER ON THE LIST, so evaluate the
  variant separately from the choice - the variant can reintroduce the exact failure the choice avoids.
  Measured: asked to resolve an ordering fork it chose correctly, then proposed moving only empty
  placeholders rather than the whole unit, reasoning that testing a placeholder adds no value. Sound in
  isolation, wrong in effect: the caller invokes through a null-tolerant operator, so the placeholders
  would compile and silently do nothing - protective machinery that protects nothing, every test green.
  ACCEPTING THE OPTION IS NOT ACCEPTING THE VARIANT.
