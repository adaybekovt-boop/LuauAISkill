// Engine API lookup — a port of tools/api.py. Output text matches the Python tool line for line (except the
// NOT FOUND hint, which names MCP tools instead of CLI flags) so test/parity.test.mjs can compare them.
import { api, meta } from "./generated/data.js";
import type { MemberRow } from "./types";

const UNDOCUMENTED_NOTE =
	"UNDOCUMENTED: no creator-docs reference page (internal, unreleased or in development). Do not build game code on it until documented or announced.";

interface Member {
	cls: string;
	member: string;
	kind: string;
	sig: string;
	read: string;
	write: string;
	thread: string;
	flags: string;
}

function member(cls: string, name: string, row: MemberRow): Member {
	const [kind, sig, read, write, thread, flags] = row;
	return { cls, member: name, kind, sig, read, write, thread, flags };
}

function flagSet(flags: string): Set<string> {
	return new Set(flags.split(",").filter((f) => f.length > 0));
}

export function resolveMember(cls: string, name: string): [string, Member] | null {
	const seen = new Set<string>();
	let c = cls;
	while (c && api.classes[c] && !seen.has(c)) {
		seen.add(c);
		const row = api.members[c]?.[name];
		if (row) return [c, member(c, name, row)];
		c = api.classes[c][0];
	}
	return null;
}

function verdict(m: Member): string[] {
	const flags = flagSet(m.flags);
	const notes: string[] = [];
	if (flags.has("deprecated") || flags.has("superseded")) {
		let pref = [...flags].find((f) => f.startsWith("prefer="))?.slice(7) ?? "";
		const dep = api.deprecated[`${m.cls}.${m.member}`];
		// The dump's preferred name is sometimes the same method on another class (Humanoid.LoadAnimation →
		// Animator:LoadAnimation); then only the message says where it moved.
		if (pref === m.member) pref = "";
		const message = dep?.[4] ?? "";
		notes.push("DEPRECATED/SUPERSEDED" + (pref ? ` -> use ${pref}` : "") + (message ? `. ${message}` : ""));
	}
	if (m.kind === "Property") {
		const blockedR = m.read !== "None" || flags.has("read:plugin-only") || flags.has("notscriptable");
		const blockedW =
			m.write !== "None" || flags.has("write:plugin-only") || flags.has("notscriptable") || flags.has("readonly");
		const whyW: string[] = [];
		if (m.write !== "None") whyW.push(m.write);
		if (flags.has("write:plugin-only")) whyW.push("PluginOrOpenCloud capability: Studio/plugin/command bar only");
		if (flags.has("notscriptable")) whyW.push("NotScriptable: set in Studio Properties");
		if (flags.has("readonly")) whyW.push("ReadOnly");
		notes.push(
			`game scripts: read ${blockedR ? "NO" : "yes"}, write ${blockedW ? "NO (" + whyW.join("; ") + ")" : "yes"}`,
		);
		if (flags.has("notreplicated")) notes.push("NotReplicated: value set on one side is not replicated to the other");
	} else {
		const blocked = m.read !== "None" || flags.has("call:plugin-only");
		notes.push(`game scripts: ${blocked ? "NO (" + m.read + ")" : "callable"}`);
		if (flags.has("yields"))
			notes.push("Yields: never call inside UpdateAsync transforms, BindToSimulation or tight loops");
	}
	if (flags.has("undocumented")) notes.push(UNDOCUMENTED_NOTE);
	if (flags.has("sim")) notes.push("Simulation Access: usable inside RunService:BindToSimulation");
	if (m.thread) {
		const t: Record<string, string> = {
			Safe: "parallel: safe",
			ReadSafe: "parallel: read-only (write in serial phase)",
			Unsafe: "parallel: serial phase only",
		};
		notes.push(t[m.thread] ?? `thread: ${m.thread}`);
	}
	return notes;
}

function docUrl(cls: string, name = ""): string {
	return `https://create.roblox.com/docs/reference/engine/classes/${cls}` + (name ? `#${name}` : "");
}

export function notFound(q: string): string {
	return (
		`NOT FOUND: ${q} is not in the API snapshot ${meta.apiClientVersion}. Do not use it. Check spelling, the ` +
		`superclass chain (api_lookup with include_inherited), or search: api_search`
	);
}

function showMember(cls: string, name: string): { found: boolean; text: string } {
	const hit = resolveMember(cls, name);
	if (!hit) return { found: false, text: notFound(`${cls}.${name}`) };
	const [owner, m] = hit;
	const out: string[] = [];
	out.push(`${cls}.${name}` + (owner !== cls ? `  (inherited from ${owner})` : ""));
	out.push(`  kind: ${m.kind}   type/signature: ${m.sig}`);
	const shown = m.flags
		.split(",")
		.filter((f) => f && f !== `prefer=${m.member}`)
		.join(",");
	out.push(`  security: read=${m.read} write=${m.write}   thread: ${m.thread}   flags: ${shown || "-"}`);
	for (const n of verdict(m)) out.push("  - " + n);
	const s = api.summaries[`${owner}.${name}`];
	if (s) out.push("  summary: " + s);
	out.push("  docs: " + (m.flags.includes("undocumented") ? "(none)" : docUrl(owner, name)));
	return { found: true, text: out.join("\n") };
}

