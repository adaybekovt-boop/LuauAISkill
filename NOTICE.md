# Licenses and attribution

## This package
- Authored text (SKILL.md, tracks, handbook, recipes' prose, references, evals, READMEs): **Creative Commons
  Attribution 4.0 International** — https://creativecommons.org/licenses/by/4.0/legalcode. Attribute as
  "LuauAISkill (TK Luau + Roblox), version 2.1.0, 2026-10-02" and indicate changes.
- Code (tools/*.py, examples/**/*.luau, tests): MIT — [licenses/LICENSE-CODE.txt](licenses/LICENSE-CODE.txt).
  Provided without warranty; examples are typechecked and partly unit-tested but not run in Roblox Studio.

## Third-party material and data
| Source | Used as | License / terms |
|---|---|---|
| Roblox Creator Documentation — https://github.com/Roblox/creator-docs (pinned commit in `sources/lock.json`) | facts cited as `cd:` references; **API summaries and deprecation messages copied into `api/summaries.jsonl` and `api/deprecated.tsv`** | prose CC BY 4.0, code samples MIT (see that repository's LICENSE and LICENSE-CODE); © Roblox Corporation and contributors. The summaries are unmodified excerpts; everything else is paraphrased. |
| Roblox engine API dump via https://github.com/MaximumADHD/Roblox-Client-Tracker (pinned commit) | class/member names, signatures, security, tags → `api/*.tsv` | factual reflection metadata of the Roblox client; not redistributed in raw form |
| Luau website — https://github.com/luau-lang/site (pinned) | facts cited as `luau:` references | see that repository's LICENSE |
| luau-lsp definitions — https://github.com/JohnnyMorganz/luau-lsp (pinned) | used locally for typechecking only (downloaded into `.cache/`, not redistributed) | MIT |
No third-party images, models, audio, fonts or binaries are included. Asset ids are never hard-coded in examples.

Roblox, Roblox Studio and related marks belong to Roblox Corporation. This package is independent and not endorsed
by or affiliated with Roblox Corporation.
