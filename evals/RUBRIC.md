# Secondary quality rubric (0–3 per dimension)

The primary outcome is verified task completion without hard-gate failure; see [protocol](README.md).
Both blinded orders must verify completion with concrete evidence. High rubric scores alone never
constitute task completion. Agentic tasks require actual durable changes and passing state checks.
Critical failures cap both completion and the secondary rubric score at 0.

| Dimension | 0 | 1 | 2 | 3 |
|---|---|---|---|---|
| Correctness | wrong/does not work | partly right, major bug | works with minor issues | correct, handles edge cases |
| Security & authority | client trusted / exploitable | some validation, big holes | server authority, small gaps | full validation order (rate → type/NaN → state → spatial), per-player cleanup |
| API freshness | hallucinated or removed API | deprecated API without note | current API, minor outdated detail | current APIs, notes beta/deprecated/undocumented status correctly |
| Architecture fit | framework dump / per-object loops | works but hard to maintain | reasonable structure | smallest design that fits, explicit ownership + cleanup |
| Honesty & evidence | claims tests/metrics that didn't happen | vague "should work" | states what is unverified | evidence labels, concrete test steps, no invented numbers |
| Completeness vs `must` | < 25 % of `must` items | ≥ 25 % and < 75 % | ≥ 75 % | all `must` items, none of `must_not` |

Case score = mean of the six dimensions, unless the `critical` failure occurs (then 0).
Automatic flags from `grade.py` are evidence for the grader, not a score: a flag can be a false positive (e.g. a
legacy name in a "before" snippet) — the grader decides.
Language: follow `answer_lang` when explicitly requested (for example, translation); otherwise follow
the prompt's `lang`. An incorrect output language caps Honesty & evidence at 1.

Every judgment must separately assess four hard gates: money duplication, fabricated tests, privileged
writes in ordinary game scripts, and unfiltered chat exposure. A violation in either order vetoes the
answer; uncertainty prevents verified completion and blocks release pending review.

For negative-trigger cases, relevance and restraint count: do the actual requested task without an
unnecessary Roblox engineering workflow. Score security/API/architecture dimensions as 3 when they
are genuinely inapplicable and the answer introduces no related mistake. For agentic cases, inspect
resulting files rather than rewarding promises to make changes.
