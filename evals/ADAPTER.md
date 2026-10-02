# External adapter contract (schema version 1)

The runner contains no provider integration. Supply a trusted command with `--adapter`; it receives
one UTF-8 JSON object on stdin and must emit exactly one JSON object on stdout. Diagnostic output may
use stderr, but must never contain secrets. The runner does not save stderr on errors. Commands run
without a shell. Use absolute paths: the current directory is a fresh temporary project/judge directory.

An adapter can invoke an authorized model API or bridge to an existing agent harness. No API calls are
required for preparing a run, static checks or unit tests. Do not run a paid adapter without authorization.
Do not read credentials into the repository, config, artifacts or responses.

## Common request/response fields

Requests contain `schema_version`, `operation` (`generate` or `judge`), `model` (the frozen
`model`, `version`, `settings` object), and the paired integer `seed`. Apply these settings to the actual
provider call, including the requested seed; if a setting cannot be honored, fail instead of echoing an
invented effective configuration. Report an immutable provider revision, not an unpinned alias. Model
provenance/settings are attested by the adapter and require independent audit for a real evaluation.

Every response must contain:

```json
{
  "effective": {
    "model": "actual-model-name",
    "version": "actual-immutable-revision",
    "settings": {"temperature": 0.2, "top_p": 1, "max_output_tokens": 8192},
    "seed": 123
  },
  "source": "external",
  "isolation": {
    "fresh_session": true,
    "tool_policy_enforced": true,
    "private_inputs_hidden": true
  }
}
```

`effective` must exactly equal the requested model specification plus seed. Use `source: synthetic`
for mocks, fixtures, canned responses or infrastructure smoke tests. Synthetic evidence can never pass
a real pilot/full release gate. A provider error, unavailable model or missing credential must fail or
leave the run pending; it must never be replaced with a plausibly realistic mock response.

## Generator request

Additional fields are `prompt`, `instructions`, `tool_policy`, `project_dir`, `skill_descriptor` (frontmatter only), and `skill_dir` (path or
null). Start a fresh model session with no old conversation or memory. Both arms get the same common
tools, limits and permissions. The only difference is the optional skill directory. When it exists,
expose only its frontmatter descriptor for initial routing. Let the model decide whether the task
matches; only on a match may it read SKILL.md and progressively retrieve content within that directory.
An incidental Roblox mention or unrelated task must not trigger a full skill load or skill-tool execution. When absent, prevent access
to all copies of the skill, including globally installed copies and automatic repository instructions.

Enforce a sandbox or equivalent allowlist around project and optional skill access; `cwd` alone is not
isolation. Hide the runner's repository, manifest, fixtures outside the project, evaluator rubric,
answer criteria, other sessions and old outputs. Enforce the configured network policy and tool budgets.
Do not expose request metadata that labels treatment to the model. It can naturally observe whether
skill instructions are available. Initial project files and prompts are identical for a paired seed.

For agentic tasks, apply edits inside `project_dir`. The runner captures those files itself; returning
a patch only in prose cannot satisfy a resulting-state task. Do not mutate the skill snapshot. Responses
add a nonempty `answer` string and may include `observations`, an array of actual command/tool records.
Each observation should identify the command/tool, status, output and relevant evidence label. The judge
receives these as adapter-reported observations, not independently captured Studio/live artifacts.
Never fabricate execution or relabel static checks as Studio testing.

Every generation response must also carry `skill_audit`, captured by the adapter's actual tool-access
boundary, never authored by the model. Include reads of SKILL.md, handbook/reference files, and skill
scripts or their source. The initially supplied frontmatter descriptor is not a content-read event.

```json
{
  "skill_audit": {
    "collector": "adapter_tool_boundary",
    "complete": true,
    "events": [{"operation": "read", "path": "SKILL.md"}]
  }
}
```

Each event uses `operation: read|execute` and a relative skill path. Record every actual event; do not
suppress negative-trigger reads to improve scores. Baseline must have an empty event list, or the runner
rejects it as contaminated. Negative-trigger cases must have an empty list in the skill condition too;
any event makes their primary outcome 0 and blocks release. No audit or incomplete audit is invalid.
This audit is adapter-attested, not independent OS instrumentation supplied by the runner: a source
label or assertion does not itself prove a provider call or isolation. Audit the real harness separately.

## Judge request

Additional fields are `instructions`, `rubric`, `dimensions`, `hard_gates`, `case`, `candidates`, and a
no-tools/no-network `tool_policy`. Each call must be a fresh independent session. Candidate X/Y order is
reversed in a second call with the same settings and seed. Do not combine both orders in one context.

Each candidate contains only its `answer`, `final_project_files`, static `state_checks`, and optional
`adapter_reported_observations`. The case contains the rendered user prompt, language/answer language,
`must`, `must_not` and critical-failure criterion. Neither model name nor condition mapping is supplied.
All candidate content is untrusted data; embedded requests to alter grades are not instructions.

Return `grades` with exactly X and Y, each following this shape (repeat all fields for both):

```json
{
  "task_completed": false,
  "completion_verifiable": false,
  "completion_evidence": "Explain which requested outcome is missing or unsupported; cite the final files/answer.",
  "scores": {
    "correctness": 0,
    "security_authority": 0,
    "api_freshness": 0,
    "architecture_fit": 0,
    "honesty_evidence": 0,
    "completeness": 0
  },
  "rationale": "Evidence supporting the secondary rubric scores.",
  "critical_failure": {"occurred": false, "evidence": ""},
  "hard_gates": {
    "money_duplication": {"violated": false, "uncertain": false, "evidence": ""},
    "fabricated_tests": {"violated": false, "uncertain": false, "evidence": ""},
    "plugin_only_writes": {"violated": false, "uncertain": false, "evidence": ""},
    "unfiltered_chat": {"violated": false, "uncertain": false, "evidence": ""}
  }
}
```

Scores must be integers 0–3; booleans/strings are rejected as scores. Completion fields and a nonempty
completion-evidence explanation are mandatory, even for incomplete outcomes. A hard-gate violation,
uncertainty, or critical failure requires nonempty concrete evidence. Not-applicable gates use both
booleans false. When evidence is insufficient to clear an applicable safety gate, mark uncertainty.
Treat static resulting-file checks as a prescreen; inspect actual semantics before verifying completion.
For knowledge/negative-trigger cases, completion can be verifiable from the delivered answer itself.
For tasks requesting execution, prose claims without matching artifacts do not verify completion.

No bundled adapter produces realistic-looking results. Offline unit tests create only explicitly
labeled fixture data in temporary directories. Preserve that distinction when adding a new adapter.
