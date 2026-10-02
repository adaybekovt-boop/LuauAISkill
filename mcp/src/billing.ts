import { publicUrl, type Env } from "./env";
import { ensureSchema, getUser } from "./users";

export const billingReady = (env: Env) => Boolean(env.STRIPE_SECRET_KEY && env.STRIPE_WEBHOOK_SECRET && env.STRIPE_PRODUCT_ID);
export function validAmount(value: unknown): number | null {
	const n = Number(value);
	return Number.isInteger(n) && n >= 300 && n <= 2000 && n % 100 === 0 ? n : null;
}

export class BillingError extends Error {}
type StripeObject = Record<string, any>;

async function stripe(env: Env, path: string, fields?: Record<string, string>, idempotencyKey?: string): Promise<StripeObject> {
	if (!env.STRIPE_SECRET_KEY) throw new BillingError("Payments are not configured yet.");
	const res = await fetch(`https://api.stripe.com/v1/${path}`, {
		method: fields ? "POST" : "GET",
		headers: { Authorization: `Bearer ${env.STRIPE_SECRET_KEY}`, "Stripe-Version": "2025-06-30.basil",
			...(fields ? { "Content-Type": "application/x-www-form-urlencoded" } : {}),
			...(idempotencyKey ? { "Idempotency-Key": idempotencyKey } : {}) },
		...(fields ? { body: new URLSearchParams(fields) } : {}),
		signal: AbortSignal.timeout(15000),
	});
	const body = await res.json() as StripeObject;
	if (!res.ok) throw new BillingError("The payment provider could not complete this request. Please try again.");
	return body;
}

export async function customerForUser(env: Env, userId: string): Promise<string> {
	await ensureSchema(env.DB);
	const existing = await env.DB.prepare("SELECT customer_id FROM billing_customers WHERE user_id = ?1").bind(userId).first<{customer_id: string}>();
	if (existing) return existing.customer_id;
	const user = await getUser(env, userId);
	if (!user || user.disabled) throw new BillingError("Account unavailable.");
	const customer = await stripe(env, "customers", { email: user.email, "metadata[user_id]": user.id }, `luau-customer-${user.id}`);
	await env.DB.prepare("INSERT INTO billing_customers (user_id, customer_id) VALUES (?1, ?2) ON CONFLICT(user_id) DO NOTHING")
		.bind(user.id, customer.id).run();
	return customer.id;
}

export async function subscriptionInfo(env: Env, userId: string): Promise<StripeObject | null> {
	await ensureSchema(env.DB);
	return env.DB.prepare(`SELECT * FROM billing_subscriptions WHERE user_id = ?1
		ORDER BY CASE WHEN status IN ('active', 'trialing') THEN 0 ELSE 1 END, updated_at DESC LIMIT 1`).bind(userId).first<StripeObject>();
}

export async function startCheckout(env: Env, userId: string, amount: number): Promise<string> {
	if (!billingReady(env) || validAmount(amount) === null) throw new BillingError("Payments are not configured or the amount is invalid.");
	const sub = await subscriptionInfo(env, userId);
	if (sub && ["active", "trialing", "past_due", "unpaid", "incomplete", "paused"].includes(sub.status)) {
		throw new BillingError("You already have a subscription. Manage it from your account.");
	}
	const customer = await customerForUser(env, userId);
	// Check the provider too: a payment can have completed while its webhook is still in transit.
	const live = await stripe(env, `subscriptions?customer=${encodeURIComponent(customer)}&status=all&limit=100`);
	if (!Array.isArray(live.data) || live.has_more) throw new BillingError("Could not verify existing subscriptions. Please use the billing portal.");
	if (live.data?.some((s: StripeObject) => ["active", "trialing", "past_due", "unpaid", "incomplete", "paused"].includes(s.status) &&
		s.items?.data?.some((i: StripeObject) => i.price?.product === env.STRIPE_PRODUCT_ID))) {
		throw new BillingError("You already have a subscription. Wait for confirmation or manage it from your account.");
	}
	const now = Date.now();
	await env.DB.prepare(`INSERT INTO billing_checkout (user_id, operation_id, amount, expires_at)
		VALUES (?1, ?2, ?3, ?4) ON CONFLICT(user_id) DO UPDATE SET
		operation_id = excluded.operation_id, amount = excluded.amount, expires_at = excluded.expires_at, session_id = NULL
		WHERE billing_checkout.expires_at <= ?5`).bind(userId, crypto.randomUUID(), amount, Math.floor(now / 1000) * 1000 + 3600000, now).run();
	const pending = (await env.DB.prepare("SELECT * FROM billing_checkout WHERE user_id = ?1").bind(userId).first<StripeObject>())!;
	if (pending.amount !== amount) throw new BillingError("A checkout is already open at another price. Cancel it from your account before changing the price.");
	const session = await stripe(env, "checkout/sessions", {
		mode: "subscription", customer,
		expires_at: String(pending.expires_at / 1000),
		"line_items[0][price_data][currency]": "usd",
		"line_items[0][price_data][unit_amount]": String(amount),
		"line_items[0][price_data][recurring][interval]": "month",
		"line_items[0][price_data][product]": env.STRIPE_PRODUCT_ID!,
		"line_items[0][quantity]": "1",
		"subscription_data[metadata][user_id]": userId,
		"metadata[user_id]": userId, client_reference_id: userId,
		success_url: `${publicUrl(env)}/account?billing=success`,
		cancel_url: `${publicUrl(env)}/account?billing=canceled`,
	}, `luau-checkout-${pending.operation_id}`);
	await env.DB.prepare("UPDATE billing_checkout SET session_id = ?2 WHERE user_id = ?1 AND operation_id = ?3")
		.bind(userId, session.id, pending.operation_id).run();
	return session.url;
}

