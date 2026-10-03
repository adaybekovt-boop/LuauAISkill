import assert from 'node:assert/strict';
import { test } from 'node:test';
import { Browser, ORIGIN, accountForm, connect, ctx, google, googleSignIn, makeEnv, rpc, worker } from './harness.mjs';

const ADMIN = { sub: '9001', email: 'Owner@Example.com', email_verified: true, name: 'Owner' };
const DEFAULT_PROFILE = { ...google.profile };
const DAY = 86_400_000;

function adminEnv(overrides = {}) {
  return makeEnv({ ADMIN_EMAILS: 'owner@example.com, second@example.com', ...overrides });
}

async function signInAs(env, profile) {
  google.profile = { email_verified: true, name: null, ...profile };
  const browser = new Browser(env);
  await googleSignIn(browser);
  google.profile = { ...DEFAULT_PROFILE };
  return browser;
}

async function adminPost(browser, path, fields = {}) {
  const page = await browser.fetch('/admin');
  assert.equal(page.status, 200, await page.clone().text());
  const csrf = /name="csrf" value="([^"]+)"/.exec(await page.text())[1];
  return browser.fetch(path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded', Origin: ORIGIN },
    body: new URLSearchParams({ csrf, ...fields }),
  });
}

const promo = (code, extra = {}) => ({ code, grant: 'days', days: '30', who: 'all', emails: '', max_uses: '', expires: '', note: '', ...extra });
const redeem = (browser, code) => accountForm(browser, '/account/promo', { code });
const compUntil = (env, id) => env.DB.db.prepare('SELECT comp_until FROM users WHERE id = ?').get(id).comp_until;

test('admin panel: only listed Google emails get in; others see 404, signed-out GET goes to sign-in', async () => {
  const env = adminEnv();
  const anon = await new Browser(env).fetch('/admin');
  assert.equal(anon.status, 302);
  assert.equal(anon.headers.get('Location'), '/login?return_to=%2Fadmin');

  const user = await signInAs(env, { sub: '1', email: 'someone@example.com' });
  assert.equal((await user.fetch('/admin')).status, 404);
  assert.equal((await user.fetch('/admin/users')).status, 404);

  const admin = await signInAs(env, ADMIN);
  const page = await admin.fetch('/admin');
  assert.equal(page.status, 200);
  const html = await page.text();
  assert.match(html, /lang="ru"/);
  assert.match(html, /Промокоды/);

  const closed = makeEnv(); // no ADMIN_EMAILS: the panel doesn't exist
  const owner = await signInAs(closed, ADMIN);
  assert.equal((await owner.fetch('/admin')).status, 404);
});

test('admin forms require CSRF and the site origin', async () => {
  const env = adminEnv();
  const admin = await signInAs(env, ADMIN);
  const missing = await admin.fetch('/admin/promo/create', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams(promo('NOCSRF')) });
  assert.equal(missing.status, 403);
  const page = await admin.fetch('/admin');
  const csrf = /name="csrf" value="([^"]+)"/.exec(await page.text())[1];
  const foreign = await admin.fetch('/admin/promo/create', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded', Origin: 'https://evil.test' }, body: new URLSearchParams({ csrf, ...promo('EVIL') }) });
  assert.equal(foreign.status, 403);
  assert.equal(env.DB.db.prepare('SELECT count(*) AS n FROM promo_codes').get().n, 0);
});

test('open promo with an activation cap: each account once, cap enforced, subscription granted', async () => {
  const env = adminEnv();
  const admin = await signInAs(env, ADMIN);
  const created = await adminPost(admin, '/admin/promo/create', promo('spring-30', { max_uses: '2' }));
  assert.equal(created.status, 200);
  assert.match(await created.text(), /SPRING-30 создан/);

  const a = await signInAs(env, { sub: '11', email: 'a@example.com' });
  const b = await signInAs(env, { sub: '12', email: 'b@example.com' });
  const c = await signInAs(env, { sub: '13', email: 'c@example.com' });
  assert.match(await (await redeem(a, ' spring-30 ')).text(), /subscription until/);
  assert.match(await (await redeem(a, 'SPRING-30')).text(), /already used/);
  assert.match(await (await redeem(b, 'SPRING-30')).text(), /subscription until/);
  assert.match(await (await redeem(c, 'SPRING-30')).text(), /no activations left/);
  assert.equal(env.DB.db.prepare("SELECT uses FROM promo_codes WHERE code = 'SPRING-30'").get().uses, 2);

  const until = compUntil(env, 'google_11');
  assert.ok(until > Date.now() + 29 * DAY && until < Date.now() + 31 * DAY);
  assert.equal(compUntil(env, 'google_13'), null);
  assert.match(await (await a.fetch('/account')).text(), /no weekly limit/);
});

test('parallel redemptions cannot exceed the cap', async () => {
  const env = adminEnv();
  const admin = await signInAs(env, ADMIN);
  await adminPost(admin, '/admin/promo/create', promo('RACE', { max_uses: '2' }));
  const users = [];
  for (let i = 0; i < 6; i++) users.push(await signInAs(env, { sub: `20${i}`, email: `u${i}@example.com` }));
  const pages = await Promise.all(users.map((u) => redeem(u, 'RACE').then((r) => r.text())));
  assert.equal(pages.filter((html) => /Promo applied/.test(html)).length, 2);
  assert.equal(env.DB.db.prepare("SELECT uses FROM promo_codes WHERE code = 'RACE'").get().uses, 2);
  assert.equal(env.DB.db.prepare("SELECT count(*) AS n FROM promo_redemptions WHERE code = 'RACE'").get().n, 2);
});

