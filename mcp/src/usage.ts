import type { Env } from "./env";
import { getSettings } from "./settings";
import { ensureSchema, hasActiveSubscription, type User } from "./users";

const WEEK = 7 * 24 * 3600 * 1000;
export function weekStart(now = Date.now()): number {
	// Unix epoch was Thursday; weekly allowances reset Monday at 00:00 UTC.
	return Math.floor((now - 4 * 86400000) / WEEK) * WEEK + 4 * 86400000;
}

/** Limits come from admin settings (D1) with the Worker's env vars as defaults. */
export const freeLimit = async (env: Env) => (await getSettings(env)).freeCallsPerWeek;
export const minuteLimit = async (env: Env) => (await getSettings(env)).callsPerMinute;

export interface UsageRow { week: number; week_calls: number; minute: number; minute_calls: number }
export async function usageInfo(env: Env, user: User, now = Date.now()) {
	await ensureSchema(env.DB);
	const row = await env.DB.prepare("SELECT * FROM usage WHERE user_id = ?1").bind(user.id).first<UsageRow>();
	return {
		used: row?.week === weekStart(now) ? row.week_calls : 0,
		limit: hasActiveSubscription(user, now) ? null : await freeLimit(env),
		resets_at: weekStart(now) + WEEK,
		calls_per_minute: await minuteLimit(env),
	};
}

export type Reservation = { ok: true; week: number; minute: number } | { ok: false; retryAfter: number; reason: string };

/** One atomic conditional upsert: parallel requests and different isolates cannot overspend an allowance. */
export async function reserveCall(env: Env, user: User, now = Date.now()): Promise<Reservation> {
	await ensureSchema(env.DB);
	const week = weekStart(now);
	const minute = Math.floor(now / 60000);
	const paid = hasActiveSubscription(user, now) ? 1 : 0;
	const [perWeek, perMinute] = [await freeLimit(env), await minuteLimit(env)];
	const row = await env.DB.prepare(`INSERT INTO usage (user_id, week, week_calls, minute, minute_calls)
		VALUES (?1, ?2, 1, ?3, 1)
		ON CONFLICT(user_id) DO UPDATE SET
		week = excluded.week,
		week_calls = CASE WHEN usage.week = excluded.week THEN usage.week_calls + 1 ELSE 1 END,
		minute = excluded.minute,
		minute_calls = CASE WHEN usage.minute = excluded.minute THEN usage.minute_calls + 1 ELSE 1 END
		WHERE (usage.minute != excluded.minute OR usage.minute_calls < ?4)
		AND (?5 = 1 OR usage.week != excluded.week OR usage.week_calls < ?6)
		RETURNING week, minute`).bind(user.id, week, minute, perMinute, paid, perWeek).first<{week: number; minute: number}>();
	if (row) return { ok: true, ...row };
	const info = await usageInfo(env, user, now);
	const weekly = !paid && info.used >= perWeek;
	return { ok: false, retryAfter: Math.max(1, Math.ceil(((weekly ? week + WEEK : (minute + 1) * 60000) - now) / 1000)),
		reason: weekly ? "Weekly free allowance reached. Subscribe at /account or wait for Monday 00:00 UTC." : "Too many calls. Please retry shortly." };
}

/** Failed validation, missing documents, and failed execution don't consume a successful-read allowance. */
export async function refundCall(env: Env, userId: string, reservation: {week: number; minute: number}): Promise<void> {
	await env.DB.prepare(`UPDATE usage SET
		week_calls = CASE WHEN week = ?2 THEN max(0, week_calls - 1) ELSE week_calls END,
		minute_calls = CASE WHEN minute = ?3 THEN max(0, minute_calls - 1) ELSE minute_calls END
		WHERE user_id = ?1`).bind(userId, reservation.week, reservation.minute).run();
}