export async function cancelCheckout(env: Env, userId: string): Promise<void> {
	const pending = await env.DB.prepare("SELECT session_id FROM billing_checkout WHERE user_id = ?1").bind(userId).first<{session_id: string | null}>();
	if (!pending) return;
	if (pending.session_id) await stripe(env, `checkout/sessions/${encodeURIComponent(pending.session_id)}/expire`, {});
	await env.DB.prepare("DELETE FROM billing_checkout WHERE user_id = ?1").bind(userId).run();
}

export async function startPortal(env: Env, userId: string): Promise<string> {
	const customer = await env.DB.prepare("SELECT customer_id FROM billing_customers WHERE user_id = ?1").bind(userId).first<{customer_id: string}>();
	if (!customer) throw new BillingError("There is no payment account yet.");
	const portal = await stripe(env, "billing_portal/sessions", { customer: customer.customer_id, return_url: `${publicUrl(env)}/account` });
	return portal.url;
}

export async function changePrice(env: Env, userId: string, amount: number, operationId: string): Promise<void> {
	if (!billingReady(env) || validAmount(amount) === null) throw new BillingError("Invalid subscription price.");
	const sub = await subscriptionInfo(env, userId);
	if (!sub || !["active", "trialing"].includes(sub.status)) throw new BillingError("An active subscription is required.");
	const live = await stripe(env, `subscriptions/${encodeURIComponent(sub.subscription_id)}`);
	const item = live.items?.data?.[0];
	if (live.customer !== sub.customer_id || item?.price?.product !== env.STRIPE_PRODUCT_ID || live.items.data.length !== 1) {
		throw new BillingError("This subscription cannot be changed here.");
	}
	await stripe(env, `subscriptions/${encodeURIComponent(sub.subscription_id)}`, {
		"items[0][id]": item.id, "items[0][price_data][currency]": "usd",
		"items[0][price_data][unit_amount]": String(amount),
		"items[0][price_data][product]": env.STRIPE_PRODUCT_ID!,
		"items[0][price_data][recurring][interval]": "month", proration_behavior: "none",
	}, `luau-price-${userId}-${operationId}-${amount}`);
}

async function validSignature(secret: string, raw: string, signature: string): Promise<boolean> {
	const fields = signature.split(",").map(p => p.trim().split("="));
	const timestamp = fields.find(([k]) => k === "t")?.[1];
	if (!timestamp || !/^\d+$/.test(timestamp) || Math.abs(Date.now() / 1000 - Number(timestamp)) > 300) return false;
	const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["verify"]);
	for (const [name, hex] of fields) {
		if (name !== "v1" || !/^[a-f0-9]{64}$/i.test(hex)) continue;
		const bytes = Uint8Array.from(hex.match(/../g)!, v => parseInt(v, 16));
		if (await crypto.subtle.verify("HMAC", key, bytes, new TextEncoder().encode(`${timestamp}.${raw}`))) return true;
	}
	return false;
}

