// Legacy/deprecated pattern scan over submitted Luau source — a port of tools/scan_legacy.py (read-only; findings
// are review candidates, not proof). Same rules: curated catalog regexes, then one generic rule per deprecated row of
// the API index; a line explained by a curated rule reports only the curated finding (generic names kept as metadata).
import { api, catalog } from "./generated/data.js";
import type { DeprecatedRow } from "./types";

export interface Finding {
	file: string;
	line: number;
	rule: string;
	code: string;
	suggest: string;
	api_candidates: string[];
}

interface Rule {
	id: string;
	rx: RegExp;
	fix: string;
}

interface GenericRule extends Rule {
	/** Literal that must occur in the line for the regex to match; its last segment keys the token index. */
	needle: string;
}

// The catalog is authored for Python's `re`; the only construct JS lacks is a leading inline `(?i)`.
function compile(pattern: string): RegExp {
	if (pattern.startsWith("(?i)")) return new RegExp(pattern.slice(4), "i");
	return new RegExp(pattern);
}

function escapeRegExp(s: string): string {
	return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

// tools/rank_legacy.py identifier()
function identifier([owner, memberName, kind]: DeprecatedRow): string {
	if (kind === "global" || kind === "datatype" || kind === "library") return memberName.replaceAll(":", ".");
	return `${owner}.${memberName}`.replace(/\.+$/, "");
}

// tools/classify_legacy.py generic_rule(): one lexical candidate per pinned deprecated row, including names shared by
// several classes — the receiver type is never proven.
function genericRule(row: DeprecatedRow): GenericRule {
	const [, , kind, preferred, message] = row;
	const name = identifier(row);
	let pattern: string;
	let needle: string;
	if (kind === "class") {
		needle = name;
		pattern = String.raw`\bInstance\s*\.\s*new\s*\(\s*["']` + escapeRegExp(name) + `["']`;
	} else if (kind === "global" || kind === "library" || kind === "EnumItem") {
		needle = name;
		pattern = String.raw`(?<![\w.:])` + escapeRegExp(name) + String.raw`\b`;
	} else {
		needle = name.split(".").pop() ?? name;
		const m = escapeRegExp(needle);
		pattern = String.raw`(?:[.:]\s*` + m + String.raw`\b|\[\s*["']` + m + String.raw`["']\s*\])`;
	}
	const hint =
		message || (preferred ? "Pinned preferred member: " + preferred : "No replacement established by the pinned deprecation row.");
	return {
		id: "api-deprecated:" + name,
		rx: new RegExp(pattern),
		fix: `${name}: ${hint} Verify receiver class and migration semantics; lexical review candidate only.`,
		needle,
	};
}

const curated: Rule[] = catalog.map((e) => ({ id: e.id, rx: compile(e.detect), fix: e.new }));
const generic: GenericRule[] = api.deprecatedRows.map(genericRule);

// Every generic pattern requires its needle's last identifier segment to appear as a whole token (it is bounded by
// quotes, `.`/`:`, `\b` or the lookbehind), so indexing rules by that token never drops a match.
// Names that aren't plain identifiers (the dump has e.g. `Studio.UI Theme`) are checked on every line instead.
const IDENT = /[A-Za-z_][A-Za-z0-9_]*/g;
const byToken = new Map<string, number[]>();
const alwaysCheck: number[] = [];
generic.forEach((r, index) => {
	const key = r.needle.split(".").pop() ?? r.needle;
	if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(key)) {
		alwaysCheck.push(index);
		return;
	}
	const list = byToken.get(key);
	if (list) list.push(index);
	else byToken.set(key, [index]);
});

function genericHits(line: string): GenericRule[] {
	const picked = new Set<number>(alwaysCheck.filter((index) => line.includes(generic[index].needle)));
	for (const [token] of line.matchAll(IDENT)) {
		for (const index of byToken.get(token) ?? []) picked.add(index);
	}
	return [...picked]
		.sort((a, b) => a - b)
		.map((index) => generic[index])
		.filter((r) => r.rx.test(line));
}

export function scan(code: string, file = "input.luau", useApi = true): Finding[] {
	const findings: Finding[] = [];
	code.split(/\r\n|\r|\n/).forEach((line, i) => {
		if (line.trimStart().startsWith("--")) return;
		const curatedHits = curated.filter((r) => r.rx.test(line));
		const apiHits = useApi ? genericHits(line) : [];
		const candidates = apiHits.map((r) => r.id.slice("api-deprecated:".length));
		// One explanation family per line (curated wins); every generic candidate stays as metadata.
		const hits = curatedHits.length ? curatedHits : apiHits;
		for (const h of hits) {
			findings.push({
				file,
				line: i + 1,
				rule: h.id,
				code: line.trim().slice(0, 160),
				suggest: h.fix,
				api_candidates: candidates,
			});
		}
	});
	return findings;
}

export function formatFindings(findings: Finding[]): string {
	const out = findings.map((f) => `${f.file}:${f.line}: [${f.rule}] ${f.code}\n    → ${f.suggest}`);
	out.push(`${findings.length} candidate(s). Review each; see references/legacy-modernization/CATALOG.md`);
	return out.join("\n");
}
