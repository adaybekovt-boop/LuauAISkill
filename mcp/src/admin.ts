// Admin panel at /admin: Google sign-in like /account, allowed only for emails in ADMIN_EMAILS. Server-rendered forms
// (no scripts, CSP stays strict), CSRF-checked POSTs, every change written to admin_log. Non-admins get a 404.
import type { Env } from "./env";
import { escape, page } from "./pages";
import {
	createPromo,
	deletePromo,
	generateCode,
	grantComplimentary,
	listPromos,
	normalizeCode,
	parseEmails,
	setPromoActive,
	type PromoCode,
} from "./promo";
import { csrfToken, getSession, validCsrf } from "./session";
import { getSettings, saveSettings } from "./settings";
import { weekStart } from "./usage";
import { COMP_FOREVER, ensureSchema, getUser, hasComplimentary, hasPaidSubscription, type User } from "./users";

const DAY = 86_400_000;

export function adminEmails(env: Env): string[] {
	return (env.ADMIN_EMAILS ?? "").split(",").map((e) => e.trim().toLowerCase()).filter(Boolean);
}

async function adminUser(env: Env, request: Request): Promise<User | null> {
	const session = await getSession(env, request);
	if (!session) return null;
	const user = await getUser(env, session.userId);
	if (!user || user.disabled || !adminEmails(env).includes(user.email.toLowerCase())) return null;
	return user;
}

function redirect(location: string): Response {
	return new Response(null, { status: 302, headers: { Location: location, "Cache-Control": "no-store" } });
}

function notFound(): Response {
	return new Response(JSON.stringify({ error: "not found" }), { status: 404, headers: { "Content-Type": "application/json" } });
}

async function log(env: Env, admin: User, action: string, detail: string): Promise<void> {
	await env.DB.prepare("INSERT INTO admin_log (at, admin_email, action, detail) VALUES (?1, ?2, ?3, ?4)")
		.bind(Date.now(), admin.email, action, detail.slice(0, 500))
		.run();
}

const date = (ms: number | null | undefined) => (ms ? new Date(ms).toISOString().slice(0, 10) : "—");
const dateTime = (ms: number) => new Date(ms).toISOString().slice(0, 16).replace("T", " ");

function planLabel(u: User, now = Date.now()): string {
	if (hasPaidSubscription(u, now)) return `Stripe · до ${date(u.subscription_period_end)}`;
	if (hasComplimentary(u, now)) return u.comp_until! >= COMP_FOREVER ? "Подарок · навсегда" : `Подарок · до ${date(u.comp_until)}`;
	return "Бесплатно";
}

function grantLabel(days: number): string {
	return days === 0 ? "навсегда" : `${days} дн.`;
}

/* ─────────────────────────── pages ─────────────────────────── */

const STYLE = `<style>
main{max-width:1080px}
.nav{display:flex;gap:6px;flex-wrap:wrap;align-items:center;margin-bottom:24px}.nav .me{margin-left:auto}
.tiles{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:12px;margin:16px 0 28px}
.tile{border:1px solid var(--line);border-radius:10px;padding:14px}.tile b{display:block;font-size:28px;line-height:1.1}
table{width:100%;border-collapse:collapse;font-size:14px}th,td{text-align:left;padding:8px 10px;border-bottom:1px solid var(--line);vertical-align:top}
th{color:var(--muted);font-weight:500}.scroll{overflow-x:auto}td form{margin:0;display:inline}
.grid2{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:12px 20px}
label{display:block;font-size:14px;color:var(--muted)}label input,label select,label textarea{display:block;width:100%;margin-top:4px;color:var(--fg)}
textarea{font:inherit;padding:10px;border:1px solid var(--line);border-radius:6px;background:var(--bg);min-height:90px}
.inline{display:flex;gap:8px;align-items:center;flex-wrap:wrap}.inline label{display:flex;gap:6px;align-items:center;color:var(--fg)}
.inline input[type=radio],.inline input[type=checkbox]{min-height:auto;width:auto}
.tag{display:inline-block;padding:2px 8px;border-radius:999px;border:1px solid var(--line);font-size:12px}
.on{border-color:#2a7}.off{color:var(--muted)}.danger{border-color:#c33;color:#c33}
code.big{font-size:15px;font-weight:600}
</style>`;

