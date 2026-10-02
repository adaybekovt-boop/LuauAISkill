import assert from 'node:assert/strict';
import { test } from 'node:test';
import { Browser, ORIGIN, accountForm, connect, ctx, googleSignIn, makeEnv, rpc, stripe, worker } from './harness.mjs';

const read = (env, token, args = { query: 'Workspace.Raycast' }) => rpc(env, token, 'tools/call', { name: 'api_lookup', arguments: args });
const billingEnv = () => makeEnv({ STRIPE_SECRET_KEY: 'sk_test', STRIPE_WEBHOOK_SECRET: 'whsec_test', STRIPE_PRODUCT_ID: 'prod_test' });

async function subscriptionFixture(env, status = 'active') {
  const { browser, accessToken } = await connect(env);
  env.DB.db.prepare('INSERT INTO billing_customers (user_id, customer_id) VALUES (?, ?)').run('google_1001', 'cus_test');
  stripe.subscriptions.set('sub_test', {
    id: 'sub_test', customer: 'cus_test', status, metadata: { user_id: 'google_1001' }, cancel_at_period_end: false,
    items: { data: [{ id: 'si_test', quantity: 1, current_period_end: Math.floor(Date.now() / 1000) + 86400,
      price: { unit_amount: 700, currency: 'usd', product: 'prod_test', recurring: { interval: 'month', interval_count: 1 } } }] },
  });
  return { browser, accessToken };
}

async function sendEvent(env, id, created = Math.floor(Date.now() / 1000), type = 'customer.subscription.updated', signatureOverride) {
  const raw = JSON.stringify({ id, created, type, data: { object: { id: 'sub_test', subscription: 'sub_test' } } });
  const t = String(Math.floor(Date.now() / 1000));
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(env.STRIPE_WEBHOOK_SECRET), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const signature = Buffer.from(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(`${t}.${raw}`))).toString('hex');
  return worker.fetch(new Request(`${ORIGIN}/billing/webhook`, { method: 'POST', headers: { 'Stripe-Signature': signatureOverride ?? `t=${t},v1=${signature}` }, body: raw }), env, ctx);
}

test('weekly allowance is shared across tools/resources; discovery and invalid calls are free', async () => {
  const env = makeEnv({ FREE_CALLS_PER_WEEK: '2' });
  const { accessToken } = await connect(env);
  for (let i = 0; i < 3; i++) assert.equal((await rpc(env, accessToken, 'tools/list')).status, 200);
  assert.ok((await read(env, accessToken, {})).json.result.isError);
  assert.equal((await read(env, accessToken)).status, 200);
  assert.equal((await rpc(env, accessToken, 'resources/read', { uri: 'skill://SKILL.md' })).status, 200);
  const denied = await read(env, accessToken);
  assert.equal(denied.status, 429);
  assert.ok(Number(denied.headers.get('Retry-After')) > 0);
  assert.equal(env.DB.db.prepare('SELECT week_calls FROM usage').get().week_calls, 2);
});

test('parallel calls cannot overspend the atomic free allowance', async () => {
  const env = makeEnv({ FREE_CALLS_PER_WEEK: '3' });
  const { accessToken } = await connect(env);
  const results = await Promise.all(Array.from({ length: 12 }, () => read(env, accessToken)));
  assert.equal(results.filter(r => r.status === 200).length, 3);
  assert.equal(results.filter(r => r.status === 429).length, 9);
  assert.equal(env.DB.db.prepare('SELECT week_calls FROM usage').get().week_calls, 3);
});

test('paid access has no weekly allowance but keeps the per-minute limit', async () => {
  const env = makeEnv({ FREE_CALLS_PER_WEEK: '1', CALLS_PER_MINUTE: '2' });
  const { accessToken } = await connect(env);
  env.DB.db.prepare("UPDATE users SET subscription_status = 'active', subscription_period_end = ?").run(Date.now() + 86400000);
  assert.equal((await read(env, accessToken)).status, 200);
  assert.equal((await read(env, accessToken)).status, 200);
  const denied = await read(env, accessToken);
  assert.equal(denied.status, 429);
  assert.match(denied.json.error.message, /Too many/);
});

