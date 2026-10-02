# luau-skill MCP server (Cloudflare Worker)

A remote, read-only MCP server, behind Google sign-in + OAuth, that serves the tk-luau-roblox skill to any MCP client: engine API facts, legacy-code
scan, ranked search over the handbook/recipes/references, and the documents themselves. It is stateless
(Streamable HTTP, JSON responses, no sessions, no Durable Objects, no storage) and built **from this repository on
every deploy**, so a push to GitHub updates the server.

Endpoint: `https://luaumcp.tklabsskill.site/mcp` · site: `/` · build info: `/health`.

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
   - **Worker name**: `luauaiskill` — must equal `name` in `wrangler.jsonc` (change one or the other).
   - **Root directory**: `mcp` with **Build command** `npm ci` — or leave Root directory `/` and Build command
     empty: the repository-root `wrangler.jsonc` installs `mcp/` and builds the same Worker.
   - **Deploy command**: `npx wrangler deploy` (default)
   - **Production branch**: the branch you merge into (`main`). Until this folder is on `main`, point it at the
     branch that has it, or builds fail with "no wrangler config".
3. Nothing else to configure: `wrangler.jsonc` runs `node scripts/build-data.mjs` before bundling, which reads
   `../api`, `../references` and the Markdown from the same checkout. No Python is needed in the build.
4. Open `https://luaumcp.tklabsskill.site/health` — it reports skill version, commit, engine API version and
   counts. That commit should match the one you pushed.

Size: ≈ 4.6 MB upload, ≈ 0.95 MB gzip (Free plan limit 3 MB gzip). Startup parses the bundled data once per isolate
(~0.1 s); requests then take a few ms of CPU (`scan_legacy` on a few hundred lines ≈ 5–12 ms; the Free plan allows
10 ms per request — use Workers Paid if you scan large files often).

## Connect a client
| Client | How |
|---|---|
| Claude Code | `claude mcp add --transport http luau-skill https://luaumcp.tklabsskill.site/mcp`, then `/mcp` → Authenticate (opens the browser sign-in) |
| claude.ai / Claude Desktop | Settings → Connectors → Add custom connector → the `/mcp` URL → Connect → Google sign-in → Allow |
| Cursor | `.cursor/mcp.json`: `{ "mcpServers": { "luau-skill": { "url": "https://…/mcp" } } }` |
| Others | any client with Streamable HTTP; for stdio-only clients use a bridge such as `npx mcp-remote https://…/mcp` |
With the skill also installed locally, the agent can use either path; SKILL.md tells it to prefer these tools when
they are connected.

## Access: Google sign-in + OAuth
`/mcp` is an OAuth 2.1 protected resource (`@cloudflare/workers-oauth-provider`). When a user presses **Connect**
in Claude, the client discovers this server (401 → `/.well-known/oauth-protected-resource/mcp` →
`/.well-known/oauth-authorization-server`), registers itself (`/register`, or a Client ID Metadata Document), and
opens `/authorize`. There the user signs in **with Google** on this site (`/login`), sees a consent page (client
name, where access goes) and approves; Claude receives a token and calls `/mcp` with it.

- Users live in D1 (`users`, created on first use: Google `sub`, email, subscription status/period end).
- `ACCESS_POLICY` (var): `registered` — any signed-in Google user with a verified email; `subscribed` — an active
  subscription (`subscription_status = active` and period end in the future). The check runs at consent **and on
  every MCP request**, so ending a subscription cuts access immediately (tokens alone are not enough).
- Until a payment provider is wired, grant subscriptions manually:
  `curl -X POST https://<host>/admin/subscription -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" -d '{"email":"user@gmail.com","status":"active","period_end":1767225600000}'`
  (`period_end` in ms; omit for no end; `status: none|canceled` revokes). A payment webhook will call the same update.
- Site: `/` (sign in), `/account` (status + MCP URL), `/logout`, `/health` (JSON build info).
- Security: PKCE everywhere (Claude ↔ server and server ↔ Google), Google `state` bound to the browser by a cookie,
  consent page can't be framed or replayed from another browser, unverified Google emails are refused, sessions are
  opaque cookies with only their hash in KV, tokens/grants are hashed by the library.

### One-time setup
1. **Google OAuth client** — Google Cloud Console → APIs & Services:
   - OAuth consent screen: External, app name, support email; scopes `openid`, `email`, `profile` (non-sensitive,
     no verification needed). Set publishing status to **In production**, otherwise only listed test users can sign in.
   - Credentials → Create OAuth client ID → Web application → Authorized redirect URI:
     `https://luaumcp.tklabsskill.site/auth/google/callback`.
2. **Secrets** — Cloudflare → Workers → `luauaiskill` → Settings → Variables and Secrets (type *Secret*):
   `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `CONSENT_SECRET` (40+ random chars), `ADMIN_TOKEN` (random).
3. **Storage** — `wrangler.jsonc` declares `OAUTH_KV` and D1 `DB` without ids; wrangler creates them on the first
   deploy. If the Workers Builds token can't create resources, create a KV namespace and a D1 database
   (`luauaiskill-users`) in the dashboard and add their ids to both `wrangler.jsonc` files.
4. `PUBLIC_URL` (var) must be the origin users reach (`https://luaumcp.tklabsskill.site`); OAuth metadata and the
   Google redirect URI are built from it, so the `*.workers.dev` hostname won't authorize.
5. Deploy, then in Claude remove the old connector and add `https://luaumcp.tklabsskill.site/mcp` again.

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