/** Retrieve Stripe's current subscription rather than trusting delivery order or a checkout redirect. */
export async function webhook(request: Request, env: Env): Promise<Response> {
	if (!billingReady(env)) return Response.json({ error: "Payments are not configured" }, { status: 503 });
	const raw = await request.text();
	if (raw.length > 128000 || !await validSignature(env.STRIPE_WEBHOOK_SECRET!, raw, request.headers.get("Stripe-Signature") ?? "")) {
		return Response.json({ error: "Invalid webhook signature" }, { status: 400 });
	}
	let event: StripeObject;
	try { event = JSON.parse(raw); } catch { return Response.json({ error: "Invalid event" }, { status: 400 }); }
	if (typeof event.id !== "string" || !Number.isSafeInteger(event.created) || typeof event.type !== "string") {
		return Response.json({ error: "Invalid event" }, { status: 400 });
	}
	const object = event.data?.object;
	let subId: unknown;
	if (event.type.startsWith("customer.subscription.")) subId = object?.id;
	else if (["checkout.session.completed", "checkout.session.async_payment_succeeded"].includes(event.type)) subId = object?.subscription;
	else if (["invoice.paid", "invoice.payment_succeeded", "invoice.payment_failed"].includes(event.type)) {
		subId = object?.parent?.subscription_details?.subscription ?? object?.subscription;
	} else return Response.json({ received: true });
	if (typeof subId !== "string" || !/^sub_[A-Za-z0-9]+$/.test(subId)) return Response.json({ received: true });
	await ensureSchema(env.DB);
	if (await env.DB.prepare("SELECT id FROM billing_events WHERE id = ?1").bind(event.id).first()) return Response.json({ received: true });
	const sub = await stripe(env, `subscriptions/${encodeURIComponent(subId)}`);
	const owner = await env.DB.prepare("SELECT user_id FROM billing_customers WHERE customer_id = ?1").bind(sub.customer).first<{user_id: string}>();
	const item = sub.items?.data?.[0];
	if (!owner || sub.metadata?.user_id !== owner.user_id || item?.price?.product !== env.STRIPE_PRODUCT_ID) return Response.json({ received: true });
	const amount = item.price.unit_amount;
	if (sub.items.data.length !== 1 || item.price.currency !== "usd" || item.price.recurring?.interval !== "month" ||
		(item.price.recurring?.interval_count ?? 1) !== 1 || item.quantity !== 1 || validAmount(amount) === null) {
		throw new BillingError("Subscription configuration does not match this product.");
	}
	const periodEnd = Number(item.current_period_end ?? sub.current_period_end) * 1000;
	if (!Number.isFinite(periodEnd) || periodEnd <= 0) throw new BillingError("The subscription has no valid billing period.");
	await env.DB.batch([
		env.DB.prepare(`INSERT INTO billing_subscriptions
			(subscription_id, user_id, customer_id, status, period_end, amount, currency, cancel_at_period_end, updated_at)
			VALUES (?1, ?2, ?3, ?4, ?5, ?6, 'usd', ?7, ?8)
			ON CONFLICT(subscription_id) DO UPDATE SET status = excluded.status, period_end = excluded.period_end,
			amount = excluded.amount, cancel_at_period_end = excluded.cancel_at_period_end, updated_at = excluded.updated_at
			WHERE billing_subscriptions.updated_at <= excluded.updated_at`)
			.bind(sub.id, owner.user_id, sub.customer, sub.status, periodEnd, amount, sub.cancel_at_period_end ? 1 : 0, event.created),
		env.DB.prepare(`UPDATE users SET
			subscription_status = CASE WHEN EXISTS (SELECT 1 FROM billing_subscriptions WHERE user_id = ?1
			AND status IN ('active', 'trialing') AND period_end > ?2) THEN 'active' ELSE 'none' END,
			subscription_period_end = (SELECT max(period_end) FROM billing_subscriptions WHERE user_id = ?1
			AND status IN ('active', 'trialing') AND period_end > ?2) WHERE id = ?1`).bind(owner.user_id, Date.now()),
		env.DB.prepare("INSERT INTO billing_events (id, created_at) VALUES (?1, ?2) ON CONFLICT(id) DO NOTHING").bind(event.id, event.created),
		env.DB.prepare("DELETE FROM billing_checkout WHERE user_id = ?1 AND session_id = ?2").bind(owner.user_id, typeof object?.id === "string" ? object.id : ""),
	]);
	return Response.json({ received: true });
}
