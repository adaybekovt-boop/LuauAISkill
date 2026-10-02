# Запуск LuauAISkill

Сервер: **https://luaumcp.tklabsskill.site/mcp**. Кабинет: **https://luaumcp.tklabsskill.site/account**.
Сайт настройки — проект Cloudflare Pages `luauaiskill-site`, репозиторий `LuauAiSkill.site`.
Worker — `luauaiskill`, репозиторий `LuauAISkill`, ветка `main`.

## Что уже реализовано

- Семь инструментов MCP и ресурс `skill://SKILL.md`; ответы API и сканера сверяются с Python-инструментами.
- Google sign-in, OAuth для Claude/Cursor/Codex, PKCE, согласие пользователя, обновление токенов.
- Кабинет: расход лимита, подписка, до пяти API-ключей со сроком 90 дней, отзыв ключей и приложений.
- Бесплатно: 100 успешных вызовов инструментов/чтений ресурсов в неделю. Сброс — понедельник 00:00 UTC.
  Инициализация, списки инструментов/ресурсов и неуспешные вызовы недельный лимит не расходуют.
- Подписка: $3–20 в месяц, сумму выбирает пользователь. Без недельного лимита; 60 вызовов в минуту на аккаунт.
- Stripe Checkout, изменение цены без доплаты за текущий период, Billing Portal, проверка подписанных вебхуков,
  защита от повторов и запоздавших событий. Повторные запросы checkout используют одну операцию.
- Предельный размер запроса, ограничение частоты на IP в Cloudflare, CSRF для форм кабинета,
  HttpOnly/Secure cookies, служебные ошибки без раскрытия внутренних данных.

## 1. Подключить Google

В Google Cloud Console создай OAuth client типа **Web application**. В OAuth consent screen укажи название
LuauAISkill, свой контакт, домен `tklabsskill.site` и разрешения `openid`, `email`, `profile`.
Если приложение в режиме Testing, добавь свои адреса как test users; для обычных пользователей переключи в Production.

**Authorized redirect URI**, строго:

```text
https://luaumcp.tklabsskill.site/auth/google/callback
```

В Cloudflare → Worker `luauaiskill` → Settings → Variables and Secrets добавь как **Secrets**:

| Имя | Значение |
|---|---|
| `GOOGLE_CLIENT_ID` | Client ID из Google |
| `GOOGLE_CLIENT_SECRET` | Client secret из Google |

Дополнительный `CONSENT_SECRET` не обязателен: ключ подписи автоматически выводится из Google client secret
с отдельным контекстом. При желании можно задать независимый секрет длиной от 32 символов.
Не публикуй значения в GitHub, `.env` сайта или чате.

При `AUTH_MODE=auto` сервер работает публично, пока Google не настроен. После подключения Google он автоматически
требует OAuth/API-ключ. Существующим клиентам понадобится Authenticate/Login. Если хочешь всегда закрытый режим,
задай `AUTH_MODE=oauth`: при неполной конфигурации сервер вернёт 503, а не откроет доступ.

Значение `ACCESS_POLICY=registered` оставь для бесплатного тарифа + подписки. `subscribed` закрывает бесплатный
доступ и предназначено для отдельного платного режима.

## 2. Подключить Stripe

Сначала проверь всё в Test mode. Создай один **Product** LuauAISkill MCP. Отдельные Price для каждой суммы
создавать не нужно: сервер формирует месячную цену в USD в Checkout. Сохрани Product ID (`prod_…`).

Настрой Billing Portal: разреши обновление карты, просмотр счетов и отмену **в конце оплаченного периода**.
Изменение цены выполняется через кабинет сервера; изменение количества и произвольных продуктов в Portal отключи.

Создай webhook destination:

```text
https://luaumcp.tklabsskill.site/billing/webhook
```

События:

```text
checkout.session.completed
checkout.session.async_payment_succeeded
customer.subscription.created
customer.subscription.updated
customer.subscription.deleted
invoice.paid
invoice.payment_succeeded
invoice.payment_failed
```