test('weekly and minute windows reset independently', async () => {
  const env = makeEnv({ FREE_CALLS_PER_WEEK: '1' });
  const { accessToken } = await connect(env);
  await read(env, accessToken);
  env.DB.db.prepare('UPDATE usage SET week = week - 604800000, minute = minute - 1').run();
  assert.equal((await read(env, accessToken)).status, 200);
  assert.equal(env.DB.db.prepare('SELECT week_calls FROM usage').get().week_calls, 1);
});

test('API keys are hashed, expire, share quotas and revoke immediately', async () => {
  const env = makeEnv({ FREE_CALLS_PER_WEEK: '2' });
  const { browser, accessToken } = await connect(env);
  const created = await accountForm(browser, '/account/keys', { label: '<script>client</script>' });
  const html = await created.text();
  const key = /la_sk_[A-Za-z0-9_-]{43}/.exec(html)[0];
  assert.doesNotMatch(html, /<script>client<\/script>/);
  assert.ok(env.DB.db.prepare('SELECT token_hash FROM api_keys').get().token_hash !== key);
  assert.equal((await read(env, key)).status, 200);
  assert.equal((await read(env, accessToken)).status, 200);
  assert.equal((await read(env, key)).status, 429);
  const id = env.DB.db.prepare('SELECT id FROM api_keys').get().id;
  assert.equal((await accountForm(browser, '/account/keys/revoke', { id })).status, 302);
  assert.equal((await rpc(env, key, 'tools/list')).status, 401);
  const next = await accountForm(browser, '/account/keys', { label: 'expired' });
  const nextKey = /la_sk_[A-Za-z0-9_-]{43}/.exec(await next.text())[0];
  env.DB.db.prepare('UPDATE api_keys SET expires_at = 0').run();
  assert.equal((await rpc(env, nextKey, 'tools/list')).status, 401);
});

test('API key cap and owner checks prevent unsafe key creation and revocation', async () => {
  const env = makeEnv();
  const { browser } = await connect(env);
  for (let i = 0; i < 5; i++) assert.equal((await accountForm(browser, '/account/keys', { label: `key ${i}` })).status, 200);
  assert.equal((await accountForm(browser, '/account/keys', { label: 'sixth' })).status, 409);
  assert.equal(env.DB.db.prepare('SELECT count(*) AS n FROM api_keys').get().n, 5);
});

test('account forms reject missing CSRF and foreign origins, including logout', async () => {
  const env = billingEnv();
  const browser = new Browser(env);
  await googleSignIn(browser);
  const missing = await browser.fetch('/logout', { method: 'POST' });
  assert.equal(missing.status, 403);
  const page = await browser.fetch('/account');
  const csrf = /name="csrf" value="([^"]+)"/.exec(await page.text())[1];
  const foreign = await browser.fetch('/billing/checkout', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded', Origin: 'https://evil.test' }, body: new URLSearchParams({ csrf, amount: '700' }) });
  assert.equal(foreign.status, 403);
  assert.equal((await browser.fetch('/account')).status, 200);
});

test('revoked OAuth connections cannot call MCP or refresh', async () => {
  const env = makeEnv();
  const { browser, accessToken, refreshToken, clientId } = await connect(env);
  const account = await browser.fetch('/account');
  const id = /action="\/account\/connections\/revoke"[^]*?name="id" value="([^"]+)"/.exec(await account.text())[1];
  assert.equal((await accountForm(browser, '/account/connections/revoke', { id })).status, 302);
  assert.equal((await rpc(env, accessToken, 'tools/list')).status, 401);
  const refreshed = await browser.fetch('/token', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ grant_type: 'refresh_token', refresh_token: refreshToken, client_id: clientId }) });
  assert.equal(refreshed.status, 400);
});

