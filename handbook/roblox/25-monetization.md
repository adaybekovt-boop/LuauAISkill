# Monetization: developer products, passes, subscriptions, transfers, policy

## TL;DR
- Grant value only from an authoritative receipt callback.
- Persist receipt idempotency with the granted value.
- Keep receipt API families and decision enums distinct.
- Handle retries, unavailable profiles, and transfer roles explicitly.
- Test duplicate delivery and failure windows without real purchases.

Read when: selling anything (developer products, passes, subscriptions, real-world commerce), Robux transfers,
loot boxes / gacha / spins, price tests. Related: [data persistence](06-data-persistence.md#developer-products-marketplaceserviceprocessreceipt)
(durable grants), recipe [save-system](../../recipes/gameplay/save-system.md) (working, session-locked receipt
handling), [security](04-security.md).

## Rules that prevent money bugs
| Rule | Why |
|---|---|
| Grant developer products **only** in a server receipt handler, never from `PromptProductPurchaseFinished` | the finished event says a prompt closed, not that money moved; receipts are retried until acknowledged |
| Deduplicate by `PurchaseId` stored **with** the grant (same profile save) | the handler can run again — on rejoin, on the next purchase, even on two servers at once |
| Acknowledge (`PurchaseGranted` / `Processed`) only after the save succeeded | acknowledged receipts are never delivered again; unsaved grants are lost on crash |
| Always install a handler before selling | with no `ProcessReceipt` and no bound handler, receipts are **auto-acknowledged** — the purchase can never be granted |
| One owner per receipt path | `ProcessReceipt` may be set once by one server Script; bound handlers have uniqueness rules (below) |
| Prices, ownership, entitlement are server facts | never accept a price, product id → reward mapping, or "I own it" from a client |
| Don't copy the docs' minimal `ProcessReceipt` sample as-is | it grants into `leaderstats` without `PurchaseId` dedupe or a durable save — fine as an API demo, wrong for production |

## Receipt APIs (two families, different enums)
| API | Return enum | Notes |
|---|---|---|
| `MarketplaceService.ProcessReceipt` (callback) | `Enum.ProductPurchaseDecision.PurchaseGranted` / `NotProcessedYet` | the classic path; docs now call it "legacy" but it is not deprecated and still works |
| `MarketplaceService:BindReceiptHandler(receiptType, handler, filter?)` → `RBXScriptConnection` | `Enum.ReceiptDecision.Processed` / `NotProcessedYet` | newer; `Enum.ReceiptType.DeveloperProduct`, `RobuxTransferSender`, `RobuxTransferReceiver` |
- `BindReceiptHandler` for developer products: **filtered** (array of product ids → that handler only) or
  **catch-all** (no filter → every product not claimed by a filtered handler). A bound handler takes precedence;
  unmatched product receipts fall through to `ProcessReceipt`, so you can migrate one product at a time.
- Receipt dictionary: `PurchaseId` (string, the dedupe key), `PlayerId`, `PlaceIdWherePurchased`, `ReceiptType`,
  `ProductId` + `CurrencyType` (developer products only), `CurrencySpent`, `TransferRequestId` (transfers only).
- Delivery: the player must be in the server; no timer retries — an unresolved receipt is redelivered when the player
  buys again or joins any server of the experience. Order between several pending receipts is not deterministic.
- `CurrencySpent` is what this player actually paid (price tests show different players different prices) — log it,
  don't compare it with a hard-coded price.

```luau
--!strict
-- Shape of a bound developer-product handler (TYPECHECKED only; not run). grantDurably must apply the reward AND
-- record the PurchaseId in the same profile save — see recipes/gameplay/save-system.md for a working version.
local MarketplaceService = game:GetService("MarketplaceService")

type GrantResult = "granted" | "duplicate" | "failed"
local function grantDurably(userId: number, purchaseId: string, productId: number): GrantResult
	return "failed" -- placeholder: real code goes through the session-locked profile
end

local GEM_PACKS = { 1111111, 2222222 } -- your developer product ids

MarketplaceService:BindReceiptHandler(Enum.ReceiptType.DeveloperProduct, function(receipt: { [string]: any })
	local result = grantDurably(receipt.PlayerId, tostring(receipt.PurchaseId), receipt.ProductId)
	if result == "granted" or result == "duplicate" then
		return Enum.ReceiptDecision.Processed -- duplicate = granted earlier, acknowledge again
	end
	return Enum.ReceiptDecision.NotProcessedYet -- redelivered on next join/purchase
end, GEM_PACKS)
```

## Robux transfers
`MarketplaceService:PromptRobuxTransferAsync(sender, receiverUserId, amount)` — **server only**, positive integer
amount, returns a `transferRequestId` (a request, not settlement). Value moves only when receipts arrive:
`RobuxTransferSender` for the sender and `RobuxTransferReceiver` for the receiver, both through `BindReceiptHandler`,
both carrying `TransferRequestId`. If the receiver needs approval (e.g. parental consent) settlement waits; offline
users get their receipt on next join. Treat each side's receipt as its own idempotent event. Robux transfers are the
documented replacement for cross-game sales.

## Passes, subscriptions, private servers
- **Passes** = permanent entitlements. Check on the server with `MarketplaceService:UserOwnsGamePassAsync(userId,
  passId)` on join and after `PromptGamePassPurchaseFinished` (a hint). Results are cached; a pass bought outside the
  experience can take minutes to show mid-session (always true on the next join).
- **Cross-game sales** of developer products and passes are disabled since **2026-05-30**; use Robux transfers.
- **Subscriptions** (recurring): entitlement = server call `MarketplaceService:GetUserSubscriptionStatusAsync(player,
  subscriptionId)` → `IsSubscribed`; re-check on `Players.UserSubscriptionStatusChanged`. The status check **must** run on
  the server (prompting may happen on the client). Product info: `GetSubscriptionProductInfoAsync`; history:
  `GetUserSubscriptionPaymentHistoryAsync`. When converting a pass to a subscription, keep granting the benefit to
  existing pass owners.
- Eligibility to buy: `PolicyService` (below) exposes `IsEligibleToPurchaseSubscription`.

## Paid random items (loot boxes, spins, gacha, re-rolls)
Policy (Terms of Use + Community Standards):
- "Paid" includes **in-game currency that can be bought with Robux** — keys, tickets, re-roll tokens count.
- Show **all outcomes and numerical odds** before the player spends; percentages must sum to 100 % (rounding
  disclaimer allowed); update odds when an outcome becomes unobtainable for that player.
- Items that change odds (lucky potion, better rod) must state the numeric effect before purchase, and the displayed
  odds must update while they are active.
- Free random rewards (earned without Robux/paid currency) don't need odds disclosure.
- Per player, call `PolicyService:GetPolicyInfoForPlayerAsync(player)` on the server and gate:
  `ArePaidRandomItemsRestricted` → no paid random generators (Robux or paid currency); `IsPaidItemTradingAllowed`
  → trading of paid items. Fail **closed** if the call errors (retry with backoff, show a recoverable message).
- Don't sell paid random items or quantity/time/role-limited items as external (Store-tab) developer products.

## Real-world commerce and pricing
- `CommerceService` (real-world products bundled with digital benefits): `GetCommerceProductInfoAsync`,
  `PromptCommerceProductPurchase`, `UserEligibleForRealWorldCommerceAsync`; eligibility also via `PolicyService`
  (`IsEligibleToPurchaseCommerceProduct`). Check each member's security with `tools/api.py` before use.
- **Managed Pricing** (Creator Hub → Monetization) unifies regional pricing and price optimization tests (~3 weeks;
  players see test prices after rejoining). Consequence for code: never hard-code prices in UI — read them with
  `GetProductInfoAsync` for the current player and expect them to change.

## Testing a purchase flow
Studio purchases are simulated (no Robux charged), which is fine for logic but not for retries. Test explicitly:
duplicate delivery of one `PurchaseId`; player leaves before the save finishes; save failure → `NotProcessedYet`;
rejoin on another server while the first handler yields; unknown product id; policy-restricted player. For
Store-tab (external) sales, Creator Hub has a **test mode** that costs real Robux and is visible only to you/your
group. Report anything you could not run as NOT RUN.

Sources: cd:production/monetization/developer-products, cd:production/monetization/passes,
cd:production/monetization/subscriptions, cd:production/monetization/robux-transfers,
cd:production/monetization/paid-random-items, cd:production/monetization/price-optimization,
cd:production/monetization/managed-pricing, cd:production/monetization/commerce-products,
cd:reference/engine/classes/MarketplaceService, cd:reference/engine/classes/PolicyService,
cd:reference/engine/classes/CommerceService, api:MarketplaceService.BindReceiptHandler, api:Enum.ReceiptDecision,
api:Enum.ReceiptType, api:MarketplaceService.PromptRobuxTransferAsync.
