# 19. Разборы кода: как эксперт ревьюит и переписывает типичные скрипты

**Когда читать:** когда нужно проверить или починить чужой код, когда ты сам написал скрипт и хочешь
посмотреть на него глазами эксперта, или когда хочешь понять, *почему* правила из `00-START-HERE.md` именно
такие. Каждый кейс построен одинаково: реалистичный плохой скрипт (как пишут новички, старые туториалы и
слабые модели) → ревью с проблемами по убыванию серьёзности → исправленная версия, прошедшая typecheck против
Roblox API.

## Содержание
1. [Порядок ревью](#порядок-ревью)
2. [Кейс 1. Монетка на Touched](#кейс-1-монетка-на-touched)
3. [Кейс 2. Магазин, который верит клиенту](#кейс-2-магазин-который-верит-клиенту)
4. [Кейс 3. Наивное сохранение данных](#кейс-3-наивное-сохранение-данных)
5. [Кейс 4. Меч с уроном от клиента](#кейс-4-меч-с-уроном-от-клиента)
6. [Кейс 5. HUD, который ломается после смерти](#кейс-5-hud-который-ломается-после-смерти)
7. [Кейс 6. NPC, который преследует игрока](#кейс-6-npc-который-преследует-игрока)
8. [Кейс 7. Дверь с общим debounce и гонкой после yield](#кейс-7-дверь-с-общим-debounce-и-гонкой-после-yield)
9. [Шаблон ответа на ревью](#шаблон-ответа-на-ревью)
10. [Чек-лист](#чек-лист)
11. [Частые ошибки агентов](#частые-ошибки-агентов)

---

## Порядок ревью

Эксперт читает код не сверху вниз, а по вопросам. Сначала отвечает на них, потом ищет мелочи:

1. **Где это запускается?** Тип скрипта, место, RunContext. LocalScript в Workspace не работает. Script в
   ReplicatedStorage с RunContext Legacy не работает. Модуль из ServerStorage не виден клиенту.
2. **Кто владеет состоянием?** Если деньги, урон или инвентарь меняет клиент, это критическая уязвимость
   или баг: изменения клиента не видны серверу.
3. **Что приходит из сети?** Каждый аргумент `OnServerEvent` проверяется: тип, NaN/inf, диапазон, права,
   состояние, дистанция, частота.
4. **Что может потерять данные?** Сохранения, покупки, выход игрока посреди операции, выключение сервера.
5. **Что течёт?** Соединения, созданные на время жизни чего-то, таблицы с ключом Player, бесконечные циклы,
   неуничтоженные инстансы.
6. **Что сломается при повторе и параллельности?** Respawn, двойной вызов, два игрока одновременно, yield
   посреди логики.
7. **Устаревшие API и стиль:** `wait`, `spawn`, `Humanoid:LoadAnimation`, глобалы, магические числа.

Проблемы сообщаются в этом порядке: **безопасность → потеря данных → баги → утечки → производительность → стиль**.

---

## Кейс 1. Монетка на Touched

### Исходный код (Script внутри каждой монетки в Workspace)
```lua
-- BAD: typical tutorial-style coin
local coin = script.Parent
local debounce = false

coin.Touched:Connect(function(hit)
	if debounce == false then
		debounce = true
		local player = game.Players:GetPlayerFromCharacter(hit.Parent)
		player.leaderstats.Coins.Value = player.leaderstats.Coins.Value + 1
		coin.Transparency = 1
		wait(5)
		coin.Transparency = 0
		debounce = false
	end
end)
```

### Ревью
1. **Баг: краш на любом касании не-игроком.** `GetPlayerFromCharacter` возвращает `nil`, если коснулась
   деталь карты, аксессуар (`hit.Parent` — Accessory, а не персонаж) или NPC. Дальше `player.leaderstats`
   падает с ошибкой `attempt to index nil with 'leaderstats'`.
2. **Баг: монетку можно «собрать», когда она невидима?** Нет, мешает debounce. Но debounce **общий**: пока
   монетка перезаряжается, её не может взять никто. Здесь это желаемое поведение (монетка одна), но
   `debounce = true` ставится **до** проверки игрока. Если коснулась стена, монетка «съедается» на 5 секунд
   без выдачи. Точнее, скрипт падает на пункте 1, и debounce остаётся `true` **навсегда**: монетка умирает.
3. **Невидимая монетка всё ещё касаема и коллидирует.** Нужно `CanTouch = false` на время перезарядки.
4. **Устаревшее:** `wait` → `task.wait`, `game.Players` → `game:GetService("Players")`.
5. **Масштаб:** один Script на каждую монетку. 500 монет = 500 скриптов, их нельзя обновить разом. Лучше один
   сервисный скрипт и теги CollectionService.
6. **Нет проверки leaderstats:** если leaderstats ещё не создан (игрок только вошёл), будет ещё один краш.
7. **Мелочь:** `Value = Value + 1` → `Value += 1`.

### Исправленная версия: один Script на все монеты (теги)
```luau
--!strict
-- @path ServerScriptService/Review/CoinService.server
-- Script, ServerScriptService. Every BasePart tagged "Coin" becomes a collectible coin.
-- Setup: tag coin parts "Coin" (Tag Editor / Properties → Tags). Anchored = true, CanCollide = false.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local COIN_TAG = "Coin"
local COIN_VALUE = 1
local RESPAWN_SECONDS = 5

local function getCoinsValue(player: Player): IntValue?
	local leaderstats = player:FindFirstChild("leaderstats")
	local coins = leaderstats and leaderstats:FindFirstChild("Coins")
	if coins and coins:IsA("IntValue") then
		return coins
	end
	return nil
end

local function playerFromHit(hit: BasePart): Player?
	-- Walk up to the character model: hit may be a limb or a part inside an Accessory.
	local model = hit:FindFirstAncestorOfClass("Model")
	if not model then
		return nil
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return Players:GetPlayerFromCharacter(model)
end

local function setupCoin(instance: Instance)
	if not instance:IsA("BasePart") then
		return
	end
	local coin = instance
	local available = true

	-- The connection belongs to the coin: Destroy() on the coin disconnects it.
	coin.Touched:Connect(function(hit: BasePart)
		if not available then
			return
		end
		local player = playerFromHit(hit)
		if not player then
			return -- walls, NPCs and accessories no longer consume the coin
		end
		local coinsValue = getCoinsValue(player)
		if not coinsValue then
			return
		end
		-- Commit synchronously: no yield between the check and the state change.
		available = false
		coinsValue.Value += COIN_VALUE
		coin.Transparency = 1
		coin.CanTouch = false

		task.delay(RESPAWN_SECONDS, function()
			if coin.Parent == nil then
				return -- the coin was destroyed while respawning
			end
			coin.Transparency = 0
			coin.CanTouch = true
			available = true
		end)
	end)
end

CollectionService:GetInstanceAddedSignal(COIN_TAG):Connect(setupCoin)
for _, instance in CollectionService:GetTagged(COIN_TAG) do
	setupCoin(instance)
end
```

**Почему так:** один скрипт на все монеты; фильтр «это живой игрок» идёт до изменения состояния; commit
синхронный, без yield между проверкой и изменением; перезарядка через `task.delay` проверяет, что монета ещё
существует; `CanTouch = false` отключает касания невидимой монеты. Leaderstats создаёт отдельный скрипт
(см. `15-gameplay-cookbook.md`). Спин и эффекты подбора стоит делать на клиенте.

---

## Кейс 2. Магазин, который верит клиенту

### Исходный код
```lua
-- BAD: LocalScript in a shop button
local button = script.Parent
local remote = game.ReplicatedStorage.BuyItem

button.MouseButton1Click:Connect(function()
	remote:FireServer("Sword", 100) -- item name and price
end)
```
```lua
-- BAD: Script in ServerScriptService
game.ReplicatedStorage.BuyItem.OnServerEvent:Connect(function(player, itemName, price)
	local coins = player.leaderstats.Coins
	if coins.Value >= price then
		coins.Value = coins.Value - price
		local item = game.ServerStorage.Items[itemName]:Clone()
		item.Parent = player.Backpack
	end
end)
```

### Ревью
1. **Критично: цена от клиента.** Эксплойтер вызывает `BuyItem:FireServer("Sword", 0)` или
   `("Sword", -1e9)`. Отрицательная цена **начисляет** деньги: `coins.Value - (-1e9)`.
2. **Критично: имя предмета от клиента индексирует ServerStorage.** `Items[itemName]` с несуществующим
   именем падает с ошибкой. С именем любого другого объекта в `Items` выдаёт его, даже если он не продаётся.
   Нетабличные значения (`itemName = {}`) тоже роняют обработчик.
3. **NaN:** `price = 0/0`. Проверка `coins.Value >= NaN` ложна, здесь это безопасно случайно. В других
   формулах NaN проходит проверки `<` и `>` незаметно. Числа от клиента всегда проверяй на конечность.
4. **Нет rate limit:** спам покупками нагружает сервер.
5. **Нет проверки «уже куплено»:** можно купить сто мечей.
6. **Выдача в Backpack теряется при смерти.** Постоянные предметы нужно хранить в данных профиля и выдавать
   при каждом `CharacterAdded` (или класть копию в `StarterGear`).
7. **Стиль:** `game.ReplicatedStorage` вместо `GetService`; нет `WaitForChild` на клиенте.

### Исправленная версия
```luau
--!strict
-- @path ReplicatedStorage/Review/ShopConfig
-- ModuleScript, ReplicatedStorage. Shared catalog: UI reads it, but the SERVER is the one who trusts it.
export type ShopItem = {
	id: string,
	displayName: string,
	price: number,
	toolName: string, -- name of the Tool in ServerStorage/ShopTools
}

local items: { [string]: ShopItem } = {
	Sword = { id = "Sword", displayName = "Sword", price = 100, toolName = "Sword" },
	Bow = { id = "Bow", displayName = "Bow", price = 250, toolName = "Bow" },
}

return table.freeze(items)
```

```luau
--!strict
-- @path ServerScriptService/Review/ShopService.server
-- Script, ServerScriptService. Validates every purchase on the server.
-- Setup: ServerStorage/ShopTools contains Tools named like ShopConfig[*].toolName.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ShopConfig = require(ReplicatedStorage.Review.ShopConfig)

local remotes = ReplicatedStorage:FindFirstChild("ShopRemotes") or Instance.new("Folder")
remotes.Name = "ShopRemotes"
remotes.Parent = ReplicatedStorage

local buyItem = Instance.new("RemoteFunction")
buyItem.Name = "BuyItem"
buyItem.Parent = remotes

local toolsFolder = ServerStorage:WaitForChild("ShopTools")

local PURCHASE_COOLDOWN = 0.3
local lastPurchase: { [Player]: number } = {}
local owned: { [Player]: { [string]: boolean } } = {} -- in a real game this lives in the saved profile

local function getCoins(player: Player): IntValue?
	local leaderstats = player:FindFirstChild("leaderstats")
	local coins = leaderstats and leaderstats:FindFirstChild("Coins")
	return if coins and coins:IsA("IntValue") then coins else nil
end

local function giveTool(player: Player, toolName: string)
	local template = toolsFolder:FindFirstChild(toolName)
	if not (template and template:IsA("Tool")) then
		warn(`ShopTools/{toolName} is missing`)
		return
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	local starterGear = player:FindFirstChild("StarterGear")
	if backpack then
		template:Clone().Parent = backpack
	end
	if starterGear then
		template:Clone().Parent = starterGear -- survives respawn
	end
end

buyItem.OnServerInvoke = function(player: Player, itemId: unknown): (boolean, string)
	local now = os.clock()
	if now - (lastPurchase[player] or 0) < PURCHASE_COOLDOWN then
		return false, "TooFast"
	end
	lastPurchase[player] = now

	if type(itemId) ~= "string" or #itemId > 32 then
		return false, "BadRequest"
	end
	local item = ShopConfig[itemId]
	if not item then
		return false, "UnknownItem"
	end
	local ownedSet = owned[player]
	if not ownedSet then
		ownedSet = {}
		owned[player] = ownedSet
	end
	if ownedSet[item.id] then
		return false, "AlreadyOwned"
	end
	local coins = getCoins(player)
	if not coins then
		return false, "NotReady"
	end
	if coins.Value < item.price then
		return false, "NotEnoughCoins"
	end
	-- Commit: all checks above are synchronous, so nothing changed in between.
	coins.Value -= item.price
	ownedSet[item.id] = true
	giveTool(player, item.toolName)
	return true, "OK"
end

Players.PlayerRemoving:Connect(function(player: Player)
	lastPurchase[player] = nil
	owned[player] = nil
end)
```

```luau
--!strict
-- @path StarterPlayer/StarterPlayerScripts/Review/ShopButton.client
-- LocalScript, StarterPlayerScripts. Sends only the item id; shows the server's verdict.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local buyItem = ReplicatedStorage:WaitForChild("ShopRemotes"):WaitForChild("BuyItem") :: RemoteFunction
local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local shopGui = playerGui:WaitForChild("ShopGui")
local buyButton = shopGui:WaitForChild("BuySword") :: TextButton

local busy = false
buyButton.Activated:Connect(function()
	if busy then
		return
	end
	busy = true
	local ok, success, reason = pcall(function()
		return buyItem:InvokeServer("Sword")
	end)
	busy = false
	if not ok then
		buyButton.Text = "Error, try again"
	elseif success then
		buyButton.Text = "Owned"
	else
		buyButton.Text = if reason == "NotEnoughCoins" then "Not enough coins" else "Can't buy"
	end
end)
```

**Почему так:** клиент отправляет только `itemId`. Цена, существование предмета и владение берутся на сервере.
`InvokeServer` здесь уместен: отвечает сервер, ему можно доверять, что он вернёт ответ (на клиенте его всё
равно оборачиваем в pcall). `busy` на клиенте нужен для UX, а не для безопасности: безопасность обеспечивает
серверный кулдаун.

---

## Кейс 3. Наивное сохранение данных

### Исходный код
```lua
-- BAD
local DataStoreService = game:GetService("DataStoreService")
local store = DataStoreService:GetDataStore("PlayerData")

game.Players.PlayerAdded:Connect(function(player)
	local data = store:GetAsync(player.Name)
	if data == nil then
		data = { Coins = 0, Level = 1 }
	end
	player:SetAttribute("Coins", data.Coins)
	player:SetAttribute("Level", data.Level)
end)

game.Players.PlayerRemoving:Connect(function(player)
	store:SetAsync(player.Name, {
		Coins = player:GetAttribute("Coins"),
		Level = player:GetAttribute("Level"),
	})
end)
```

### Ревью
1. **Потеря данных: ключ по `Name`.** Игрок меняет ник и теряет весь прогресс. Ключ всегда строится из `UserId`.
2. **Потеря данных: `GetAsync` без pcall.** При сбое DataStore скрипт падает, атрибуты не ставятся, и
   `PlayerRemoving` сохраняет `nil`-поля поверх настоящих данных.
3. **Потеря данных: ошибка загрузки превращается в новый профиль.** Даже с pcall типичная ошибка выглядит
   так: `if not ok then data = defaults end`. После этого сохранение дефолтов **стирает** настоящий прогресс.
   Если загрузка не удалась, игрок не должен играть с сохранением (кик с сообщением или read-only режим).
4. **Потеря данных: нет `BindToClose`.** При выключении сервера `PlayerRemoving` может не успеть сохранить.
5. **Потеря данных: нет session lock.** Игрок быстро перезаходит на другой сервер. Новый сервер читает старые
   данные раньше, чем старый сервер успел сохранить, и дальше один перезаписывает другого.
6. **Нет ретраев** при временных ошибках (throttling, сеть).
7. **`SetAsync` вслепую** перезаписывает запись; `UpdateAsync` позволяет проверить версию или владельца сессии.
8. **Нет автосейва:** краш сервера теряет всю сессию.
9. **Порядок:** `PlayerAdded` без обхода уже вошедших игроков. В Studio игрок часто входит раньше, чем
   скрипт подключился.

### Исправленная версия (минимально надёжная)
Полноценная система профилей с session lock, миграциями и очередью сохранений описана в
`10-data-persistence-monetization.md`. Здесь минимальная версия, которая уже **не теряет данные** в типичных
сценариях. Session lock в ней упрощённый.

```luau
--!strict
-- @path ServerScriptService/Review/SimpleData.server
-- Script, ServerScriptService. Minimal SAFE persistence: UserId keys, pcall + retries,
-- failed load != new profile, UpdateAsync with a session marker, autosave, BindToClose.
-- For production prefer the full profile system in knowledge/10 or ProfileStore.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local STORE_NAME = if RunService:IsStudio() then "PlayerData_Studio" else "PlayerData_v1"
local store = DataStoreService:GetDataStore(STORE_NAME)

local MAX_ATTEMPTS = 4
local AUTOSAVE_SECONDS = 120
local SESSION_TIMEOUT = 20 * 60 -- a lock older than this is considered abandoned

type Data = { Coins: number, Level: number }
type Record = { data: Data, session: { jobId: string, time: number }? }

local DEFAULT_DATA: Data = { Coins = 0, Level = 1 }
local profiles: { [Player]: Data } = {}

local function keyFor(player: Player): string
	return `Player_{player.UserId}`
end

local function retry(label: string, fn: () -> ...any): boolean
	for attempt = 1, MAX_ATTEMPTS do
		local ok, err = pcall(fn)
		if ok then
			return true
		end
		warn(`{label} failed (attempt {attempt}): {err}`)
		if attempt < MAX_ATTEMPTS then
			task.wait(2 ^ attempt + math.random()) -- exponential backoff with jitter
		end
	end
	return false
end

local function sanitize(raw: unknown): Data
	local data = table.clone(DEFAULT_DATA)
	if type(raw) == "table" then
		local t = raw :: { [string]: unknown }
		if type(t.Coins) == "number" then
			data.Coins = t.Coins :: number
		end
		if type(t.Level) == "number" then
			data.Level = t.Level :: number
		end
	end
	return data
end

local function load(player: Player): Data?
	local loaded: Data? = nil
	local lockedElsewhere = false
	local ok = retry(`Load {player.UserId}`, function()
		store:UpdateAsync(keyFor(player), function(old: unknown): Record?
			-- Transform: no yields, no side effects outside of local variables. May run again.
			local record = if type(old) == "table" then old :: Record else nil
			local session = record and record.session
			if session and session.jobId ~= game.JobId and os.time() - session.time < SESSION_TIMEOUT then
				lockedElsewhere = true
				return nil -- returning nil cancels the write
			end
			lockedElsewhere = false
			local data = sanitize(record and record.data)
			loaded = data
			return { data = data, session = { jobId = game.JobId, time = os.time() } }
		end)
	end)
	if not ok or lockedElsewhere then
		return nil
	end
	return loaded
end

local function save(player: Player, data: Data, release: boolean): boolean
	local ok = retry(`Save {player.UserId}`, function()
		store:UpdateAsync(keyFor(player), function(old: unknown): Record?
			local record = if type(old) == "table" then old :: Record else nil
			local session = record and record.session
			if session and session.jobId ~= game.JobId then
				return nil -- another server owns this profile now: never overwrite it
			end
			local newSession = if release then nil else { jobId = game.JobId, time = os.time() }
			return { data = data, session = newSession }
		end)
	end)
	return ok
end

local function onPlayerAdded(player: Player)
	local data = load(player)
	if player.Parent == nil then
		-- The player left while we were loading. Release the lock we may have taken.
		if data then
			save(player, data, true)
		end
		return
	end
	if not data then
		player:Kick("Your data could not be loaded. Please rejoin in a minute.")
		return
	end
	profiles[player] = data
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Value = data.Coins
	coins.Parent = leaderstats
	leaderstats.Parent = player
	-- Gameplay code changes profiles[player] (the source of truth) and mirrors it to coins.Value.
end

local function onPlayerRemoving(player: Player)
	local data = profiles[player]
	if not data then
		return -- never loaded: nothing to save, and we must not write defaults
	end
	profiles[player] = nil
	save(player, data, true)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

task.spawn(function()
	while true do
		task.wait(AUTOSAVE_SECONDS)
		for player, data in profiles do
			task.spawn(save, player, data, false)
		end
	end
end)

game:BindToClose(function()
	if RunService:IsStudio() then
		task.wait(1) -- let PlayerRemoving saves start in Studio
	end
	local pending = 0
	for player, data in profiles do
		pending += 1
		task.spawn(function()
			save(player, data, true)
			pending -= 1
		end)
	end
	local deadline = os.clock() + 25 -- BindToClose has a hard limit of about 30 seconds
	while pending > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
end)
```

**Что осталось упрощённым** (см. `10-...` для полной версии): при `BindToClose` игрок может одновременно
сохраняться из `PlayerRemoving` и из `BindToClose`. Здесь это безопасно, потому что обе записи одинаковы и
проверяют владельца сессии. В большой системе нужна очередь сохранений на ключ. Не хранятся `PurchaseId`
для покупок (кейс не про них). Нет миграций схемы.

---

## Кейс 4. Меч с уроном от клиента

### Исходный код
```lua
-- BAD: LocalScript inside the Tool
local tool = script.Parent
local remote = game.ReplicatedStorage.DealDamage
local debounce = false

tool.Activated:Connect(function()
	local anim = tool.Parent.Humanoid:LoadAnimation(script.SlashAnim)
	anim:Play()
end)

tool.Handle.Touched:Connect(function(hit)
	if hit.Parent:FindFirstChild("Humanoid") and not debounce then
		debounce = true
		remote:FireServer(hit.Parent.Humanoid, 25)
		wait(0.5)
		debounce = false
	end
end)
```
```lua
-- BAD: Script in ServerScriptService
game.ReplicatedStorage.DealDamage.OnServerEvent:Connect(function(player, humanoid, damage)
	humanoid:TakeDamage(damage)
end)
```

### Ревью
1. **Критично: сервер наносит любой урон любому Humanoid по запросу.** Эксплойтер убивает всех на сервере
   одной строкой в цикле: `DealDamage:FireServer(target.Humanoid, math.huge)`. Отрицательный урон лечит.
2. **Критично: нет проверки дистанции, кулдауна, того, что меч экипирован и игрок жив.**
3. **Баг: урон наносится касанием, даже без взмаха.** Меч бьёт, когда просто касается врага.
4. **Баг: `LoadAnimation` на каждый клик** создаёт новый AnimationTrack. Треки копятся (есть лимит на
   количество загруженных треков), анимации наслаиваются. Трек загружают один раз и кэшируют.
5. **Устаревшее:** `Humanoid:LoadAnimation` → `Animator:LoadAnimation`; `wait` → `task.wait`.
6. **Баг:** `hit.Parent:FindFirstChild("Humanoid")` находит и собственного владельца меча: можно ударить себя.

### Исправленная версия: сервер сам ищет цели
```luau
--!strict
-- @path ServerScriptService/Review/SwordServer.server
-- Script, ServerScriptService. Server-authoritative melee: the client only says "I swung".
-- Setup: the Tool named "Sword" (with a Handle) is given to players (StarterPack or shop).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DAMAGE = 25
local COOLDOWN = 0.6
local RANGE = 6 -- studs in front of the character
local HITBOX_SIZE = Vector3.new(5, 5, RANGE)

local swingRemote = Instance.new("RemoteEvent")
swingRemote.Name = "SwordSwing"
swingRemote.Parent = ReplicatedStorage

local lastSwing: { [Player]: number } = {}

local function aliveHumanoid(model: Instance?): Humanoid?
	if not (model and model:IsA("Model")) then
		return nil
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return if humanoid and humanoid.Health > 0 then humanoid else nil
end

swingRemote.OnServerEvent:Connect(function(player: Player)
	local now = os.clock()
	if now - (lastSwing[player] or 0) < COOLDOWN then
		return
	end
	local character = player.Character
	local humanoid = aliveHumanoid(character)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (character and humanoid and root and root:IsA("BasePart")) then
		return
	end
	local tool = character:FindFirstChildOfClass("Tool")
	if not (tool and tool.Name == "Sword") then
		return -- the sword must be equipped (equipped tools are parented to the character)
	end
	lastSwing[player] = now

	-- Hitbox in front of the character, computed on the server from the server's view of the character.
	local boxCFrame = root.CFrame * CFrame.new(0, 0, -RANGE / 2)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }

	local damaged: { [Humanoid]: boolean } = {}
	for _, part in workspace:GetPartBoundsInBox(boxCFrame, HITBOX_SIZE, params) do
		local model = part:FindFirstAncestorOfClass("Model")
		local targetHumanoid = aliveHumanoid(model)
		if targetHumanoid and not damaged[targetHumanoid] then
			damaged[targetHumanoid] = true -- once per target per swing, no matter how many limbs overlap
			targetHumanoid:TakeDamage(DAMAGE)
		end
	end
end)

Players.PlayerRemoving:Connect(function(player: Player)
	lastSwing[player] = nil
end)
```

```luau
--!strict
-- @path StarterPlayer/StarterPlayerScripts/Review/SwordClient.client
-- LocalScript, StarterPlayerScripts. Plays the animation locally (it replicates from the
-- player's own Animator) and tells the server "I swung". Damage is decided by the server.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SLASH_ANIMATION_ID = "rbxassetid://0" -- replace with an animation owned by the game creator
local COOLDOWN = 0.6

local player = Players.LocalPlayer
local swingRemote = ReplicatedStorage:WaitForChild("SwordSwing") :: RemoteEvent

local slashAnimation = Instance.new("Animation")
slashAnimation.AnimationId = SLASH_ANIMATION_ID

local function onCharacterAdded(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local animator = humanoid:WaitForChild("Animator") :: Animator
	local slashTrack = animator:LoadAnimation(slashAnimation) -- loaded once per character
	local lastLocalSwing = 0

	local function bindTool(tool: Instance)
		if not (tool:IsA("Tool") and tool.Name == "Sword") then
			return
		end
		tool.Activated:Connect(function()
			local now = os.clock()
			if now - lastLocalSwing < COOLDOWN then
				return -- UX only; the server enforces the real cooldown
			end
			lastLocalSwing = now
			slashTrack:Play()
			swingRemote:FireServer()
		end)
	end

	-- The tool moves Backpack -> character when equipped. Bind it once, wherever it is now.
	local backpack = player:WaitForChild("Backpack")
	for _, tool in backpack:GetChildren() do
		bindTool(tool)
	end
	backpack.ChildAdded:Connect(function(child: Instance)
		if child:GetAttribute("SwordBound") then
			return
		end
		child:SetAttribute("SwordBound", true)
		bindTool(child)
	end)
end

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
	task.spawn(onCharacterAdded, player.Character)
end
```

**Почему так:** клиент ничего не сообщает о целях. Сервер берёт хитбокс перед персонажем в своей картине мира,
бьёт каждую цель один раз, проверяет кулдаун и экипировку. Анимация загружается один раз на персонажа. Для
игр с высоким пингом бывает нужна компенсация лага (клиент присылает цель, сервер проверяет её правдоподобие),
см. `09-networking-remotes-security.md` и `08-physics-raycast-movement.md`.

> Привязка Tool на клиенте упрощена, потому что тема кейса — серверная авторитетность. Атрибут
> `SwordBound`, который ставит клиент, виден только этому клиенту, и этого достаточно. Tool, который
> возвращается в Backpack после экипировки, остаётся тем же объектом, поэтому атрибут защищает от
> повторной привязки. Каноничный вариант Tool-скрипта см. в `11-characters-humanoid-animation.md`.

---

## Кейс 5. HUD, который ломается после смерти

### Исходный код
```lua
-- BAD: LocalScript inside StarterGui.HUD (ScreenGui with default ResetOnSpawn = true)
local player = game.Players.LocalPlayer
local label = script.Parent.CoinsLabel

while true do
	label.Text = "Coins: " .. player.leaderstats.Coins.Value
	wait(0.1)
end

player.CharacterAdded:Connect(function(char)
	char.Humanoid.HealthChanged:Connect(function(hp)
		script.Parent.HealthBar.Size = UDim2.new(hp / 100, 0, 1, 0)
	end)
end)
```

### Ревью
1. **Баг: код после `while true do` никогда не выполняется.** Цикл без выхода блокирует остаток скрипта.
   Подписка на здоровье мертва.
2. **Баг: `leaderstats` может ещё не существовать** при старте клиента: `attempt to index nil with 'Coins'`.
3. **Поллинг раз в 0.1 с** вместо события. Правильно: `Coins.Changed` (у ValueBase `Changed` передаёт новое
   значение) или атрибут и `GetAttributeChangedSignal`.
4. **Баг: `hp / 100`**. У Humanoid бывает `MaxHealth ≠ 100`. Правильно: `hp / humanoid.MaxHealth`, с clamp.
5. **`ResetOnSpawn = true` (по умолчанию):** GUI и этот скрипт пересоздаются при каждой смерти. Здесь это
   случайно маскирует пункт 1. В общем случае теряется состояние UI, а подписки дублируются, если скрипт живёт
   вне GUI.
6. **Нет обработки уже существующего персонажа:** `CharacterAdded` подключён после того, как персонаж уже
   появился.
7. **Устаревшее:** `wait` → `task.wait`.

### Исправленная версия
```luau
--!strict
-- @path StarterPlayer/StarterPlayerScripts/Review/Hud.client
-- LocalScript, StarterPlayerScripts. HUD lives in a ScreenGui with ResetOnSpawn = false.
-- Setup: StarterGui/HUD (ScreenGui, ResetOnSpawn = false) with TextLabel "CoinsLabel" and
-- Frame "HealthBack" containing Frame "HealthBar".
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local hud = player:WaitForChild("PlayerGui"):WaitForChild("HUD") :: ScreenGui
local coinsLabel = hud:WaitForChild("CoinsLabel") :: TextLabel
local healthBar = hud:WaitForChild("HealthBack"):WaitForChild("HealthBar") :: Frame

-- Coins: event-driven, waits for leaderstats without blocking the rest of the script.
task.spawn(function()
	local leaderstats = player:WaitForChild("leaderstats")
	local coins = leaderstats:WaitForChild("Coins") :: IntValue
	local function render(value: number)
		coinsLabel.Text = `Coins: {value}`
	end
	coins.Changed:Connect(render)
	render(coins.Value)
end)

-- Health: re-bound for every character. Connections to the old humanoid die with it.
local HEALTH_TWEEN = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function onCharacterAdded(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local function render()
		local fraction = if humanoid.MaxHealth > 0 then math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1) else 0
		TweenService:Create(healthBar, HEALTH_TWEEN, { Size = UDim2.fromScale(fraction, 1) }):Play()
	end
	humanoid.HealthChanged:Connect(render)
	humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(render)
	render()
end

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
	task.spawn(onCharacterAdded, player.Character)
end
```

---

## Кейс 6. NPC, который преследует игрока

### Исходный код
```lua
-- BAD: Script inside the NPC model
local npc = script.Parent
local humanoid = npc.Humanoid

while true do
	wait()
	local closest, dist = nil, math.huge
	for _, p in pairs(game.Players:GetPlayers()) do
		local d = (p.Character.HumanoidRootPart.Position - npc.HumanoidRootPart.Position).Magnitude
		if d < dist then
			closest, dist = p, d
		end
	end
	if closest then
		humanoid:MoveTo(closest.Character.HumanoidRootPart.Position)
		if dist < 5 then
			closest.Character.Humanoid.Health = closest.Character.Humanoid.Health - 10
		end
	end
end
```

### Ревью
1. **Баг: краш, когда у игрока нет персонажа** (респавн, загрузка): `attempt to index nil with 'HumanoidRootPart'`.
   После краша NPC мёртв навсегда.
2. **Баг: урон 10 за каждый кадр** (`wait()` ≈ 30 раз в секунду). Игрок умирает за треть секунды.
   Урон должен идти по кулдауну.
3. **Баг: NPC преследует мёртвых игроков** и продолжает цикл, когда умер сам.
4. **Нет pathfinding:** `MoveTo` идёт по прямой, NPC застревает о стены. Для простых арен это допустимо, для
   карт со стенами нужен `PathfindingService` (см. `11-characters-humanoid-animation.md`).
5. **Производительность:** цикл каждый кадр на каждого NPC. 50 NPC = 50 циклов. Решения обновляются
   5–10 раз в секунду, а не 60. Лучше один менеджер на всех NPC.
6. **Сетевое владение:** unanchored NPC рядом с игроком автоматически получает владельцем этого игрока.
   Клиент может телепортировать такого NPC. Для NPC, которых контролирует сервер, вызывают
   `root:SetNetworkOwner(nil)`.
7. **`Health -= 10` в обход `TakeDamage`** игнорирует ForceField (защиту после респавна).
8. **Устаревшее:** `wait()`, `pairs` без надобности, `game.Players`.

### Исправленная версия (простая арена, без pathfinding)
```luau
--!strict
-- @path ServerScriptService/Review/ChaserNpcs.server
-- Script, ServerScriptService. One manager drives every model tagged "Chaser".
-- Setup: NPC rigs with Humanoid + HumanoidRootPart, tagged "Chaser". For maps with walls,
-- replace the direct MoveTo with PathfindingService (knowledge/11).
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local TAG = "Chaser"
local THINK_INTERVAL = 0.2 -- seconds between decisions (5 Hz), not every frame
local AGGRO_RANGE = 60
local ATTACK_RANGE = 4.5
local ATTACK_DAMAGE = 10
local ATTACK_COOLDOWN = 1

type Npc = { model: Model, humanoid: Humanoid, root: BasePart, lastAttack: number }
local npcs: { [Model]: Npc } = {}

local function register(instance: Instance)
	if not instance:IsA("Model") or npcs[instance] then
		return
	end
	local humanoid = instance:FindFirstChildOfClass("Humanoid")
	local root = instance:FindFirstChild("HumanoidRootPart")
	if not (humanoid and root and root:IsA("BasePart")) then
		warn(`{instance:GetFullName()} is tagged {TAG} but has no Humanoid/HumanoidRootPart`)
		return
	end
	if root:CanSetNetworkOwnership() then
		root:SetNetworkOwner(nil) -- the server simulates this NPC; clients cannot move it
	end
	npcs[instance] = { model = instance, humanoid = humanoid, root = root, lastAttack = 0 }
	humanoid.Died:Connect(function()
		npcs[instance] = nil
	end)
end

local function findTarget(npc: Npc): (Humanoid?, BasePart?, number)
	local bestHumanoid: Humanoid?, bestRoot: BasePart?, bestDistance = nil, nil, AGGRO_RANGE
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
			local distance = (root.Position - npc.root.Position).Magnitude
			if distance < bestDistance then
				bestHumanoid, bestRoot, bestDistance = humanoid, root, distance
			end
		end
	end
	return bestHumanoid, bestRoot, bestDistance
end

local function think(npc: Npc, now: number)
	if npc.humanoid.Health <= 0 or npc.model.Parent == nil then
		npcs[npc.model] = nil
		return
	end
	local targetHumanoid, targetRoot, distance = findTarget(npc)
	if not (targetHumanoid and targetRoot) then
		npc.humanoid:MoveTo(npc.root.Position) -- stop
		return
	end
	npc.humanoid:MoveTo(targetRoot.Position)
	if distance <= ATTACK_RANGE and now - npc.lastAttack >= ATTACK_COOLDOWN then
		npc.lastAttack = now
		targetHumanoid:TakeDamage(ATTACK_DAMAGE) -- respects ForceField
	end
end

CollectionService:GetInstanceAddedSignal(TAG):Connect(register)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(instance: Instance)
	if instance:IsA("Model") then
		npcs[instance] = nil
	end
end)
for _, instance in CollectionService:GetTagged(TAG) do
	register(instance)
end

while true do
	local now = os.clock()
	for _, npc in npcs do
		-- think() never yields, so one bad NPC cannot stall the others; pcall isolates errors.
		local ok, err = pcall(function()
			think(npc, now)
		end)
		if not ok then
			warn(`Chaser {npc.model:GetFullName()} error: {err}`)
			npcs[npc.model] = nil
		end
	end
	task.wait(THINK_INTERVAL)
end
```

> Удаление ключей таблицы во время обхода в Luau допустимо (присваивание `nil` существующему ключу).
> Добавлять **новые** ключи во время обхода нельзя. Здесь `register` вызывается из событий, а не из цикла.

---

## Кейс 7. Дверь с общим debounce и гонкой после yield

### Исходный код
```lua
-- BAD: Script inside the door part
local door = script.Parent
local prompt = door.ProximityPrompt
local open = false

prompt.Triggered:Connect(function(player)
	if open then return end
	open = true
	for i = 1, 20 do
		door.CFrame = door.CFrame * CFrame.Angles(0, math.rad(4.5), 0)
		wait()
	end
	wait(3)
	for i = 1, 20 do
		door.CFrame = door.CFrame * CFrame.Angles(0, math.rad(-4.5), 0)
		wait()
	end
	open = false
end)
```

### Ревью
1. **Баг: дверь вращается вокруг центра, а не петли.** `CFrame * Angles` вращает вокруг центра детали.
   Нужна петля (hinge): вращение вокруг точки на краю, то есть закрытый CFrame двери относительно шарнира.
2. **Сетевая нагрузка и дёрганье:** 40 изменений CFrame с сервера по кадрам. Каждое реплицируется, на клиенте
   движение рваное. Лучше `TweenService` (сервер твинит одну деталь, это приемлемо для редких дверей) или
   сервер меняет атрибут `Open`, а анимирует клиент.
3. **Накопление ошибки:** многократное умножение CFrame копит float-погрешность, и дверь «уплывает». Правильно
   вычислять целевой CFrame от сохранённого исходного, а не от текущего.
4. **Уничтожение во время анимации:** если дверь удалили (сброс карты) во время `wait`, скрипт продолжит
   менять CFrame уничтоженной детали. Здесь это безвредно, но в общем случае после yield нужна проверка
   `door.Parent`.
5. **Устаревшее:** `wait`; ProximityPrompt найден точкой без `WaitForChild` (на сервере допустимо, если
   prompt создан в Studio).

### Исправленная версия
```luau
--!strict
-- @path ServerScriptService/Review/HingedDoors.server
-- Script, ServerScriptService. Every Model tagged "HingedDoor" with parts "Door" (anchored) and
-- "Hinge" (anchored, invisible, positioned on the door's edge) and a ProximityPrompt inside "Door".
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local TAG = "HingedDoor"
local OPEN_ANGLE = math.rad(90)
local STAY_OPEN_SECONDS = 3
local SWING_INFO = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function setupDoor(instance: Instance)
	if not instance:IsA("Model") then
		return
	end
	local door = instance:FindFirstChild("Door")
	local hinge = instance:FindFirstChild("Hinge")
	local prompt = door and door:FindFirstChildOfClass("ProximityPrompt")
	if not (door and door:IsA("BasePart") and hinge and hinge:IsA("BasePart") and prompt) then
		warn(`{instance:GetFullName()}: expected Door (BasePart), Hinge (BasePart), ProximityPrompt`)
		return
	end

	-- Store the door's pose relative to the hinge ONCE; every target is computed from it (no drift).
	local closedHinge = hinge.CFrame
	local doorOffset = closedHinge:ToObjectSpace(door.CFrame)
	local closedCFrame = door.CFrame
	local openCFrame = closedHinge * CFrame.Angles(0, OPEN_ANGLE, 0) * doorOffset

	local busy = false
	prompt.Triggered:Connect(function(_player: Player)
		if busy then
			return -- per-door state, not a global debounce
		end
		busy = true
		prompt.Enabled = false

		local openTween = TweenService:Create(door, SWING_INFO, { CFrame = openCFrame })
		openTween:Play()
		openTween.Completed:Wait()
		task.wait(STAY_OPEN_SECONDS)
		if not door:IsDescendantOf(game) then
			return -- the door was destroyed while we were waiting
		end
		local closeTween = TweenService:Create(door, SWING_INFO, { CFrame = closedCFrame })
		closeTween:Play()
		closeTween.Completed:Wait()

		if door:IsDescendantOf(game) then
			prompt.Enabled = true
			busy = false
		end
	end)
end

CollectionService:GetInstanceAddedSignal(TAG):Connect(setupDoor)
for _, instance in CollectionService:GetTagged(TAG) do
	setupDoor(instance)
end
```

**Математика петли:** `doorOffset = hinge:ToObjectSpace(door)` — поза двери в системе координат петли.
Повернули петлю: `hinge * Angles(...)`. Вернули дверь в мир: `* doorOffset`. Эту формулу используют для любого
вращения вокруг произвольной точки (см. `07-datatypes-cframe-math.md`).

---

## Шаблон ответа на ревью

```text
Итог: <одно предложение: главное, что не так>.

Критично (безопасность / потеря данных):
1. <проблема> — <почему это плохо, сценарий атаки или потери> — <исправление>
Баги:
2. ...
Утечки / производительность:
3. ...
Стиль / устаревшее:
4. ...

Исправленный код:
<тип скрипта, место>
<полный код>

Как проверить: <шаги в Studio, 2 клиента, что должно произойти>.
Статус: typecheck пройден (luau-lsp + определения Roblox); в Studio не запускалось.
```

## Чек-лист
- [ ] Для каждого скрипта определено, где и в каком контексте он работает.
- [ ] Найдено всё, что клиент может подделать (аргументы remotes, изменения на клиенте, которые код считает серверными).
- [ ] Найдены все пути потери данных (ключи, pcall, ошибка загрузки → дефолты, BindToClose, session lock).
- [ ] Найдены краши на nil: `FindFirstChild`, `GetPlayerFromCharacter`, `player.Character`, leaderstats.
- [ ] Найдены циклы без выхода, блокирующие код ниже, и циклы «каждый кадр» там, где хватит 5–10 Гц.
- [ ] Найдены повторные загрузки анимаций, соединения на каждый respawn без очистки, растущие таблицы.
- [ ] Исправленная версия прошла typecheck и сохранила задуманное поведение.
- [ ] Проблемы упорядочены по серьёзности, к каждой приложено исправление.

## Частые ошибки агентов
- **Чинят симптом, а не причину.** Например, оборачивают `player.leaderstats` в pcall вместо проверки на nil.
  Правильно: найти, почему там nil, и обработать этот случай явно.
- **Переписывают всё с нуля в новом стиле** и теряют поведение, которое пользователь хотел сохранить.
  Правильно: сохранять наблюдаемое поведение и менять ровно то, что сломано или опасно, объясняя каждую правку.
- **Не замечают, что `while true do` блокирует остаток скрипта.**
- **Сообщают о стиле раньше, чем об уязвимости.** Пользователю важнее «любой игрок может выдать себе деньги»,
  чем «используйте `+=`».
- **Предлагают клиентскую защиту** (проверки в LocalScript, скрытие remotes) как решение эксплойтов. Правильно:
  защита только на сервере.
- **Говорят «исправлено и протестировано»** без запуска. Правильно: «typecheck пройден, проверьте в Studio так-то».