test('email-restricted, forever, disabled and expired promos', async () => {
  const env = adminEnv();
  const admin = await signInAs(env, ADMIN);
  await adminPost(admin, '/admin/promo/create', promo('VIP', { grant: 'forever', who: 'emails', emails: 'Friend@Example.com\nnot-an-email' }));
  await adminPost(admin, '/admin/promo/create', promo('OLD', { expires: '2020-01-01' }));
  await adminPost(admin, '/admin/promo/create', promo('OFF'));
  await adminPost(admin, '/admin/promo/toggle', { code: 'OFF' });

  const friend = await signInAs(env, { sub: '31', email: 'friend@example.com' });
  const stranger = await signInAs(env, { sub: '32', email: 'stranger@example.com' });
  assert.match(await (await redeem(stranger, 'VIP')).text(), /for other accounts/);
  assert.match(await (await redeem(friend, 'VIP')).text(), /subscription forever/);
  assert.equal(compUntil(env, 'google_31'), 32503680000000);
  assert.match(await (await redeem(friend, 'OLD')).text(), /expired/);
  assert.match(await (await redeem(friend, 'OFF')).text(), /exist or is turned off/);
  assert.match(await (await redeem(friend, 'NOPE')).text(), /exist or is turned off/);
  // a later 30-day code never shortens "forever"
  await adminPost(admin, '/admin/promo/create', promo('MORE'));
  await redeem(friend, 'MORE');
  assert.equal(compUntil(env, 'google_31'), 32503680000000);
});

test('promo subscription lifts the weekly allowance for MCP calls', async () => {
  const env = adminEnv({ FREE_CALLS_PER_WEEK: '1' });
  const { accessToken, browser } = await connect(env); // dev@example.com, google_1001
  const read = () => rpc(env, accessToken, 'tools/call', { name: 'api_lookup', arguments: { query: 'Workspace.Raycast' } });
  assert.equal((await read()).status, 200);
  assert.equal((await read()).status, 429);
  const admin = await signInAs(env, ADMIN);
  await adminPost(admin, '/admin/promo/create', promo('UNLIMITED', { grant: 'forever' }));
  assert.match(await (await redeem(browser, 'UNLIMITED')).text(), /forever/);
  assert.equal((await read()).status, 200);
  assert.equal((await read()).status, 200);
});

test('user management: grant, revoke, reset, block; admin cannot block themselves', async () => {
  const env = adminEnv({ FREE_CALLS_PER_WEEK: '1' });
  const { accessToken } = await connect(env);
  const read = () => rpc(env, accessToken, 'tools/call', { name: 'api_lookup', arguments: { query: 'Workspace.Raycast' } });
  const admin = await signInAs(env, ADMIN);
  const list = await (await admin.fetch('/admin/users?q=dev@')).text();
  assert.match(list, /dev@example\.com/);
  assert.ok(!list.includes('/admin/user?id=google_9001'), 'admin row filtered out by the search');

  assert.equal((await read()).status, 200);
  assert.equal((await read()).status, 429);
  await adminPost(admin, '/admin/user', { id: 'google_1001', action: 'reset' });
  assert.equal((await read()).status, 200);

  const granted = await (await adminPost(admin, '/admin/user', { id: 'google_1001', action: 'grant', grant: 'days', days: '7' })).text();
  assert.match(granted, /Подписка до/);
  assert.ok(compUntil(env, 'google_1001') > Date.now() + 6 * DAY);
  await adminPost(admin, '/admin/user', { id: 'google_1001', action: 'revoke' });
  assert.equal(compUntil(env, 'google_1001'), null);

  await adminPost(admin, '/admin/user', { id: 'google_1001', action: 'block' });
  assert.equal((await read()).status, 403);
  await adminPost(admin, '/admin/user', { id: 'google_1001', action: 'unblock' });
  // access is back; the one free call of this week was spent after the reset, so the quota (429) answers, not the ban (403)
  assert.equal((await read()).status, 429);

  const self = await (await adminPost(admin, '/admin/user', { id: 'google_9001', action: 'block' })).text();
  assert.match(self, /Неизвестное действие/);
  assert.equal(env.DB.db.prepare("SELECT disabled FROM users WHERE id = 'google_9001'").get().disabled, 0);

  const log = env.DB.db.prepare('SELECT action FROM admin_log ORDER BY id').all().map((r) => r.action);
  assert.deepEqual(log, ['user.reset', 'user.grant', 'user.revoke', 'user.block', 'user.unblock']);
});

test('settings change limits and the site banner without a redeploy', async () => {
  const env = adminEnv();
  const admin = await signInAs(env, ADMIN);
  const saved = await adminPost(admin, '/admin/settings', { free_calls_per_week: '250', calls_per_minute: '30', announcement: '  Скидка   до пятницы ' });
  assert.match(await saved.text(), /Настройки сохранены/);
  const config = await (await worker.fetch(new Request(`${ORIGIN}/api/config`), env, ctx)).json();
  assert.equal(config.free_calls_per_week, 250);
  assert.equal(config.calls_per_minute, 30);
  assert.equal(config.announcement, 'Скидка до пятницы');
  const bad = await adminPost(admin, '/admin/settings', { free_calls_per_week: '0', calls_per_minute: '30', announcement: '' });
  assert.match(await bad.text(), /целые положительные/);
});

test('admin output is escaped', async () => {
  const env = adminEnv();
  await signInAs(env, { sub: '66', email: 'x@example.com', name: '<script>alert(1)</script>' });
  const admin = await signInAs(env, ADMIN);
  const html = await (await admin.fetch('/admin/users')).text();
  assert.doesNotMatch(html, /<script>alert/);
  assert.match(html, /&#60;script&#62;/);
});
