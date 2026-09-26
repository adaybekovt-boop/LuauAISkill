# Track: legacy code & modernization

Use for: old scripts, free models, deprecated APIs, "modernize/upgrade this code".
Load: [legacy catalog](../references/legacy-modernization/CATALOG.md) → [anti-patterns](../references/anti-patterns.md) →
[AI failure modes](../references/ai-failure-modes.md).

Method
1. `python tools/scan_legacy.py <path>` (read-only) → list of findings with catalog ids.
2. For each finding read the catalog entry: why, modern form, **when the old form is still acceptable**, security notes.
3. Change behaviour-preserving pieces first; list any behaviour change explicitly; keep diffs reviewable.
4. Verify each replaced API with `python tools/api.py <Class.Member>`.
Evals: `evals/cases/api-freshness.jsonl`, `evals/cases/adversarial.jsonl`.
