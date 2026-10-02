// Users and access policy (D1). The table is created on first use, so a fresh database needs no migration step.
import type { Env } from "./env";

export interface User {
	id: string;
	email: string;
	name: string | null;
	created_at: number;
	last_login_at: number;
	subscription_status: string;
	subscription_period_end: number | null;
	disabled: number;
}

const SCHEMA = [
	`CREATE TABLE IF NOT EXISTS users (
		id TEXT PRIMARY KEY,
		email TEXT NOT NULL,
		name TEXT,
		created_at INTEGER NOT NULL,
		last_login_at INTEGER NOT NULL,
		subscription_status TEXT NOT NULL DEFAULT 'none',
		subscription_period_end INTEGER,
		disabled INTEGER NOT NULL DEFAULT 0
	)`,
	"CREATE INDEX IF NOT EXISTS users_email ON users (email)",
];

const ready = new WeakMap<D1Database, Promise<void>>();

function ensureSchema(db: D1Database): Promise<void> {
	let p = ready.get(db);
	if (!p) {
		p = (async () => {
			for (const sql of SCHEMA) await db.prepare(sql).run();
		})();
		p.catch(() => ready.delete(db));
		ready.set(db, p);
	}
	return p;
}

export async function upsertGoogleUser(env: Env, sub: string, email: string, name: string | null): Promise<User> {
	await ensureSchema(env.DB);
	const id = `google_${sub}`; // OAuth grant keys forbid ":" in user ids
	const now = Date.now();
	await env.DB.prepare(
		`INSERT INTO users (id, email, name, created_at, last_login_at) VALUES (?1, ?2, ?3, ?4, ?4)
		 ON CONFLICT(id) DO UPDATE SET email = excluded.email, name = excluded.name, last_login_at = excluded.last_login_at`,
	)
		.bind(id, email, name, now)
		.run();
	return (await getUser(env, id))!;
}

export async function getUser(env: Env, id: string): Promise<User | null> {
	await ensureSchema(env.DB);
	return (await env.DB.prepare("SELECT * FROM users WHERE id = ?1").bind(id).first<User>()) ?? null;
}

export async function setSubscriptionByEmail(
	env: Env,
	email: string,
	status: string,
	periodEnd: number | null,
): Promise<number> {
	await ensureSchema(env.DB);
	const r = await env.DB.prepare(
		"UPDATE users SET subscription_status = ?2, subscription_period_end = ?3 WHERE lower(email) = lower(?1)",
	)
		.bind(email, status, periodEnd)
		.run();
	return r.meta.changes ?? 0;
}

export function policy(env: Env): "registered" | "subscribed" {
	return env.ACCESS_POLICY === "subscribed" ? "subscribed" : "registered";
}

export function hasActiveSubscription(user: User, now = Date.now()): boolean {
	return (
		user.subscription_status === "active" && (user.subscription_period_end === null || user.subscription_period_end > now)
	);
}

export type Access = { ok: true; user: User } | { ok: false; reason: "unknown_user" | "disabled" | "subscription_required" };

/** Checked at authorization time AND on every MCP request, so a cancelled subscription stops access immediately. */
export async function checkAccess(env: Env, userId: string): Promise<Access> {
	const user = await getUser(env, userId);
	if (!user) return { ok: false, reason: "unknown_user" };
	if (user.disabled) return { ok: false, reason: "disabled" };
	if (policy(env) === "subscribed" && !hasActiveSubscription(user)) return { ok: false, reason: "subscription_required" };
	return { ok: true, user };
}