function layout(admin: User, title: string, body: string, csrf: string): Response {
	const nav = `<nav class="nav">
<a class="btn" href="/admin">Обзор</a><a class="btn" href="/admin/users">Пользователи</a>
<a class="btn" href="/admin#promo">Промокоды</a><a class="btn" href="/admin#settings">Настройки</a>
<span class="me muted">${escape(admin.email)}</span>
<form method="post" action="/logout"><input type="hidden" name="csrf" value="${escape(csrf)}"><button class="btn">Выйти</button></form>
</nav>`;
	return page(`${title} · LuauAISkill`, `${STYLE}${nav}${body}`, 200, undefined, "ru");
}

function csrfField(csrf: string): string {
	return `<input type="hidden" name="csrf" value="${escape(csrf)}">`;
}

function promoRows(promos: PromoCode[], csrf: string, now: number): string {
	if (!promos.length) return `<p class="muted">Промокодов пока нет.</p>`;
	return `<div class="scroll"><table><thead><tr><th>Код</th><th>Даёт</th><th>Кто</th><th>Активаций</th><th>До</th><th>Статус</th><th></th></tr></thead><tbody>
${promos
	.map((p) => {
		const emails = p.allowed_emails ? p.allowed_emails.split("\n") : [];
		const expired = p.expires_at !== null && p.expires_at <= now;
		const usedUp = p.max_uses !== null && p.uses >= p.max_uses;
		const status = !p.active ? `<span class="tag off">выключен</span>` : expired ? `<span class="tag off">истёк</span>` : usedUp ? `<span class="tag off">исчерпан</span>` : `<span class="tag on">активен</span>`;
		return `<tr><td><code class="big">${escape(p.code)}</code>${p.note ? `<br><span class="muted">${escape(p.note)}</span>` : ""}</td>
<td>${grantLabel(p.grant_days)}</td>
<td>${emails.length ? `${emails.length} email<br><span class="muted">${escape(emails.slice(0, 3).join(", "))}${emails.length > 3 ? "…" : ""}</span>` : "все"}</td>
<td>${p.uses}${p.max_uses !== null ? ` / ${p.max_uses}` : " / ∞"}</td><td>${date(p.expires_at)}</td><td>${status}</td>
<td><form method="post" action="/admin/promo/toggle">${csrfField(csrf)}<input type="hidden" name="code" value="${escape(p.code)}">
<button class="btn">${p.active ? "Выключить" : "Включить"}</button></form>
<form method="post" action="/admin/promo/delete">${csrfField(csrf)}<input type="hidden" name="code" value="${escape(p.code)}">
<button class="btn danger">Удалить</button></form></td></tr>`;
	})
	.join("")}
</tbody></table></div>`;
}

