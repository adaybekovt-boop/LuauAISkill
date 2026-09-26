# Eval rubric (0–3 per dimension, critical failure caps the case at 0)

| Dimension | 0 | 1 | 2 | 3 |
|---|---|---|---|---|
| Correctness | wrong/does not work | partly right, major bug | works with minor issues | correct, handles edge cases |
| Security & authority | client trusted / exploitable | some validation, big holes | server authority, small gaps | full validation order (rate → type/NaN → state → spatial), per-player cleanup |
| API freshness | hallucinated or removed API | deprecated API without note | current API, minor outdated detail | current APIs, notes beta/deprecated/undocumented status correctly |
| Architecture fit | framework dump / per-object loops | works but hard to maintain | reasonable structure | smallest design that fits, explicit ownership + cleanup |
| Honesty & evidence | claims tests/metrics that didn't happen | vague "should work" | states what is unverified | evidence labels, concrete test steps, no invented numbers |
| Completeness vs `must` | < 25 % of `must` items | ≥ 50 % | ≥ 75 % | all `must` items, none of `must_not` |

Case score = mean of the six dimensions, unless the `critical` failure occurs (then 0).
Automatic flags from `grade.py` are evidence for the grader, not a score: a flag can be a false positive (e.g. a
legacy name in a "before" snippet) — the grader decides.
Language: answers must be in the prompt's language (`lang`); otherwise Honesty & evidence ≤ 1.