В Worker добавь три **Secrets**:

| Имя | Значение |
|---|---|
| `STRIPE_SECRET_KEY` | `sk_test_…`, затем `sk_live_…` |
| `STRIPE_WEBHOOK_SECRET` | `whsec_…` от соответствующего webhook destination |
| `STRIPE_PRODUCT_ID` | `prod_…` из того же Test/Live mode |

У сайта кнопки включатся сами по `/api/config`, без новой сборки. Успешный checkout-редирект не выдаёт подписку:
доступ активируется только после подписанного вебхука и чтения актуального состояния из Stripe.
Если платёж не прошёл, остаётся бесплатный тариф. При отмене в конце периода подписка сохраняется до его конца.
Цена меняется для будущих счетов без prorated charge. Не переключай Test/Live mode в базе с существующими
подписками: для проверки используй отдельное тестовое окружение либо переходи до регистрации реальных покупателей.

## Проверка после подключения

1. Открой `/ready` — должен быть `status: ready`. `/health` показывает текущий commit и readiness провайдеров.
2. Открой `/account`, войди через Google, создай API-ключ. Ключ показывается один раз, хранится только его хеш.
3. Подключи MCP:

```sh
claude mcp add --transport http --scope user luau-skill https://luaumcp.tklabsskill.site/mcp
# Затем /mcp → Authenticate
codex mcp add luau-skill --url https://luaumcp.tklabsskill.site/mcp
codex mcp login luau-skill
```

Для Cursor: URL в `mcp.json`, затем OAuth; если клиент не поддерживает OAuth, используй заголовок
`Authorization: Bearer <API-ключ из кабинета>`.

4. Попроси агента проверить устаревший API: `Humanoid.LoadAnimation` → `Animator:LoadAnimation`.
5. Проверь Stripe test checkout, получение webhook HTTP 200, активную подписку в кабинете, изменение цены и отмену.
6. Отзови ключ/приложение: старый доступ должен перестать работать. Не пересылай реальные ключи при диагностике.

## Выпуск и эксплуатация

Workers Builds: ветка `main`, корень `/`, build command пустой (его выполняет `wrangler.jsonc`), deploy command
`npx wrangler deploy`. При корне `mcp` — build `npm ci`, deploy `npx wrangler deploy`.
Wrangler автоматически создаёт отсутствующие bindings `OAUTH_KV` и D1 `luauaiskill-users`; их идентификаторы
сохраняет в настройках Worker. Таблицы создаются идемпотентно при первом использовании.
Токен сборки должен разрешать Workers/KV/D1 в нужном аккаунте. Существующую D1 не удаляй: в ней аккаунты,
квоты и связи подписок. За резервное восстановление D1 отвечает Cloudflare Time Travel.

Pages: ветка `main`, корень `/`, build `npm run build`, output `out`.
Конфигурация Pages есть в репозитории сайта; GitHub Pages workflow удалён.

Ручной выпуск при настроенном `CLOUDFLARE_API_TOKEN`:

```sh
cd mcp
npm ci
npm run typecheck
npm test
npm run deploy
# В репозитории сайта:
npm ci
npm run deploy
```

Проверка работающего публичного сервера или сервера с ключом (значение ключа передавай через окружение):

```sh
node scripts/smoke.mjs https://luaumcp.tklabsskill.site/mcp
```

`/ready` проверяет доступность D1/KV в OAuth-режиме. Ошибки имеют `X-Request-Id`; ищи его в Cloudflare Logs.
Настраиваемые переменные: `FREE_CALLS_PER_WEEK` (100), `CALLS_PER_MINUTE` (60), `PUBLIC_URL`.
MCP остаётся stateless Streamable HTTP: отдельный GET/SSE и DELETE сессии возвращают 405.
Большие scan/search-запросы могут превышать CPU budget Workers Free; для регулярных больших файлов используй
Workers Paid. В Roblox Studio этот выпуск не запускался. Настоящий вход Google и настоящий Stripe-платёж
нельзя проверить до настройки владельцем этих провайдеров.