async function overview(env: Env, request: Request, admin: User, notice?: string): Promise<Response> {
	await ensureSchema(env.DB);
	const now = Date.now();
	const csrf = await csrfToken(env, request);
	const stats = await env.DB.prepare(
		`SELECT count(*) AS total,
		 sum(CASE WHEN created_at > ?1 THEN 1 ELSE 0 END) AS week_new,
		 sum(disabled) AS disabled,
		 sum(CASE WHEN (subscription_status IN ('active','trialing') AND (subscription_period_end IS NULL OR subscription_period_end > ?2))
		          OR comp_until > ?2 THEN 1 ELSE 0 END) AS subscribed
		 FROM users`,
	)
		.bind(now - 7 * DAY, now)
		.first<{ total: number; week_new: number | null; disabled: number | null; subscribed: number | null }>();
	const calls = await env.DB.prepare("SELECT coalesce(sum(week_calls), 0) AS n FROM usage WHERE week = ?1").bind(weekStart(now)).first<{ n: number }>();
	const promos = await listPromos(env);
	const settings = await getSettings(env);
	const recent = (await env.DB.prepare("SELECT * FROM admin_log ORDER BY id DESC LIMIT 30").all<{ at: number; admin_email: string; action: string; detail: string }>()).results;

	const body = `<h1>Админка</h1>
${notice ? `<p role="status" class="box">${escape(notice)}</p>` : ""}
<div class="tiles">
<div class="tile"><span class="muted">Пользователи</span><b>${stats?.total ?? 0}</b></div>
<div class="tile"><span class="muted">Новые за 7 дней</span><b>${stats?.week_new ?? 0}</b></div>
<div class="tile"><span class="muted">С подпиской</span><b>${stats?.subscribed ?? 0}</b></div>
<div class="tile"><span class="muted">Заблокированы</span><b>${stats?.disabled ?? 0}</b></div>
<div class="tile"><span class="muted">Вызовов за неделю</span><b>${calls?.n ?? 0}</b></div>
</div>

<h2 id="promo">Промокоды</h2>
<form method="post" action="/admin/promo/create" class="box">${csrfField(csrf)}
<div class="grid2">
<label>Код <input name="code" maxlength="32" placeholder="пусто — сгенерировать" pattern="[A-Za-z0-9][A-Za-z0-9_\\-]{2,31}"></label>
<label>Заметка <input name="note" maxlength="200" placeholder="для кого / зачем"></label>
</div>
<p style="margin-top:14px">Даёт подписку</p>
<div class="inline"><label><input type="radio" name="grant" value="days" checked> на</label>
<input name="days" type="number" min="1" max="3650" value="30" aria-label="Дней" style="width:110px"><span>дней</span>
<label><input type="radio" name="grant" value="forever"> навсегда</label></div>
<p style="margin-top:14px">Кто может активировать</p>
<div class="inline"><label><input type="radio" name="who" value="all" checked> все</label>
<label><input type="radio" name="who" value="emails"> только эти email</label></div>
<label style="margin-top:8px">Email (через запятую или с новой строки) <textarea name="emails" placeholder="friend@gmail.com"></textarea></label>
<div class="grid2" style="margin-top:8px">
<label>Лимит активаций <input name="max_uses" type="number" min="1" max="1000000" placeholder="пусто — без лимита"></label>
<label>Действует до <input name="expires" type="date"></label>
</div>
<div class="row"><button class="btn primary">Создать промокод</button></div>
</form>
${promoRows(promos, csrf, now)}

<h2 id="settings" style="margin-top:32px">Настройки сайта</h2>
<form method="post" action="/admin/settings" class="box">${csrfField(csrf)}
<div class="grid2">
<label>Бесплатных вызовов в неделю <input name="free_calls_per_week" type="number" min="1" max="1000000" value="${settings.freeCallsPerWeek}" required></label>
<label>Вызовов в минуту (все тарифы) <input name="calls_per_minute" type="number" min="1" max="10000" value="${settings.callsPerMinute}" required></label>
</div>
<label style="margin-top:12px">Объявление на сайте (пусто — без баннера) <input name="announcement" maxlength="300" value="${escape(settings.announcement)}"></label>
<div class="row"><button class="btn primary">Сохранить</button></div>
</form>

<h2 style="margin-top:32px">Журнал</h2>
${recent.length ? `<div class="scroll"><table><thead><tr><th>Когда (UTC)</th><th>Кто</th><th>Действие</th><th>Детали</th></tr></thead><tbody>
${recent.map((r) => `<tr><td>${dateTime(r.at)}</td><td>${escape(r.admin_email)}</td><td>${escape(r.action)}</td><td>${escape(r.detail)}</td></tr>`).join("")}
</tbody></table></div>` : `<p class="muted">Пока пусто.</p>`}`;
	return layout(admin, "Админка", body, csrf);
}

interface UserRow extends User {
	week_calls: number;
}

