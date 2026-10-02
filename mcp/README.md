# luau-skill MCP server (Cloudflare Worker)

A remote, read-only MCP server that serves the tk-luau-roblox skill to any MCP client: engine API facts, legacy-code
scan, ranked search over the handbook/recipes/references, and the documents themselves. It is stateless
(Streamable HTTP, JSON responses, no sessions, no Durable Objects, no storage) and built **from this repository on
every deploy**, so a push to GitHub updates the server.

Endpoint: `https://<worker>.<account>.workers.dev/mcp` · health/info: `/` or `/health`.

## Tools
| Tool | Same as | Does |
|---|---|---|
| `api_lookup` | `tools/api.py X` | existence, signature, security, game-script read/write/call verdict, deprecation + replacement, yields, parallel safety, undocumented |
| `api_search` | `tools/api.py --search` | substring search over class/member/enum/datatype names |
| `api_deprecated` | `tools/api.py --deprecated` | deprecated members of a class with replacement and reason |
| `scan_legacy` | `tools/scan_legacy.py` | legacy/deprecated patterns in submitted Luau code (≤ 200k characters) |
| `search_skill` | `tools/search.py` | BM25 search over the skill's Markdown (heading ×4, body ×1) |
| `read_skill_doc` | reading a file | SKILL.md, tracks, chapters, recipes, references; optional heading filter; paged |
| `list_skill_docs` | `ls` | documents under a prefix |
Resource: `skill://SKILL.md`. Server `instructions` carry the workflow and hard rules, so clients that show them get
the router even before reading SKILL.md. Output of `api_lookup`, `api_search`, `api_deprecated` and `scan_legacy` is
byte-identical to the Python tools (enforced by `test/parity.test.mjs`).

## Deploy with Workers Builds (GitHub → Cloudflare)
1. Cloudflare dashboard → Workers & Pages → Create → **Import a repository** → this repository.
2. Build settings:
   - **Worker name**: `luau-skill-mcp` — must equal `name` in `wrangler.jsonc` (change one or the other).
   - **Root directory**: `mcp`
   - **Build command**: `npm ci`
   - **Deploy command**: `npx wrangler deploy` (default)
   - **Production branch**: the branch you merge into (`main`). Until this folder is on `main`, point it at the
     branch that has it, or builds fail with "no wrangler config".
3. Nothing else to configure: `wrangler.jsonc` runs `node scripts/build-data.mjs` before bundling, which reads
   `../api`, `../references` and the Markdown from the same checkout. No Python is needed in the build.
4. Open `https://luau-skill-mcp.<account>.workers.dev/` — it reports skill version, commit, engine API version and
   counts. That commit should match the one you pushed.

Size: ≈ 4.6 MB upload, ≈ 0.95 MB gzip (Free plan limit 3 MB gzip). Startup parses the bundled data once per isolate
(~0.1 s); requests then take a few ms of CPU (`scan_legacy` on a few hundred lines ≈ 5–12 ms; the Free plan allows
10 ms per request — use Workers Paid if you scan large files often).

## Connect a client
| Client | How |
|---|---|
| Claude Code | `claude mcp add --transport http luau-skill https://luau-skill-mcp.<account>.workers.dev/mcp` → check with `/mcp` |
| claude.ai / Claude Desktop | Settings → Connectors → Add custom connector → the `/mcp` URL (works only without `MCP_TOKEN`; those clients use OAuth, not static headers) |
| Cursor | `.cursor/mcp.json`: `{ "mcpServers": { "luau-skill": { "url": "https://…/mcp" } } }` |
| Others | any client with Streamable HTTP; for stdio-only clients use a bridge such as `npx mcp-remote https://…/mcp` |
With the skill also installed locally, the agent can use either path; SKILL.md tells it to prefer these tools when
they are connected.

## Access control
The data is the public content of this repository, so the server is open by default. To restrict it:
`npx wrangler secret put MCP_TOKEN` (in `mcp/`) → `/mcp` then requires `Authorization: Bearer <token>`
(Claude Code: `--header "Authorization: Bearer <token>"`). For abuse protection add a Cloudflare WAF rate-limiting
rule on `/mcp`. All tools are read-only; nothing writes, fetches the network or runs submitted code (`scan_legacy`
only runs the catalog's regexes over the text).

## Develop
```text
cd mcp
npm ci
npm test            # builds data, bundles, runs protocol tests + parity with tools/*.py (needs python3)
npm run typecheck
npx wrangler dev    # http://127.0.0.1:8787/mcp ; inspect with: npx @modelcontextprotocol/inspector
```
`src/generated/` is produced by `scripts/build-data.mjs` and gitignored. Change behaviour in `src/*.ts`, keep it in
step with the Python tool it mirrors, and let the parity test prove it.
