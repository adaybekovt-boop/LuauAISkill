// Shapes of the data produced by scripts/build-data.mjs (compact arrays keep the bundle small).

/** [superclass, tags, summary] */
export type ClassRow = [string, string, string];
/** [kind, type_or_signature, read, write, thread, flags] */
export type MemberRow = [string, string, string, string, string, string];
/** [value, flags] */
export type EnumItemRow = [string, string];
/** [owner, kind, signature, flags] */
export type DatatypeRow = [string, string, string, string];
/** [owner, member, kind, preferred, message] */
export type DeprecatedRow = [string, string, string, string, string];

export interface ApiData {
	classes: Record<string, ClassRow>;
	members: Record<string, Record<string, MemberRow>>;
	enums: Record<string, Record<string, EnumItemRow>>;
	datatypes: Record<string, DatatypeRow>;
	deprecated: Record<string, DeprecatedRow>;
	deprecatedRows: DeprecatedRow[];
	summaries: Record<string, string>;
}

export interface CatalogRule {
	id: string;
	detect: string;
	old: string;
	new: string;
	status: string;
	why: string;
}

export interface Doc {
	path: string;
	text: string;
}

export interface Meta {
	skillVersion: string;
	commit: string;
	builtAt: string;
	apiClientVersion: string;
	docsCommit: string;
	counts: Record<string, number>;
}