async function usersPage(env: Env, request: Request, admin: User): Promise<Response> {
	await ensureSchema(env.DB);
	const url = new URL(request.url);
	const q = (url.searchParams.get("q") ?? "").trim().toLowerCase().slice(0, 100);
	const pageNo = Math.max(0, Math.min(1000, Number(url.searchParams.get("page")) || 0));
	const csrf = await csrfToken(env, request);
	const rows = (
		await env.DB.prepare(
			`SELECT u.*, CASE WHEN g.week = ?1 THEN g.week_calls ELSE 0 END AS week_calls
			 FROM users u LEFT JOIN usage g ON g.user_id = u.id
			 WHERE ?2 = '' OR instr(lower(u.email), ?2) > 0 OR instr(lower(coalesce(u.name, '')), ?2) > 0
			 ORDER BY u.created_at DESC LIMIT 51 OFFSET ?3`,
		)
			.bind(weekStart(), q, pageNo * 50)
			.all<UserRow>()
	).results;
	const more = rows.length > 50;
	const list = rows.slice(0, 50);
	const qs = (p: number) => `/admin/users?${new URLSearchParams({ ...(q ? { q } : {}), page: String(p) })}`;
	const body = `<h1>Пользователи</h1>
<form method="get" action="/admin/users" class="inline"><input name="q" value="${escape(q)}" placeholder="email или имя" aria-label="Поиск">
<button class="btn">Найти</button>${q ? `<a class="btn" href="/admin/users">Сбросить</a>` : ""}</form>
${list.length ? `<div class="scroll"><table><thead><tr><th>Email</th><th>Тариф</th><th>Вызовы (нед.)</th><th>Регистрация</th><th>Вход</th><th></th></tr></thead><tbody>
${list
	.map(
		(u) => `<tr><td>${escape(u.email)}${u.name ? `<br><span class="muted">${escape(u.name)}</span>` : ""}${u.disabled ? ` <span class="tag danger">заблокирован</span>` : ""}</td>
<td>${planLabel(u)}</td><td>${u.week_calls}</td><td>${date(u.created_at)}</td><td>${date(u.last_login_at)}</td>
<td><a class="btn" href="/admin/user?id=${encodeURIComponent(u.id)}">Управлять</a></td></tr>`,
	)
	.join("")}
</tbody></table></div>` : `<p class="muted">Никого не найдено.</p>`}
<div class="row">${pageNo > 0 ? `<a class="btn" href="${qs(pageNo - 1)}">← Назад</a>` : ""}${more ? `<a class="btn" href="${qs(pageNo + 1)}">Дальше →</a>` : ""}</div>`;
	return layout(admin, "Пользователи", body, csrf);
}

async function userPage(env: Env, request: Request, admin: User, id: string, notice?: string): Promise<Response> {
	const user = await getUser(env, id);
	if (!user) return redirect("/admin/users");
	const csrf = await csrfToken(env, request);
	const now = Date.now();
	const usage = await env.DB.prepare("SELECT week, week_calls FROM usage WHERE user_id = ?1").bind(id).first<{ week: number; week_calls: number }>();
	const redemptions = (await env.DB.prepare("SELECT code, redeemed_at FROM promo_redemptions WHERE user_id = ?1 ORDER BY redeemed_at DESC").bind(id).all<{ code: string; redeemed_at: number }>()).results;
	const keys = await env.DB.prepare("SELECT count(*) AS n FROM api_keys WHERE user_id = ?1 AND revoked_at IS NULL AND expires_at > ?2").bind(id, now).first<{ n: number }>();
	const self = user.id === admin.id;
	const hidden = `${csrfField(csrf)}<input type="hidden" name="id" value="${escape(user.id)}">`;
	const body = `<p><a href="/admin/users">← Все пользователи</a></p>
<h1>${escape(user.email)}</h1>
${notice ? `<p role="status" class="box">${escape(notice)}</p>` : ""}
<div class="box"><dl>
<dt>Имя</dt><dd>${escape(user.name ?? "—")}</dd>
<dt>Тариф</dt><dd>${planLabel(user, now)}</dd>
<dt>Stripe</dt><dd>${escape(user.subscription_status)}${user.subscription_period_end ? ` · до ${date(user.subscription_period_end)}` : ""}</dd>
<dt>Вызовов за неделю</dt><dd>${usage?.week === weekStart(now) ? usage.week_calls : 0}</dd>
<dt>API-ключей</dt><dd>${keys?.n ?? 0}</dd>
<dt>Регистрация</dt><dd>${dateTime(user.created_at)} UTC</dd>
<dt>Последний вход</dt><dd>${dateTime(user.last_login_at)} UTC</dd>
<dt>Статус</dt><dd>${user.disabled ? `<span class="tag danger">заблокирован</span>` : "активен"}</dd>
<dt>Промокоды</dt><dd>${redemptions.length ? redemptions.map((r) => `${escape(r.code)} (${date(r.redeemed_at)})`).join(", ") : "—"}</dd>
</dl></div>

<h2>Подписка</h2>
<form method="post" action="/admin/user" class="box">${hidden}<input type="hidden" name="action" value="grant">
<div class="inline"><label><input type="radio" name="grant" value="days" checked> Выдать на</label>
<input name="days" type="number" min="1" max="3650" value="30" aria-label="Дней" style="width:110px"><span>дней</span>
<label><input type="radio" name="grant" value="forever"> навсегда</label>
<button class="btn primary">Выдать</button></div></form>
${hasComplimentary(user, now) ? `<form method="post" action="/admin/user">${hidden}<input type="hidden" name="action" value="revoke">
<button class="btn">Забрать подаренную подписку</button></form>` : ""}
<p class="muted">Оплаченную через Stripe подписку отменяет сам пользователь в кабинете или ты — в панели Stripe.</p>

<h2>Доступ</h2>
<div class="row">
<form method="post" action="/admin/user">${hidden}<input type="hidden" name="action" value="reset"><button class="btn">Сбросить недельный лимит</button></form>
${self ? "" : `<form method="post" action="/admin/user">${hidden}<input type="hidden" name="action" value="${user.disabled ? "unblock" : "block"}">
<button class="btn${user.disabled ? "" : " danger"}">${user.disabled ? "Разблокировать" : "Заблокировать"}</button></form>`}
</div>`;
	return layout(admin, user.email, body, csrf);
}

