# Executable release smoke fixtures

**Engine status: NOT RUN.** These are disposable Studio/Open Cloud test fixtures, not proof that any recipe
passed an engine run. Seven Luau files provide bounded server/client coordination and ten recipe-specific cases.
The fixtures reference the original recipe sources instead of copying implementations.

- [Runbook, coverage limits, and artifact format](../../maintainers/engine-smoke/README.md)
- [Required cases and current evidence status](../../maintainers/engine-smoke/manifest.json)
- [Evidence validator](../../tools/check_engine_evidence.py)

Run from the repository root:

```sh
python tools/check_engine_evidence.py --allow-pending
python -m unittest discover -s tests -p test_engine_evidence.py
python tools/check_engine_evidence.py
```

The first command validates infrastructure and explicitly reports pending execution. The last is the release gate:
it exits nonzero until all ten current-source engine receipts and required visual captures exist.

Each `projects/<case>.project.json` is a separate, disabled-by-default Rojo place. Build/open one at a time. Do not
sync this test project into an existing game. Original recipe server Scripts live in `ServerStorage.SmokeScripts`
and are cloned into the test server only after the primitive scene fixture is ready. Test-only remotes never belong
in a shipped experience. Stop and discard the entire test session after every case, including failures/timeouts.

The shared server/client protocol executes actual recipe remotes and observes server state; it never substitutes
`Instance.new("Player")`, invokes server signal callbacks directly, mocks DataStores, or labels CLI execution as
engine testing. Module lookup is dynamic because each isolated fixture contains different original modules; those
source modules are independently checked in their own example projects.