test('checkout validates the amount and never activates access from the success URL', async () => {
  const env = billingEnv();
  const browser = new Browser(env);
  await googleSignIn(browser);
  const invalid = await accountForm(browser, '/billing/checkout', { amount: '299' });
  assert.equal(invalid.status, 400);
  const checkout = await accountForm(browser, '/billing/checkout', { amount: '700' });
  assert.equal(checkout.status, 302);
  assert.equal(checkout.headers.get('Location'), 'https://checkout.stripe.com/test');
  const fields = stripe.calls.at(-1).fields;
  assert.equal(fields['line_items[0][price_data][unit_amount]'], '700');
  assert.equal(fields['subscription_data[metadata][user_id]'], 'google_1001');
  await browser.fetch('/account?billing=success');
  assert.equal(env.DB.db.prepare('SELECT subscription_status FROM users').get().subscription_status, 'none');
});

test('webhooks reject forged signatures and grant access only after verified canonical state', async () => {
  const env = billingEnv();
  await subscriptionFixture(env);
  assert.equal((await sendEvent(env, 'evt_fake', undefined, undefined, 't=0,v1=bad')).status, 400);
  assert.equal(env.DB.db.prepare('SELECT subscription_status FROM users').get().subscription_status, 'none');
  assert.equal((await sendEvent(env, 'evt_real')).status, 200);
  assert.equal(env.DB.db.prepare('SELECT subscription_status FROM users').get().subscription_status, 'active');
  const calls = stripe.calls.length;
  assert.equal((await sendEvent(env, 'evt_real')).status, 200);
  assert.equal(stripe.calls.length, calls, 'duplicate events do not call Stripe again');
  assert.equal(env.DB.db.prepare('SELECT count(*) AS n FROM billing_events').get().n, 1);
});

test('scheduled cancellation preserves the paid period, immediate cancellation returns to free', async () => {
  const env = billingEnv();
  const { accessToken } = await subscriptionFixture(env);
  const live = stripe.subscriptions.get('sub_test');
  live.cancel_at_period_end = true;
  await sendEvent(env, 'evt_schedule');
  assert.equal(env.DB.db.prepare('SELECT subscription_status FROM users').get().subscription_status, 'active');
  live.status = 'canceled';
  await sendEvent(env, 'evt_cancel', Math.floor(Date.now() / 1000) + 1, 'customer.subscription.deleted');
  assert.equal(env.DB.db.prepare('SELECT subscription_status FROM users').get().subscription_status, 'none');
  assert.equal((await read(env, accessToken)).status, 200, 'free tier remains available');
});

test('out-of-order webhooks cannot revive a canceled subscription', async () => {
  const env = billingEnv();
  await subscriptionFixture(env);
  const now = Math.floor(Date.now() / 1000);
  await sendEvent(env, 'evt_active', now - 3);
  stripe.subscriptions.get('sub_test').status = 'canceled';
  await sendEvent(env, 'evt_new', now);
  await sendEvent(env, 'evt_old', now - 2);
  assert.equal(env.DB.db.prepare('SELECT subscription_status FROM users').get().subscription_status, 'none');
});

test('payment-provider failure is retryable and never exposes upstream details', async () => {
  const env = billingEnv();
  await subscriptionFixture(env);
  stripe.failure = true;
  try {
    const response = await sendEvent(env, 'evt_retry');
    assert.equal(response.status, 503);
    assert.doesNotMatch(await response.text(), /upstream secret/);
    assert.equal(env.DB.db.prepare('SELECT count(*) AS n FROM billing_events').get().n, 0);
  } finally { stripe.failure = false; }
  assert.equal((await sendEvent(env, 'evt_retry')).status, 200);
});

