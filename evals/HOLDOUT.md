# Development exposure and sealed holdout

The original 167 cases were visible during skill development. The 15 D6 additions
were also written while inspecting the skill. All 182 are **development-exposed**,
including pilot cases. Randomly labeling some of them “holdout” would not measure
out-of-sample improvement. No real A/B execution is implied by structural checks.

`development-exposure.json` records these IDs permanently. `split.json` binds each
case to its canonical content and every referenced fixture/project source file.
`python tools/check_eval_bank.py` reports category balance, Russian prompts,
documented broken-code fixtures, hashes, provenance, and clean holdout fraction.
`--require-ready` exits 2 until all structural/holdout gates pass. Its normal exit 0
means the audit ran, not that D6 passed. D6 also requires actual pilot/full runs.

## Adding a genuinely sealed holdout

1. Freeze the final skill snapshot and record both its commit and content SHA-256.
2. An independent author who has not inspected the skill implementation or
   development cases prepares fresh tasks covering every category. Keep their
   prompts, criteria, and fixtures unavailable to authors improving the skill.
3. A custodian imports the cases for the evaluator only. With 182 development
   cases, at least 78 clean cases are required for a 30% share of the total bank.
   Case IDs cannot reuse development or pilot IDs. An 85-case set gives 85/267.
4. Record each case in `split.json` with `exposure: sealed_holdout`, its content
   hash, and the provenance below. Never run `--freeze-development` on an imported
   sealed bank; that command refuses an existing holdout and cannot create one.
5. Evaluate once under frozen settings, including heldout-only D7 statistics and
   category comparisons. After inspecting holdout failures to improve the skill,
   retire that holdout to development and obtain a fresh independent holdout.

Provenance requires `external_author`, `custodian`, `sealed_at`, `skill_commit`,
`skill_sha256`, `seal_artifact`, `seal_sha256`, `no_development_use: true`, and
`ever_development_exposed: false`. The referenced JSON custody artifact repeats
these identity/time/snapshot fields and booleans and includes `case_hashes` mapping
case IDs to their hashes. `seal_sha256` hashes the artifact's exact bytes. The
runner must compare `seal_skill_sha256` returned by the audit to the actual frozen
skill snapshot, not just the repository commit (a dirty tree can share a commit).

The case hash is SHA-256 over UTF-8 canonical JSON with sorted keys, no ASCII
escaping, and separators `(',', ':')`: an object with `case` (the raw JSONL object)
and `files` (sorted map from fixture/project source paths to exact UTF-8 contents).
Use `check_eval_bank.case_hash(case, root)` rather than duplicate the algorithm.

Custody records are attestations, not cryptographic proof that a model never saw a
case. Access isolation and non-exposure require independent operational review.
A ZIP hash alone proves integrity, not independence. Do not count an unreviewed
archive as clean holdout simply because it is named “sealed”.

## Broken-code coverage

`fixture-defects.json` describes intentional defects in existing fixtures. New
regression cases can provide `fixture_defect` alongside their fixture. The audit
checks that documented code files exist and are nonempty; semantic defect review
is still required. The negative-trigger fixture deliberately contains broken Luau
but requests only translation of a comment: repairing the code or loading the
Roblox workflow would fail its actual task. Fixtures are not production examples.
