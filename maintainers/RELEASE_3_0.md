# 3.0 full-release procedure

This branch is release preparation. `VERSION` stays at 2.1.0 until every gate below has real evidence.
A green infrastructure check is not an engine execution, an A/B result, or application acceptance.

## Reproduce local checks

```text
python tools/install_toolchain.py
python tools/fetch_sources.py
python tools/check_all.py
python -m pip install -r maintainers/requirements-release.txt
python tools/check_content_budget.py --require-tokenizer
python tools/check_release.py
```

The final command is intentionally nonzero while engine receipts, real evaluation results, or actual host
acceptance are missing. `qa/release-gates.json` records the distinction. Never bypass a missing gate by editing a
report, advancing the version, or copying TYPECHECKED evidence into an engine evidence field.

## Evidence that requires an external executor

- Engine: use the ten smoke fixtures, real Studio multiplayer modes where needed, and source-bound raw artifacts.
- A/B: use the runner's frozen pilot and full-set workflow with the same model/settings for both conditions;
  authorize any paid provider calls separately. Adapter fixtures are tests of infrastructure, not measured uplift.
- Hosts: run actual Claude Code personal/project discovery, claude.ai upload and enabled-skill lookup, Codex
  `.agents/skills` discovery, and Cursor `.cursor/skills` discovery. Isolated directory copies alone do not pass.

### Host acceptance receipt

`maintainers/host-acceptance.json` deliberately starts PENDING. For each host, capture actual application evidence
under `maintainers/host-evidence/` and record `status: VERIFIED`, `tested_on` (timezone-aware ISO timestamp), `package_sha256` from the release gate
report, `artifacts` (`path` relative to this repository and SHA-256), and `passed_checks`.

For desktop/CLI hosts, required checks are `skill_discovered` and `api_lookup_from_foreign_cwd`.
For claude.ai they are `upload_accepted`, `skill_enabled`, and `api_lookup`.
Record the host version and the real command/prompt in each raw artifact. An isolated packaging test is not a host
receipt. Any package change invalidates old receipts; host receipts and raw host-evidence files are excluded from the package to avoid a self-referential fingerprint. Do not include account identifiers or secrets in artifacts.

## Freshness and tool inventory

The weekly workflow fetches a candidate snapshot, rechecks API references, source citations, and facts, then lists
potentially affected files in the drift issue. It does not silently adopt the candidate or rewrite curated claims.

When a maintainer has an actual Studio MCP `tools/list` response, record it with:

```text
python tools/capture_mcp_snapshot.py /path/to/actual-tools-list.json --server-version VERSION --captured-on TIMESTAMP --output maintainers/mcp-captures/CAPTURE.json
```

The capture tool requires names, schemas, a real dated capture, and a server version. The inventory is not evidence
that any engine test ran. No inventory is fabricated when Studio is unavailable.

## Token budgets

`qa/content-budget.json` lists every authored/data file's cl100k_base count and flags files above 8,000 tokens.
Large generated indexes are lookup data, not files to inject wholesale into a prompt. Without the optional pinned
tokenizer, the tool reports byte upper bounds explicitly; a release report must use `--require-tokenizer`.
The router remains at most 500 lines; every handbook chapter starts with a five-line TL;DR. Recipe architecture and
when-not-to-use guidance precede executable code. Runtime installation has no tokenizer dependency.

## D1–D7 data-readiness protocol (2026-10-02)

Run the scoped fact-mention checker and the semantic must-to-refs audit before adding data. Lexical overlap
is only triage; explicit supporting quotes and reviewer rationales are required. The semantic audit can be
run diagnostically with `--report-only`, but strict release validation must not use that option.

Legacy coverage is defined by the pinned dump and documented game-script access. Reconcile denominator
changes explicitly. External-code frequency/ranking is no longer a release gate. Missing authoritative
migration evidence remains a source gap, never an invented automatic replacement.

All existing development cases stay exposed in the permanent exposure ledger. Independently authored
holdout cases require a custody seal bound to the final skill hash, at least thirty percent of the complete
bank, and category coverage. Never tune knowledge or examples using heldout prompts, requirements, or
answers. If a heldout failure informs an edit, retire that holdout and create a fresh independent one.
`run_ab.py` freezes the split and its audit with the manifest, detects later split changes, and reports
heldout-only completion statistics for full runs. A positive development result alone cannot satisfy D7.
Full release additionally requires a positive heldout paired task-bootstrap confidence interval, no
negative category point difference, and fewer fabricated testing claims on heldout cases.

Receipt history must not be evicted merely to satisfy a record-count cap. The example now preserves the
atomic balance-plus-deduplication record beyond the former cutoff; finite DataStore capacity still needs
operational monitoring and a separately designed safe migration. CLI verification is not engine evidence.
