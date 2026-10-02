// Read-only access to the skill's Markdown (SKILL.md, tracks, handbook, recipes, references).
import { docs } from "./generated/data.js";
import { sections } from "./search";

const byPath = new Map(docs.map((d) => [d.path, d.text]));

export function normalizePath(path: string): string {
	return path.trim().replace(/^\.?\/+/, "").replace(/^\$SKILL\//, "").replace(/\\/g, "/");
}

export function listDocs(prefix = ""): string {
	const p = normalizePath(prefix);
	const rows = docs
		.filter((d) => d.path.startsWith(p))
		.map((d) => {
			const title = /^#\s+(.*)$/m.exec(d.text)?.[1] ?? "";
			return `${d.path}  (${Math.ceil(d.text.length / 4)} tok≈)  ${title}`;
		});
	return rows.length ? rows.join("\n") : `no skill documents under '${p}'`;
}

export const MAX_CHARS = 60_000;

/**
 * Returns a document, or one heading's section of it (case-insensitive substring match on the heading path).
 * Long documents are paged by character offset so a client never receives an unbounded blob.
 */
export function readDoc(path: string, heading?: string, offset = 0): { found: boolean; text: string } {
	const p = normalizePath(path);
	const text = byPath.get(p);
	if (text === undefined) {
		const near = docs
			.map((d) => d.path)
			.filter((q) => q.endsWith(p.split("/").pop() ?? p) || q.includes(p))
			.slice(0, 8);
		return {
			found: false,
			text: `NOT FOUND: ${p}.` + (near.length ? ` Did you mean: ${near.join(", ")}?` : " Use list_skill_docs."),
		};
	}
	let body = text;
	if (heading) {
		const want = heading.toLowerCase();
		const secs = sections(p, text).filter((s) => s.heading.toLowerCase().includes(want));
		if (!secs.length) {
			const heads = sections(p, text).map((s) => s.heading);
			return { found: false, text: `No heading matching '${heading}' in ${p}. Headings:\n- ` + heads.join("\n- ") };
		}
		body = secs.map((s) => `## ${s.heading}  (${p}:${s.line})\n${s.body}`).join("\n\n");
	}
	const start = Math.max(0, offset);
	const chunk = body.slice(start, start + MAX_CHARS);
	const rest = body.length - (start + chunk.length);
	return {
		found: true,
		text: chunk + (rest > 0 ? `\n\n[… ${rest} more characters; call again with offset=${start + chunk.length}]` : ""),
	};
}
