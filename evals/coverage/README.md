# Knowledge coverage audit (D5)

Run `python tools/check_eval_coverage.py`. The default is a strict readiness gate;
`--report-only` allows unresolved semantic coverage but still fails malformed or
stale evidence. The report is generated, not manually edited.

## Evidence and limits

`baseline.json` records the original development bank before this audit: its case
file hashes, case count and obligation count. “Not previously measured” is not a
claim that no knowledge existed.

`reviews.json` is the authoritative reviewed mapping. Each record binds case ID,
must index, exact must text and its SHA-256 to one or more exact quotations in
that case's declared refs. It records the reviewer, date, semantic rationale and
status. Separate `reviews-world.json`, `reviews-visual.json` and `reviews-api.json`
are contributor review artifacts; merged master records are authoritative.

The checker validates paths, declared refs, quotation presence, demand hashes,
duplicates, orphaned reviews and correction-source integrity. It does **not**
prove semantic entailment through string comparison. A human or independent
judge can contest the recorded assistant semantic reviews. Matching words only
produce `candidates_not_proof`, never a coverage pass. The current review was
performed by assistant reviewers reading the cited content, not by an independent
human panel or paid model-evaluation run.

Statuses are `supported`, `missing`, `ambiguous`, `unreviewed`, and `invalid`.
The latter is a computed integrity failure. Every status other than supported
blocks the D5 readiness gate. Refresh a stale quotation only after rereading its
meaning; do not automatically replace it with a search hit.

## Demand corrections and architectural ambiguity

`criterion-corrections.json` keeps original criteria alongside proposed or
accepted replacements. Accepted corrections require a source file hash and exact
source quote. The report counts corrected demand separately. A contradiction
between a recipe and a rubric is not by itself permission to weaken the rubric.

The Lighting.Technology criterion was corrected using the pinned API row:
RobloxScriptSecurity access, with no Deprecated dump tag, while documentation
describes supersession. LIT-08 retains its original server-ClockTime criterion
and remains ambiguous because its cited recipe recommends server-owned cycle
metadata with a client visual writer. This requires explicit adjudication;
neither interpretation has been established by an engine execution here.

## Measured changes

Missing declared references were added rather than copying existing chapters.
Only measured prose gaps were filled: unrelated-request nonactivation; runtime
division checks and top-N sorting; module startup/global ownership; purchase,
blink and chest validation; animation lifecycle and server-created Animator;
NPC bounded recovery; text-command validation/filter failure; diagnostic and
verification reporting; visual integration and measurement guidance.

Receipt coverage exposed count-based history eviction in both the new ledger
guidance and the older save-system implementation. The regression case
GAP-DATASTORES-REPLAY-01 demands old-receipt replay protection, new purchases
beyond arbitrary count caps, and safe durable-capacity failure handling.

All engineering categories have recipe refs. The negative-triggers category
intentionally has none: activating an engineering recipe would violate its
scope requirement. This is reported as a literal exception to the user's
every-category recipe target, not hidden as a completed metric.

The sealed held-out bank was not opened or used for these development changes.
Its later independent coverage audit must remain distinguishable from this
development audit; adding holdout-driven knowledge requires treating that bank
as development-exposed and obtaining a new untouched validation set.