function showClass(cls: string, showAll: boolean): string {
	const [, tags, summary] = api.classes[cls];
	const superclass = api.classes[cls][0];
	const out: string[] = [];
	out.push(`${cls}  superclass=${superclass}  tags=${tags || "-"}`);
	if (summary) out.push("  " + summary);
	if (tags.includes("undocumented")) out.push("  " + UNDOCUMENTED_NOTE);
	const chain = [cls];
	while (showAll && api.classes[chain[chain.length - 1]] && api.classes[chain[chain.length - 1]][0]) {
		chain.push(api.classes[chain[chain.length - 1]][0]);
	}
	for (const owner of chain) {
		const ms = api.members[owner] ?? {};
		if (owner !== cls) out.push(`  -- inherited from ${owner}`);
		for (const name of Object.keys(ms).sort(pyCompare)) {
			const [kind, sig, read, write, , flags] = ms[name];
			const mark = flags.includes("deprecated") || flags.includes("superseded") ? " [DEPRECATED]" : "";
			const sec = read === "None" && write === "None" ? "" : ` [${read}/${write}]`;
			const po = flags.includes("plugin-only") ? " [plugin-only]" : "";
			const ns = flags.includes("notscriptable") ? " [NotScriptable]" : "";
			const ud = flags.includes("undocumented") && !tags.includes("undocumented") ? " [UNDOCUMENTED]" : "";
			out.push(`  ${kind.slice(0, 4).padEnd(4)} ${name}: ${sig}${sec}${po}${ns}${ud}${mark}`);
		}
	}
	out.push("  docs: " + (tags.includes("undocumented") ? "(none)" : docUrl(cls)));
	return out.join("\n");
}

// Python sorts str by code point; localeCompare would not.
function pyCompare(a: string, b: string): number {
	return a < b ? -1 : a > b ? 1 : 0;
}

function showEnum(parts: string[]): { found: boolean; text: string } {
	const name = parts[1];
	const items = api.enums[name];
	if (!items) return { found: false, text: notFound("Enum." + parts.slice(1).join(".")) };
	if (parts.length > 2) {
		const item = items[parts[2]];
		if (!item) {
			return { found: false, text: `Enum.${name} has no item '${parts[2]}'. Valid: ${Object.keys(items).join(", ")}` };
		}
		const out = [`Enum.${name}.${parts[2]} = ${item[0]}${item[1].includes("deprecated") ? " DEPRECATED" : ""}`];
		const d = api.deprecated[`Enum.${name}.${parts[2]}`];
		if (d && d[4]) out.push("  " + d[4]);
		return { found: true, text: out.join("\n") };
	}
	const s = api.summaries["Enum." + name];
	const out = [`Enum.${name}` + (s ? ` — ${s}` : "")];
	for (const [item, r] of Object.entries(items)) {
		out.push(`  ${item} = ${r[0]}${r[1].includes("deprecated") ? " [DEPRECATED]" : ""}`);
	}
	return { found: true, text: out.join("\n") };
}

/** api.py <query> [--all] */
export function lookup(query: string, includeInherited = false): { found: boolean; text: string } {
	const raw = query.trim().replace(/[()]+$/, "");
	const q = raw.replaceAll(":", ".");
	const parts = q.split(".");
	if (parts[0] === "Enum" && parts.length >= 2) return showEnum(parts);
	const candidates = [raw, q, parts.length === 2 ? q.replace(".", ":") : q];
	for (const cand of candidates) {
		const r = api.datatypes[cand];
		if (r) {
			const out = [`${cand}  (${r[1]} of ${r[0]})  ${r[2]}  flags: ${r[3] || "-"}`];
			if (api.summaries[cand]) out.push("  summary: " + api.summaries[cand]);
			return { found: true, text: out.join("\n") };
		}
	}
	if (parts.length === 1) {
		if (api.classes[parts[0]]) return { found: true, text: showClass(parts[0], includeInherited) };
		const dts = Object.entries(api.datatypes)
			.filter(([, r]) => r[0] === parts[0])
			.map(([k]) => k)
			.sort(pyCompare);
		if (dts.length) return { found: true, text: `${parts[0]} (datatype/library): ` + dts.join(", ") };
		return { found: false, text: notFound(q) };
	}
	const [cls, name] = parts;
	if (!api.classes[cls]) return { found: false, text: notFound(q) };
	return showMember(cls, name);
}

/** api.py --search <term> */
export function search(term: string, limit = 200): { found: boolean; text: string } {
	const t = term.toLowerCase();
	const hits: string[] = [];
	for (const c of Object.keys(api.classes)) if (c.toLowerCase().includes(t)) hits.push(c);
	for (const [c, ms] of Object.entries(api.members)) {
		for (const m of Object.keys(ms)) if (m.toLowerCase().includes(t)) hits.push(`${c}.${m}`);
	}
	for (const e of Object.keys(api.enums)) if (e.toLowerCase().includes(t)) hits.push(`Enum.${e}`);
	for (const k of Object.keys(api.datatypes)) if (k.toLowerCase().includes(t)) hits.push(k);
	const out = hits.slice(0, limit);
	if (hits.length > limit) out.push(`... ${hits.length - limit} more`);
	return { found: hits.length > 0, text: out.join("\n") || `no API names contain '${term}'` };
}

/** api.py --deprecated <Class|*> */
export function deprecatedOf(cls: string): { found: boolean; text: string } {
	const out: string[] = [];
	for (const [key, r] of Object.entries(api.deprecated)) {
		if (r[0] === cls || cls === "*") out.push(`${key}  ->  ${r[3] || "?"}   ${r[4]}`);
	}
	return { found: out.length > 0, text: out.join("\n") || `no deprecated members recorded for ${cls}` };
}
