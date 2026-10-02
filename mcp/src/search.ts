// Ranked keyword search over the skill's Markdown — the Worker equivalent of tools/search.py (SQLite FTS5 + BM25).
// Same units (a heading + its text), same weights (heading 4, body 1), AND first then OR fallback. Tokenizing
// approximates FTS5 `porter unicode61`, so ranks can differ slightly from the CLI; contents are identical.
import { docs } from "./generated/data.js";

export interface Section {
	path: string;
	line: number;
	heading: string;
	body: string;
}

interface Indexed extends Section {
	head: Map<string, number>;
	text: Map<string, number>;
	headLen: number;
	textLen: number;
}

const HEADING = /^(#{1,4})\s+(.*)/;

export function sections(path: string, text: string): Section[] {
	const out: Section[] = [];
	const title = path.split("/").pop()!.replace(/\.md$/, "");
	let stack: string[] = [];
	let start = 1;
	let buf: string[] = [];
	text.split("\n").forEach((line, i) => {
		const m = HEADING.exec(line);
		if (m) {
			if (buf.length) out.push({ path, line: start, heading: stack.join(" › ") || title, body: buf.join("\n") });
			const level = m[1].length;
			stack = [...stack.slice(0, level - 1), m[2].trim()];
			start = i + 1;
			buf = [];
		} else {
			buf.push(line);
		}
	});
	if (buf.length) out.push({ path, line: start, heading: stack.join(" › ") || title, body: buf.join("\n") });
	return out;
}

// Small Porter-style suffix stripping: enough to make "locking"/"locks"/"locked" meet "lock".
export function stem(word: string): string {
	let w = word;
	if (w.length <= 3) return w;
	if (w.endsWith("sses")) w = w.slice(0, -2);
	else if (w.endsWith("ies")) w = w.slice(0, -3) + "i";
	else if (w.endsWith("s") && !w.endsWith("ss") && !w.endsWith("us")) w = w.slice(0, -1);
	for (const suf of ["ingly", "edly", "ing", "ed"]) {
		if (w.endsWith(suf) && w.length - suf.length >= 3 && /[aeiouy]/.test(w.slice(0, -suf.length))) {
			w = w.slice(0, -suf.length);
			if (/(at|bl|iz)$/.test(w)) w += "e";
			else if (/([^aeiouylsz])\1$/.test(w)) w = w.slice(0, -1);
			break;
		}
	}
	if (w.endsWith("y") && w.length > 3 && /[aeiou]/.test(w.slice(0, -1))) w = w.slice(0, -1) + "i";
	return w;
}

export function tokens(text: string): string[] {
	return (text.toLowerCase().match(/[\p{L}\p{N}_]+/gu) ?? []).map(stem);
}

function counts(words: string[]): Map<string, number> {
	const m = new Map<string, number>();
	for (const w of words) m.set(w, (m.get(w) ?? 0) + 1);
	return m;
}

let index: { rows: Indexed[]; avgHead: number; avgText: number; dfHead: Map<string, number>; dfText: Map<string, number> } | null =
	null;

function build() {
	if (index) return index;
	const rows: Indexed[] = [];
	for (const d of docs) {
		for (const s of sections(d.path, d.text)) {
			const h = tokens(s.heading);
			const b = tokens(s.body);
			rows.push({ ...s, head: counts(h), text: counts(b), headLen: h.length, textLen: b.length });
		}
	}
	const dfHead = new Map<string, number>();
	const dfText = new Map<string, number>();
	for (const r of rows) {
		for (const t of r.head.keys()) dfHead.set(t, (dfHead.get(t) ?? 0) + 1);
		for (const t of r.text.keys()) dfText.set(t, (dfText.get(t) ?? 0) + 1);
	}
	const avgHead = rows.reduce((a, r) => a + r.headLen, 0) / Math.max(rows.length, 1);
	const avgText = rows.reduce((a, r) => a + r.textLen, 0) / Math.max(rows.length, 1);
	index = { rows, avgHead, avgText, dfHead, dfText };
	return index;
}

// Built at isolate startup (global scope) rather than inside the first request, which on Workers is CPU-limited.
build();

function bm25(tf: number, df: number, len: number, avg: number, n: number): number {
	if (!tf) return 0;
	const idf = Math.log(1 + (n - df + 0.5) / (df + 0.5));
	const k1 = 1.2;
	const b = 0.75;
	return (idf * (tf * (k1 + 1))) / (tf + k1 * (1 - b + (b * len) / Math.max(avg, 1)));
}

function snippet(body: string, terms: Set<string>, width = 18): string {
	const words = body.split(/\s+/).filter(Boolean);
	const hit = words.findIndex((w) => tokens(w).some((t) => terms.has(t)));
	const from = Math.max(0, (hit < 0 ? 0 : hit) - Math.floor(width / 2));
	const part = words
		.slice(from, from + width)
		.map((w) => (tokens(w).some((t) => terms.has(t)) ? `[${w}]` : w))
		.join(" ");
	return (from > 0 ? "… " : "") + part + (from + width < words.length ? " …" : "");
}

export interface Hit {
	path: string;
	line: number;
	heading: string;
	snippet: string;
	score: number;
}

export function searchSkill(query: string, limit = 8): Hit[] {
	const idx = build();
	const qTokens = [...new Set(tokens(query))];
	if (!qTokens.length) return [];
	const n = idx.rows.length;
	const score = (r: Indexed) =>
		qTokens.reduce(
			(acc, t) =>
				acc +
				4.0 * bm25(r.head.get(t) ?? 0, idx.dfHead.get(t) ?? 0, r.headLen, idx.avgHead, n) +
				1.0 * bm25(r.text.get(t) ?? 0, idx.dfText.get(t) ?? 0, r.textLen, idx.avgText, n),
			0,
		);
	const has = (r: Indexed, t: string) => r.head.has(t) || r.text.has(t);
	let matched = idx.rows.filter((r) => qTokens.every((t) => has(r, t)));
	if (!matched.length) matched = idx.rows.filter((r) => qTokens.some((t) => has(r, t)));
	const terms = new Set(qTokens);
	return matched
		.map((r) => ({ r, s: score(r) }))
		.sort((a, b) => b.s - a.s)
		.slice(0, limit)
		.map(({ r, s }) => ({ path: r.path, line: r.line, heading: r.heading, snippet: snippet(r.body, terms), score: s }));
}

export function formatHits(hits: Hit[]): string {
	if (!hits.length) return "no results (try other words; this is keyword search)";
	return hits.map((h) => `${h.path}:${h.line}  ${h.heading}\n    ${h.snippet}`).join("\n");
}