test('public preview works before Google setup; forced OAuth fails closed', async () => {
  const env = makeEnv({ GOOGLE_CLIENT_SECRET: undefined });
  assert.equal((await rpc(env, null, 'tools/list')).status, 200);
  assert.equal((await rpc(env, null, 'tools/list', {}, '/')).status, 200);
  assert.equal((await worker.fetch(new Request(`${ORIGIN}/.well-known/oauth-authorization-server`), env, ctx)).status, 404);
  assert.equal((await worker.fetch(new Request(`${ORIGIN}/login`), env, ctx)).status, 503);
  env.AUTH_MODE = 'oauth';
  assert.equal((await rpc(env, null, 'tools/list')).status, 503);
  assert.equal((await worker.fetch(new Request(`${ORIGIN}/ready`), env, ctx)).status, 503);
});

test('oversized streamed requests are rejected without Content-Length; demo is narrow', async () => {
  const env = makeEnv({ GOOGLE_CLIENT_SECRET: undefined });
  const oversized = await worker.fetch(new Request(`${ORIGIN}/mcp`, { method: 'POST', body: 'x'.repeat(1024 * 1024 + 1) }), env, ctx);
  assert.equal(oversized.status, 413);
  assert.ok(oversized.headers.get('X-Request-Id'));
  const browser = new Browser(env);
  const demo = await browser.fetch('/api/demo', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ query: 'Humanoid.LoadAnimation' }) });
  assert.equal(demo.status, 200);
  assert.match((await demo.json()).text, /DEPRECATED/);
  const config = await browser.fetch('/api/config');
  assert.equal((await config.json()).google_ready, false);
});

test('duplicate and parallel checkout requests reuse one operation; another price requires cancellation', async () => {
  const env = billingEnv();
  const browser = new Browser(env);
  await googleSignIn(browser);
  const results = await Promise.all([accountForm(browser, '/billing/checkout', { amount: '700' }), accountForm(browser, '/billing/checkout', { amount: '700' })]);
  assert.ok(results.every(r => r.status === 302));
  assert.equal(env.DB.db.prepare('SELECT count(*) AS n FROM billing_checkout').get().n, 1);
  assert.equal((await accountForm(browser, '/billing/checkout', { amount: '800' })).status, 409);
  assert.equal((await accountForm(browser, '/billing/checkout/cancel')).status, 302);
  assert.equal((await accountForm(browser, '/billing/checkout', { amount: '800' })).status, 302);
});

test('a price change keeps the billing period and disables prorated charges', async () => {
  const env = billingEnv();
  const { browser } = await subscriptionFixture(env);
  await sendEvent(env, 'evt_price_ready');
  const response = await accountForm(browser, '/billing/price', { amount: '800' });
  assert.equal(response.status, 302);
  const fields = stripe.calls.at(-1).fields;
  assert.equal(fields['items[0][price_data][unit_amount]'], '800');
  assert.equal(fields.proration_behavior, 'none');
  assert.equal((await accountForm(browser, '/billing/portal')).headers.get('Location'), 'https://billing.stripe.com/test');
});

test('reconnecting clients can refresh valid tokens; disabled users cannot refresh', async () => {
  const env = makeEnv();
  const { browser, refreshToken, clientId } = await connect(env);
  const fields = { grant_type: 'refresh_token', refresh_token: refreshToken, client_id: clientId, resource: `${ORIGIN}/mcp` };
  const renewed = await browser.fetch('/token', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams(fields) });
  assert.equal(renewed.status, 200);
  const tokens = await renewed.json();
  assert.equal((await rpc(env, tokens.access_token, 'tools/list')).status, 200);
  env.DB.db.prepare('UPDATE users SET disabled = 1').run();
  assert.equal((await rpc(env, tokens.access_token, 'tools/list')).status, 403);
  const denied = await browser.fetch('/token', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ ...fields, refresh_token: tokens.refresh_token }) });
  assert.equal(denied.status, 400);
});

test('independent consent-secret setup is optional and Google activation is automatic', async () => {
  const env = makeEnv({ CONSENT_SECRET: undefined });
  const { accessToken } = await connect(env);
  assert.equal((await rpc(env, accessToken, 'tools/list')).status, 200);
  assert.equal((await new Browser(env).fetch('/api/config')).status, 200);
});
