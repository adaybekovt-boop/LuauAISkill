# Dated, source-backed facts

`references/facts.json` is the single source for the generated [limits table](../references/limits.md).
Do not edit the table by hand. These are explicit statements about a cited snapshot, not measurements of a
live engine or promises that a feature works in every Studio/client version.

## Schema

The top-level object has `schema_version: 1`, `source_pins`, optional `url_sources`, and a nonempty `facts` array.
Each fact has:

| Field | Meaning |
|---|---|
| `id` | Unique stable lowercase kebab-case identifier |
| `section` | Human-table grouping |
| `statement` | Narrow claim including important conditions |
| `value` | Finite JSON number, string, boolean, array, or object; never null or empty |
| `unit` | Explicit unit and scope; formulas name their independent variables |
| `status` | `documented`, `approximate`, `default`, `beta`, `ga`, or `deprecated` |
| `source` | Creator-docs reference, reflected API reference, supported official URL, or exact pinned blob URL |
| `checked_on` | Actual review date in `YYYY-MM-DD`, not the source's publication date |
| `expires_after` | Positive integer days, at most 366; expires at the start of checked_on + this duration |
| `evidence` | One or more short exact excerpts supporting the statement; whitespace wrapping is ignored |
| `notes` | Optional qualifiers, source conflict explanation, or limitations |

`documented` describes evidence, not maturity. `default` is not a hard maximum. `approximate` must retain the
source's approximation. Release statuses require explicit evidence: an API's presence or a missing beta banner
is insufficient. A release date is a separate fact, never inferred from a commit date or an expiry deadline.

Arrays can express a minimum/maximum or dimensions, with the statement and unit making the interpretation
explicit. Strings preserve formulas and source notation such as `64K` without inventing a conversion. `players`
means players in a server; `concurrent_users` means users across an experience; `lifetime_users` means users who
have ever joined. Data-store experience rate budgets are separate by store type and operation.

## Source resolution and evidence

- Creator-docs references resolve to Markdown/YAML under `content/en-us` at the locked commit. Existing examples
  include `cd:projects/server-authority/index` and `cd:reference/engine/classes/RemoteEvent`.
- API references resolve in the locked `Full-API-Dump.json`, including inherited class members and enum items.
  For example, `api:ParticleEmitter.FlipbookIncompatible` supports a fact about its reflected default message.
  API reflection does not establish rollout status or live behavior.
- Official Creator Hub/Luau document URLs resolve to the corresponding locked corpus document. A GitHub blob
  URL must contain the exact locked SHA and point into that corpus. The Open Cloud limits cite the actual
  `content/en-us/reference/cloud/openapi.json`, not the landing page that merely links to it.
- Dated official announcements outside the Git corpus require a reviewed, minimal extract in
  `references/fact-sources/`, registered under their exact HTTPS URL in `url_sources` with a SHA-256 digest.
  The extract records URL, author, publication date, retrieval date, and the short relevant quote. It is clearly
  labeled as an extract, not a complete page archive. Review the original official announcement before recording
  or refreshing it. CI verifies local integrity/resolution, not current remote availability or staff identity.

The checker reads immutable Git blobs rather than trusting editable cached files. `source_pins` must match
`sources/lock.json`. Missing repos, unavailable blobs, changed pins, missing registered extracts, hash mismatches,
and excerpts absent from the pinned source are failures. An external live URL with no corpus mapping or reviewed
extract is a failure, not a successful HEAD request.

The checker establishes structural/provenance consistency. A human still needs to verify that a selected excerpt
supports the claim, that a formula is transcribed correctly, and that no later authoritative source overrides it.
It does not mechanically prove arbitrary prose, arithmetic, or a rollout's state.

## Known source precedence decision

The 2026-07-09 [official server-authority full-release announcement](https://devforum.roblox.com/t/full-release-ship-fair-and-competitive-games-with-server-authority/4727993)
explicitly announced availability for all games. It overrides the stale beta sentence in the pinned network-ownership
guide. Both the full-release status and date are stored in facts, with the announcement extract retained for audit.
Do not regress this to beta by copying an isolated documentation line. Related subfeatures must be assessed separately.

## Review and CI workflow

1. Fetch the intended baseline with `python tools/fetch_sources.py`. Do not use `--latest` as an automatic remedy
   for failing facts. A baseline update requires review of the source and API changes.
2. Review each changed/expired claim against its actual source. Preserve qualifications and scope, and resolve
   conflicting official sources. Update values/evidence and `checked_on` only after that review.
3. On a baseline change, review all affected facts before updating `source_pins`. For announcement extracts,
   recheck the source, update the retrieval date, then recompute the file's SHA-256 digest.
4. Run `python tools/check_facts.py`, then `python tools/render_facts.py`.
5. Run `python tools/render_facts.py --check` and `python -m unittest discover -s tests -p 'test_facts.py'`.
6. Run the aggregate repository checks. CI must invoke both the facts validator and rendered-table check.

Normal checks use today's UTC date. `--as-of YYYY-MM-DD` supports explicitly historical reproduction and expiry
boundary tests; do not use a past date to make a release appear fresh. Facts fail on their expiry date, not the day
after. Current policy uses 30 days for rollout status, 90 days for changing service/engine limits, and 180 days for
an established release date. These are review intervals chosen by maintainers, not platform guarantees.

Python unit tests use temporary local Git repos and the historical reviewed data date, so they work without the
upstream corpus or network. The full facts check intentionally fails when the actual pinned corpus is absent.
