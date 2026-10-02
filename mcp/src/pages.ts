// Minimal server-rendered pages for the site and the OAuth consent step. Everything interpolated is escaped.
import type { ConsentDescription } from "@cloudflare/workers-oauth-provider";
import type { ApiKey } from "./keys";

export const escape = (value: string) => value.replace(/[&<>"']/g, (ch) => `&#${ch.charCodeAt(0)};`);

const STYLE = `
:root{color-scheme:light dark;--bg:#fff;--fg:#111;--muted:#666;--line:#ddd;--accent:#1a5fff}
@media (prefers-color-scheme:dark){:root{--bg:#111;--fg:#eee;--muted:#999;--line:#333;--accent:#6e9bff}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:16px/1.5 system-ui,sans-serif}
main{max-width:720px;margin:0 auto;padding:48px 16px}h1{font-size:22px;margin:0 0 16px}h2{font-size:18px}
p{margin:0 0 12px}.muted{color:var(--muted)}.box{border:1px solid var(--line);border-radius:10px;padding:16px;margin:16px 0}
.btn{display:inline-block;border:1px solid var(--line);border-radius:8px;padding:10px 16px;background:none;color:var(--fg);
font:inherit;cursor:pointer;text-decoration:none}.btn.primary{background:var(--accent);border-color:var(--accent);color:#fff}
.row{display:flex;gap:8px;flex-wrap:wrap;margin-top:16px}code{word-break:break-all}dl{display:grid;grid-template-columns:auto 1fr;gap:4px 16px;margin:0}
dt{color:var(--muted)}dd{margin:0;overflow-wrap:anywhere}.warn{border-color:#c80;}
input,select{font:inherit;max-width:100%;padding:10px;border:1px solid var(--line);border-radius:6px;background:var(--bg);color:var(--fg)}
button,a,input,select{min-height:44px}a:focus-visible,button:focus-visible,input:focus-visible,select:focus-visible{outline:3px solid var(--accent);outline-offset:3px}
pre{white-space:pre-wrap;overflow-wrap:anywhere}form{margin:12px 0}hr{border:0;border-top:1px solid var(--line);margin:20px 0}`;

export function page(title: string, body: string, status = 200, headers?: Headers): Response {
	const h = headers ?? new Headers();
	h.set("Content-Type", "text/html; charset=utf-8");
	h.set("Cache-Control", "no-store");
	if (!h.has("X-Frame-Options")) h.set("X-Frame-Options", "DENY");
	if (!h.has("Content-Security-Policy")) h.set("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'");
	return new Response(
		`<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">` +
			`<title>${escape(title)}</title><style>${STYLE}</style><main>${body}</main></html>`,
		{ status, headers: h },
	);
}

export function landingPage(): string {
	return `<h1>LuauAISkill</h1>
<p>Roblox engine API facts, legacy-code scan and the skill's handbook and recipes, served over MCP to Claude and other clients.</p>
<div class="row"><a class="btn primary" href="/login">Sign in with Google</a></div>`;
}

export function accountPage(opts: {
	email: string;
	policy: string;
	subscription: string;
	periodEnd: number | null;
	allowed: boolean;
	mcpUrl: string;
	csrf: string;
	operationId: string;
	usage: {used: number; limit: number | null; resets_at: number; calls_per_minute: number};
	billingReady: boolean;
	amount?: number;
	cancelAtPeriodEnd?: boolean;
	keys: ApiKey[];
	grants: {id: string; name: string}[];
	nextCursor?: string;
	newKey?: string;
	notice?: string;
}): string {
	const until = opts.periodEnd ? new Date(opts.periodEnd).toISOString().slice(0, 10) : "—";
	const csrf = `<input type="hidden" name="csrf" value="${escape(opts.csrf)}"><input type="hidden" name="operation_id" value="${escape(opts.operationId)}">`;
	const prices = Array.from({length: 18}, (_, i) => (i + 3) * 100)
		.map(n => `<option value="${n}"${n === (opts.amount ?? 700) ? " selected" : ""}>$${n / 100}/month</option>`).join("");
	const paid = opts.usage.limit === null;
	return `<h1>Account</h1>
${opts.notice ? `<p role="status">${escape(opts.notice)}</p>` : ""}
<div class="box"><dl>
<dt>Email</dt><dd>${escape(opts.email)}</dd>
<dt>Access</dt><dd>${opts.allowed ? "Active" : "Subscription required"}</dd>
<dt>Plan</dt><dd>${paid ? "Subscription" : "Free"}</dd>
<dt>Usage this week</dt><dd>${opts.usage.used}${paid ? " (no weekly limit)" : ` / ${opts.usage.limit}`}</dd>
<dt>Resets</dt><dd>${escape(new Date(opts.usage.resets_at).toISOString().slice(0, 16))} UTC</dd>
<dt>Rate limit</dt><dd>${opts.usage.calls_per_minute} tool calls / minute</dd>
<dt>Subscription</dt><dd>${escape(opts.subscription)} · until ${escape(until)}${opts.cancelAtPeriodEnd ? " · cancels at period end" : ""}</dd>
</dl></div>
<div class="box"><p>MCP server URL</p><p><code>${escape(opts.mcpUrl)}</code></p>
<p class="muted">Claude → Settings → Connectors → Add custom connector.</p></div>
<div class="box"><h2>Subscription · pay what you want</h2>
${opts.billingReady ? `<form method="post" action="${paid ? "/billing/price" : "/billing/checkout"}">${csrf}
<label>Monthly price <select name="amount">${prices}</select></label>
<button class="btn primary">${paid ? "Change price for future invoices" : "Continue to secure checkout"}</button></form>
${!paid ? `<form method="post" action="/billing/checkout/cancel">${csrf}<button class="btn">Cancel unfinished checkout</button></form>` : ""}
<form method="post" action="/billing/portal">${csrf}<button class="btn">Manage invoices, payment method and cancellation</button></form>`
: `<p class="muted">Payments are not available yet. Your free plan works without a payment card.</p>`}
</div>
<div class="box"><h2>API keys</h2><p class="muted">For clients using an Authorization header. Up to 5 active keys; each expires after 90 days.</p>
${opts.newKey ? `<p>Save this key now. It is shown only once.</p><pre><code>${escape(opts.newKey)}</code></pre>` : ""}
<form method="post" action="/account/keys">${csrf}<input name="label" maxlength="80" placeholder="Client name" aria-label="Key name" required>
<button class="btn">Create key</button></form>
${opts.keys.filter(k => !k.revoked_at && k.expires_at > Date.now()).map(k => `<form method="post" action="/account/keys/revoke">${csrf}
<input type="hidden" name="id" value="${escape(k.id)}">${escape(k.label)} · expires ${new Date(k.expires_at).toISOString().slice(0, 10)}
<button class="btn">Revoke key</button></form>`).join("")}
<p><code>Authorization: Bearer &lt;your key&gt;</code></p></div>
<div class="box"><h2>Connected apps</h2>
${opts.grants.length ? opts.grants.map(g => `<form method="post" action="/account/connections/revoke">${csrf}
<input type="hidden" name="id" value="${escape(g.id)}">${escape(g.name)} <button class="btn">Disconnect</button></form>`).join("") : "<p>No connected apps.</p>"}
${opts.nextCursor ? `<a class="btn" href="/account?cursor=${encodeURIComponent(opts.nextCursor)}">More apps</a>` : ""}</div>
<form method="post" action="/logout" class="row">${csrf}<button class="btn">Sign out</button></form>`;
}

export function subscriptionRequiredPage(email: string): string {
	return `<h1>Subscription required</h1>
<p>${escape(email)} has no active subscription.</p>
<div class="row"><a class="btn" href="/account">Account</a></div>`;
}

export function errorPage(message: string): string {
	return `<h1>Sign-in failed</h1><p>${escape(message)}</p><div class="row"><a class="btn" href="/">Start again</a></div>`;
}

export function consentPage(details: ConsentDescription, handle: string, email: string): string {
	const name = escape(details.clientName || "An application");
	const origin = details.clientDomain
		? `Published by <strong>${escape(details.clientDomain)}</strong>.`
		: "This app registered itself; its name is not verified.";
	const loopback = details.redirectIsLoopback
		? `<div class="box warn"><p><strong>Access will go to an app on this computer.</strong> Continue only if you just started connecting from it.</p></div>`
		: "";
	const scopes = details.scope
		.map((s) => `<input type="hidden" name="scope" value="${escape(s)}">`)
		.join("");
	return `<h1>Connect ${name} to LuauAISkill?</h1>
<div class="box"><dl>
<dt>Account</dt><dd>${escape(email)}</dd>
<dt>Sends access to</dt><dd><strong>${escape(details.redirectHost)}</strong></dd>
<dt>Permissions</dt><dd>${details.scope.map(escape).join(", ") || "mcp"} (read-only tools)</dd>
</dl><p class="muted" style="margin-top:12px">${origin}</p></div>
${loopback}
<form method="post" action="/authorize">
<input type="hidden" name="handle" value="${escape(handle)}">${scopes}
<label><input type="checkbox" name="remember" value="1"> Don't ask again for this app</label>
<div class="row"><button class="btn primary" name="decision" value="approve">Allow</button>
<button class="btn" name="decision" value="deny">Deny</button></div>
</form>`;
}
