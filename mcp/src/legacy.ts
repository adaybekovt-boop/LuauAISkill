// Legacy/deprecated pattern scan over submitted Luau source — a port of tools/scan_legacy.py (read-only; findings
// are review candidates, not proof). Same rules: curated catalog regexes first, then unambiguous deprecated member
// names from the API index; a line explained by a curated rule doesn't also get the generic hit.
import { api, catalog } from "./generated/data.js";

export interface Finding {
	file: string;
	line: number;
	rule: string;
	code: string;
	suggest: string;
}

interface Rule {
	id: string;
	rx: RegExp;
	fix: string;
}

interface ApiRule {
	id: string;
	sep: string;
	fix: string;
	order: number;
}

// The catalog is authored for Python's `re`; the only construct JS lacks is a leading inline `(?i)`.
function compile(pattern: string): RegExp {
	if (pattern.startsWith("(?i)")) return new RegExp(pattern.slice(4), "i");
	return new RegExp(pattern);
}

function escapeRegExp(s: string): string {
	return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

const curated: Rule[] = catalog.map((e) => ({ id: e.id, rx: compile(e.detect), fix: e.new }));

// Deprecated member names that don't collide with non-deprecated members of other classes (first class wins, as in
// the Python tool). All of them are matched by ONE alternation regex so a scan stays cheap on a Worker's CPU budget.
const apiRules = new Map<string, ApiRule>();
{
	const live = new Set<string>();
	const dead = new Map<string, { cls: string; kind: string; flags: string }>();
	for (const [cls, ms] of Object.entries(api.members)) {
		for (const [name, row] of Object.entries(ms)) {
			const flags = row[5];
			if (flags.includes("deprecated")) {
				if (!dead.has(name)) dead.set(name, { cls, kind: row[0], flags });
			} else {
				live.add(name);
			}
		}
	}
	let order = 0;
	for (const [name, r] of dead) {
		if (live.has(name) || name.length < 6 || name[0] !== name[0].toUpperCase() || name[0] === name[0].toLowerCase()) {
			continue;
		}
		const pref =
			r.flags
				.split(",")
				.find((f) => f.startsWith("prefer="))
				?.slice(7) ?? "see api/deprecated.tsv";
		apiRules.set(name, { id: `api-deprecated:${r.cls}.${name}`, sep: r.kind === "Function" ? ":" : ".", fix: pref, order: order++ });
	}
}
const apiPattern = new RegExp(`([:.])(${[...apiRules.keys()].map(escapeRegExp).join("|")})\\b`, "g");

function apiHits(line: string): { id: string; fix: string }[] {
	const found = new Map<string, ApiRule>();
	for (const m of line.matchAll(apiPattern)) {
		const rule = apiRules.get(m[2]);
		if (rule && rule.sep === m[1]) found.set(rule.id, rule);
	}
	return [...found.values()].sort((a, b) => a.order - b.order).map((r) => ({ id: r.id, fix: r.fix }));
}

export function scan(code: string, file = "input.luau", useApi = true): Finding[] {
	const findings: Finding[] = [];
	const lines = code.split(/\r\n|\r|\n/);
	lines.forEach((line, i) => {
		const trimmed = line.trimStart();
		if (!trimmed || trimmed.startsWith("--")) return;
		let hits = curated.filter((r) => r.rx.test(line)).map((r) => ({ id: r.id, fix: r.fix }));
		// A curated rule already explains the line; the generic API-deprecation hit would repeat it.
		if (useApi && !hits.length) hits = apiHits(line);
		for (const h of hits) {
			findings.push({ file, line: i + 1, rule: h.id, code: line.trim().slice(0, 160), suggest: h.fix });
		}
	});
	return findings;
}

export function formatFindings(findings: Finding[]): string {
	const out = findings.map((f) => `${f.file}:${f.line}: [${f.rule}] ${f.code}\n    → ${f.suggest}`);
	out.push(`${findings.length} candidate(s). Review each; see references/legacy-modernization/CATALOG.md`);
	return out.join("\n");
}
