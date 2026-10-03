// Site settings the admin can change without a redeploy. D1 values override the Worker's env vars; a short
// per-isolate cache keeps the hot MCP path to one D1 read per few seconds.
import type { Env } from "./env";
import { ensureSchema } from "./users";

export interface Settings {
	freeCallsPerWeek: number;
	callsPerMinute: number;
	/** Banner text for the site; empty = no banner. */
	announcement: string;
}

const KEYS = { freeCallsPerWeek: "free_calls_per_week", callsPerMinute: "calls_per_minute", announcement: "announcement" } as const;
const TTL = 10_000;
const cache = new WeakMap<D1Database, { at: number; value: Settings }>();

function positive(raw: string | undefined | null, fallback: number): number {
	const n = Number(raw);
	return Number.isSafeInteger(n) && n > 0 ? n : fallback;
}

export function envDefaults(env: Env): Settings {
	return {
		freeCallsPerWeek: positive(env.FREE_CALLS_PER_WEEK, 100),
		callsPerMinute: positive(env.CALLS_PER_MINUTE, 60),
		announcement: "",
	};
}

export async function getSettings(env: Env, now = Date.now()): Promise<Settings> {
	if (!env.DB) return envDefaults(env);
	const hit = cache.get(env.DB);
	if (hit && now - hit.at < TTL) return hit.value;
	await ensureSchema(env.DB);
	const rows = (await env.DB.prepare("SELECT key, value FROM settings").all<{ key: string; value: string }>()).results;
	const map = new Map(rows.map((r) => [r.key, r.value]));
	const base = envDefaults(env);
	const value: Settings = {
		freeCallsPerWeek: positive(map.get(KEYS.freeCallsPerWeek), base.freeCallsPerWeek),
		callsPerMinute: positive(map.get(KEYS.callsPerMinute), base.callsPerMinute),
		announcement: (map.get(KEYS.announcement) ?? "").slice(0, 300),
	};
	cache.set(env.DB, { at: now, value });
	return value;
}

export async function saveSettings(env: Env, next: Settings): Promise<void> {
	await ensureSchema(env.DB);
	await env.DB.batch(
		(Object.keys(KEYS) as (keyof Settings)[]).map((k) =>
			env.DB.prepare("INSERT INTO settings (key, value) VALUES (?1, ?2) ON CONFLICT(key) DO UPDATE SET value = excluded.value")
				.bind(KEYS[k], String(next[k])),
		),
	);
	cache.delete(env.DB);
}
