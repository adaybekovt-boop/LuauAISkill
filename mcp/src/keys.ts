import type { Env } from "./env";
import { randomToken, sha256 } from "./session";
import { ensureSchema } from "./users";

export interface ApiKey { id: string; label: string; created_at: number; expires_at: number; revoked_at: number | null }
export async function listKeys(env: Env, userId: string): Promise<ApiKey[]> {
	await ensureSchema(env.DB);
	return (await env.DB.prepare("SELECT id, label, created_at, expires_at, revoked_at FROM api_keys WHERE user_id = ?1 ORDER BY created_at DESC")
		.bind(userId).all<ApiKey>()).results;
}

export async function createKey(env: Env, userId: string, label: string): Promise<string | null> {
	await ensureSchema(env.DB);
	const token = `la_sk_${randomToken()}`;
	const now = Date.now();
	const result = await env.DB.prepare(`INSERT INTO api_keys (id, user_id, token_hash, label, created_at, expires_at)
		SELECT ?1, ?2, ?3, ?4, ?5, ?6 WHERE
		(SELECT count(*) FROM api_keys WHERE user_id = ?2 AND revoked_at IS NULL AND expires_at > ?5) < 5`)
		.bind(crypto.randomUUID(), userId, await sha256(token), label.slice(0, 80) || "MCP client", now, now + 90 * 86400000).run();
	return result.meta.changes ? token : null;
}

export async function revokeKey(env: Env, userId: string, id: string): Promise<void> {
	await env.DB.prepare("UPDATE api_keys SET revoked_at = ?3 WHERE id = ?1 AND user_id = ?2").bind(id, userId, Date.now()).run();
}

export async function keyUser(env: Env, token: string): Promise<string | null> {
	if (!/^la_sk_[A-Za-z0-9_-]{43}$/.test(token)) return null;
	await ensureSchema(env.DB);
	const row = await env.DB.prepare("SELECT user_id FROM api_keys WHERE token_hash = ?1 AND revoked_at IS NULL AND expires_at > ?2")
		.bind(await sha256(token), Date.now()).first<{user_id: string}>();
	return row?.user_id ?? null;
}
