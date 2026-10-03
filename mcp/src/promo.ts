// Promo codes: each grants a complimentary subscription for N days (0 = forever). A code is open to everyone or to
// a list of emails, with optional activation cap and expiry. Redemption is one row per (code, user): the row is
// inserted first, then the cap-checked increment runs as a single conditional UPDATE, so neither a double submit
// nor parallel users can overspend a code.
import type { Env } from "./env";
import { COMP_FOREVER, ensureSchema, getUser } from "./users";

export interface PromoCode {
	code: string;
	grant_days: number;
	max_uses: number | null;
	uses: number;
	allowed_emails: string | null;
	expires_at: number | null;
	active: number;
	note: string | null;
	created_at: number;
}

const DAY = 86_400_000;
const CODE_RE = /^[A-Z0-9][A-Z0-9_-]{2,31}$/;

export function normalizeCode(raw: unknown): string | null {
	const code = String(raw ?? "").trim().toUpperCase();
	return CODE_RE.test(code) ? code : null;
}

export function generateCode(): string {
	const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no 0/O/1/I
	const bytes = crypto.getRandomValues(new Uint8Array(8));
	const chars = [...bytes].map((b) => alphabet[b % alphabet.length]).join("");
	return `LUAU-${chars.slice(0, 4)}-${chars.slice(4)}`;
}

export function parseEmails(raw: unknown): string[] {
	return [...new Set(String(raw ?? "").split(/[\s,;]+/).map((e) => e.trim().toLowerCase()).filter((e) => /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(e)))].slice(0, 500);
}

export interface NewPromo {
	code: string;
	grantDays: number;
	maxUses: number | null;
	emails: string[];
	expiresAt: number | null;
	note: string;
}

export async function createPromo(env: Env, p: NewPromo): Promise<boolean> {
	await ensureSchema(env.DB);
	const r = await env.DB.prepare(
		`INSERT INTO promo_codes (code, grant_days, max_uses, allowed_emails, expires_at, note, created_at)
		 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7) ON CONFLICT(code) DO NOTHING`,
	)
		.bind(p.code, p.grantDays, p.maxUses, p.emails.length ? p.emails.join("\n") : null, p.expiresAt, p.note.slice(0, 200) || null, Date.now())
		.run();
	return Boolean(r.meta.changes);
}

export async function listPromos(env: Env): Promise<PromoCode[]> {
	await ensureSchema(env.DB);
	return (await env.DB.prepare("SELECT * FROM promo_codes ORDER BY created_at DESC LIMIT 200").all<PromoCode>()).results;
}

export async function setPromoActive(env: Env, code: string, active: boolean): Promise<void> {
	await env.DB.prepare("UPDATE promo_codes SET active = ?2 WHERE code = ?1").bind(code, active ? 1 : 0).run();
}

/** Deleting a code keeps the subscriptions it already granted. */
export async function deletePromo(env: Env, code: string): Promise<void> {
	await env.DB.batch([
		env.DB.prepare("DELETE FROM promo_redemptions WHERE code = ?1").bind(code),
		env.DB.prepare("DELETE FROM promo_codes WHERE code = ?1").bind(code),
	]);
}

export type RedeemResult =
	| { ok: true; grantDays: number; compUntil: number }
	| { ok: false; reason: "invalid" | "not_allowed" | "used_up" | "already_redeemed" | "expired" };

/** Extends (never shortens) the complimentary period: forever stays forever. */
export async function grantComplimentary(env: Env, userId: string, days: number, now = Date.now()): Promise<number> {
	const row = await env.DB.prepare(
		`UPDATE users SET comp_until = CASE
			WHEN ?2 = 0 THEN ?4
			WHEN comp_until IS NOT NULL AND comp_until >= ?4 THEN comp_until
			ELSE max(coalesce(comp_until, 0), ?3) + ?2 * ?5 END
		 WHERE id = ?1 RETURNING comp_until`,
	)
		.bind(userId, days, now, COMP_FOREVER, DAY)
		.first<{ comp_until: number }>();
	return row?.comp_until ?? 0;
}

export async function redeemPromo(env: Env, userId: string, rawCode: unknown, now = Date.now()): Promise<RedeemResult> {
	await ensureSchema(env.DB);
	const code = normalizeCode(rawCode);
	const user = await getUser(env, userId);
	if (!code || !user) return { ok: false, reason: "invalid" };
	const promo = await env.DB.prepare("SELECT * FROM promo_codes WHERE code = ?1").bind(code).first<PromoCode>();
	if (!promo || !promo.active) return { ok: false, reason: "invalid" };
	if (promo.expires_at !== null && promo.expires_at <= now) return { ok: false, reason: "expired" };
	if (promo.allowed_emails && !promo.allowed_emails.split("\n").includes(user.email.toLowerCase())) {
		return { ok: false, reason: "not_allowed" };
	}

	const claimed = await env.DB.prepare(
		"INSERT INTO promo_redemptions (code, user_id, redeemed_at) VALUES (?1, ?2, ?3) ON CONFLICT DO NOTHING",
	)
		.bind(code, userId, now)
		.run();
	if (!claimed.meta.changes) return { ok: false, reason: "already_redeemed" };

	const counted = await env.DB.prepare(
		`UPDATE promo_codes SET uses = uses + 1 WHERE code = ?1 AND active = 1
		 AND (max_uses IS NULL OR uses < max_uses) AND (expires_at IS NULL OR expires_at > ?2)`,
	)
		.bind(code, now)
		.run();
	if (!counted.meta.changes) {
		await env.DB.prepare("DELETE FROM promo_redemptions WHERE code = ?1 AND user_id = ?2").bind(code, userId).run();
		return { ok: false, reason: "used_up" };
	}
	const compUntil = await grantComplimentary(env, userId, promo.grant_days, now);
	return { ok: true, grantDays: promo.grant_days, compUntil };
}