/* ─────────────────────────── actions ─────────────────────────── */

function grantDays(form: FormData): number | null {
	if (form.get("grant") === "forever") return 0;
	const n = Number(form.get("days"));
	return Number.isInteger(n) && n >= 1 && n <= 3650 ? n : null;
}

async function action(env: Env, request: Request, admin: User, path: string): Promise<Response> {
	const form = await request.formData().catch(() => new FormData());
	if (!(await validCsrf(env, request, form))) {
		return page("Форма устарела", `<h1>Форма устарела</h1><p>Обнови страницу админки и повтори.</p><p><a class="btn" href="/admin">Админка</a></p>`, 403, undefined, "ru");
	}

	if (path === "/admin/promo/create") {
		const days = grantDays(form);
		const raw = String(form.get("code") ?? "").trim();
		const code = raw ? normalizeCode(raw) : generateCode();
		const emails = form.get("who") === "emails" ? parseEmails(form.get("emails")) : [];
		const maxRaw = String(form.get("max_uses") ?? "").trim();
		const maxUses = maxRaw ? Number(maxRaw) : null;
		const expRaw = String(form.get("expires") ?? "").trim();
		const expiresAt = /^\d{4}-\d{2}-\d{2}$/.test(expRaw) ? Date.parse(`${expRaw}T23:59:59Z`) : null;
		if (days === null) return overview(env, request, admin, "Укажи срок подписки: от 1 до 3650 дней или «навсегда».");
		if (!code) return overview(env, request, admin, "Код: 3–32 символа, латиница, цифры, «-» и «_».");
		if (form.get("who") === "emails" && !emails.length) return overview(env, request, admin, "Добавь хотя бы один корректный email или выбери «все».");
		if (maxUses !== null && !(Number.isInteger(maxUses) && maxUses >= 1)) return overview(env, request, admin, "Лимит активаций — целое число от 1.");
		const ok = await createPromo(env, { code, grantDays: days, maxUses, emails, expiresAt, note: String(form.get("note") ?? "") });
		if (!ok) return overview(env, request, admin, `Код ${code} уже существует.`);
		await log(env, admin, "promo.create", `${code}: ${grantLabel(days)}, ${emails.length ? `${emails.length} email` : "все"}, лимит ${maxUses ?? "∞"}`);
		return overview(env, request, admin, `Промокод ${code} создан.`);
	}
	if (path === "/admin/promo/toggle" || path === "/admin/promo/delete") {
		const code = normalizeCode(form.get("code"));
		if (!code) return redirect("/admin#promo");
		if (path === "/admin/promo/delete") {
			await deletePromo(env, code);
			await log(env, admin, "promo.delete", code);
		} else {
			const current = await env.DB.prepare("SELECT active FROM promo_codes WHERE code = ?1").bind(code).first<{ active: number }>();
			if (current) {
				await setPromoActive(env, code, !current.active);
				await log(env, admin, current.active ? "promo.disable" : "promo.enable", code);
			}
		}
		return redirect("/admin#promo");
	}
	if (path === "/admin/settings") {
		const free = Number(form.get("free_calls_per_week"));
		const perMinute = Number(form.get("calls_per_minute"));
		if (!Number.isInteger(free) || free < 1 || free > 1_000_000 || !Number.isInteger(perMinute) || perMinute < 1 || perMinute > 10_000) {
			return overview(env, request, admin, "Лимиты — целые положительные числа.");
		}
		const announcement = String(form.get("announcement") ?? "").replace(/\s+/g, " ").trim().slice(0, 300);
		await saveSettings(env, { freeCallsPerWeek: free, callsPerMinute: perMinute, announcement });
		await log(env, admin, "settings.save", `free/week ${free}, per minute ${perMinute}, banner ${announcement ? `«${announcement}»` : "нет"}`);
		return overview(env, request, admin, "Настройки сохранены.");
	}
	if (path === "/admin/user") {
		const id = String(form.get("id") ?? "");
		const user = await getUser(env, id);
		if (!user) return redirect("/admin/users");
		const kind = String(form.get("action") ?? "");
		let notice = "";
		if (kind === "grant") {
			const days = grantDays(form);
			if (days === null) return userPage(env, request, admin, id, "Укажи срок: от 1 до 3650 дней или «навсегда».");
			const until = await grantComplimentary(env, id, days);
			notice = until >= COMP_FOREVER ? "Подписка выдана навсегда." : `Подписка до ${date(until)}.`;
			await log(env, admin, "user.grant", `${user.email}: ${grantLabel(days)}`);
		} else if (kind === "revoke") {
			await env.DB.prepare("UPDATE users SET comp_until = NULL WHERE id = ?1").bind(id).run();
			notice = "Подаренная подписка снята.";
			await log(env, admin, "user.revoke", user.email);
		} else if (kind === "reset") {
			await env.DB.prepare("UPDATE usage SET week_calls = 0 WHERE user_id = ?1").bind(id).run();
			notice = "Недельный лимит сброшен.";
			await log(env, admin, "user.reset", user.email);
		} else if ((kind === "block" || kind === "unblock") && id !== admin.id) {
			await env.DB.prepare("UPDATE users SET disabled = ?2 WHERE id = ?1").bind(id, kind === "block" ? 1 : 0).run();
			notice = kind === "block" ? "Пользователь заблокирован: MCP и кабинет для него закрыты." : "Пользователь разблокирован.";
			await log(env, admin, `user.${kind}`, user.email);
		} else {
			return userPage(env, request, admin, id, "Неизвестное действие.");
		}
		return userPage(env, request, admin, id, notice);
	}
	return notFound();
}

/** Entry point for every /admin path except the bearer-token /admin/subscription API. */
export async function adminPanel(request: Request, env: Env, path: string): Promise<Response> {
	if (!adminEmails(env).length) return notFound();
	const session = await getSession(env, request);
	if (!session && request.method === "GET") return redirect(`/login?return_to=${encodeURIComponent(path)}`);
	const admin = await adminUser(env, request);
	if (!admin) return notFound();
	if (request.method === "POST") return action(env, request, admin, path);
	if (request.method !== "GET") return notFound();
	if (path === "/admin" || path === "/admin/") return overview(env, request, admin);
	if (path === "/admin/users") return usersPage(env, request, admin);
	if (path === "/admin/user") return userPage(env, request, admin, new URL(request.url).searchParams.get("id") ?? "");
	return notFound();
}
