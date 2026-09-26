# 00. Начни здесь: как писать Roblox/Luau-код на уровне эксперта

**Когда читать:** всегда, первым, перед любой задачей по Roblox/Luau. Здесь описано, как работает эксперт:
алгоритм решения задачи, решения по умолчанию, золотые правила, скелеты скриптов, формат ответа и чек-лист
самопроверки. Остальные файлы `knowledge/` — подробные справочники по темам. Слой `handbook/` — процесс,
безопасность и доказательность (что считать проверенным). Слой `knowledge/` — **как именно писать код**.

## Содержание
1. [Карта пакета и инструменты](#1-карта-пакета-и-инструменты)
2. [Алгоритм эксперта: от запроса до сдачи](#2-алгоритм-эксперта-от-запроса-до-сдачи)
3. [Решения по умолчанию](#3-решения-по-умолчанию)
4. [Золотые правила](#4-золотые-правила)
5. [Скелеты: серверный скрипт, клиентский скрипт, модуль, класс](#5-скелеты)
6. [Формат ответа пользователю](#6-формат-ответа-пользователю)
7. [Плейбуки по типам запросов](#7-плейбуки-по-типам-запросов)
8. [Чек-лист самопроверки перед сдачей](#8-чек-лист-самопроверки-перед-сдачей)
9. [Правила для авторов этого пакета](#9-правила-для-авторов-этого-пакета)

---

## 1. Карта пакета и инструменты

| Что | Где | Зачем |
|---|---|---|
| Этот файл | `knowledge/00-START-HERE.md` | алгоритм, правила, скелеты, чек-лист |
| Маршрутизатор тем | [`knowledge/INDEX.md`](INDEX.md) | «задача → какие файлы читать» |
| Справочники по темам | `knowledge/01..18-*.md` | язык, типы, stdlib, API, сеть, данные, UI, физика, рецепты, ошибки |
| Процесс и безопасность | `handbook/`, `tracks/` | контракт агента, доказательность, релиз |
| API-справочник офлайн | `python3 tools/roblox_api.py Class.Member` | точная сигнатура, наследование, deprecated, описание |
| Проверка кода | `tools/check_code_blocks.py`, `.toolchain/luau-lsp` | настоящий typecheck против API Roblox |
| Поиск по базе | `python3 tools/search.py "запрос"` | ключевой поиск по всем документам |

### Установить тулчейн (один раз)
```bash
bash tools/setup_luau_toolchain.sh          # Linux/macOS -> ./.toolchain
# Windows: powershell -ExecutionPolicy Bypass -File tools\setup_luau_toolchain.ps1
```
Будут скачаны `luau` (запуск чистого Luau), `luau-analyze`, `luau-compile`, `luau-lsp` и
`globalTypes.d.luau` — определения типов всего Roblox Engine API.

### Проверить API, а не вспоминать
```bash
python3 tools/roblox_api.py Humanoid                  # класс, цепочка наследования, свои члены
python3 tools/roblox_api.py Humanoid --all            # плюс унаследованные
python3 tools/roblox_api.py Workspace.Raycast         # сигнатура + описание
python3 tools/roblox_api.py Humanoid.LoadAnimation    # покажет DEPRECATED -> Animator:LoadAnimation
python3 tools/roblox_api.py Enum.HumanoidStateType    # все значения enum
python3 tools/roblox_api.py CFrame.lookAt             # конструкторы datatype
python3 tools/roblox_api.py --find Shapecast          # поиск члена по подстроке
```
Правило: **любой класс или член, в котором ты не уверен на 100%, сначала проверь этой командой.** Если
член не найден, не выдумывай. Ищи через `--find`, смотри наследование или новую документацию.

### Проверить свой код перед сдачей
Сохрани каждый скрипт в `.luau` и прогони анализатор с типами Roblox:
```bash
.toolchain/luau-lsp analyze --definitions=.toolchain/globalTypes.d.luau --platform=roblox MyScript.server.luau
```
Для нескольких связанных скриптов удобнее собрать их в один `.md` с блоками ```` ```luau ```` и директивами
`-- @path ...` (см. раздел 9) и запустить `python3 tools/check_code_blocks.py путь/к/файлу.md --warnings`.
Тогда `require` между модулями тоже типизируется. Чистую логику без Roblox API можно ещё и **выполнить**:
`.toolchain/luau file.luau` (или блок с `-- @run`).

Typecheck — это **не** запуск в Studio. Он ловит опечатки в API, nil-доступы, неверные типы и устаревшие вызовы.
Он не ловит логику репликации, гонки и ошибки дизайна. Для этого есть чек-лист (раздел 8) и тест в Studio.

---

## 2. Алгоритм эксперта: от запроса до сдачи

Эксперт не начинает с кода. Он за 1–2 минуты мысленно проходит эти шаги (для больших задач выписывает их):

**Шаг 1. Что на самом деле нужно.** Переформулируй запрос как наблюдаемое поведение: «игрок нажимает E у
двери — дверь открывается у всех, закрывается через 3 с; спамить нельзя». Если запрос расплывчатый («сделай
симулятор»), сузь его до вертикального среза (один цикл геймплея целиком) и явно назови допущения.
Не задавай 10 уточняющих вопросов: прими разумные допущения и перечисли их.

**Шаг 2. Кто владеет каждым состоянием (authority).** Для каждого значения (деньги, HP, открыта ли дверь,
инвентарь, таймер раунда) реши, кто его меняет. Почти всегда это **сервер**. Клиент присылает только
*намерение* («хочу купить item X») и рисует *представление* (UI, эффекты, звук, камера).

**Шаг 3. Где живёт каждый кусок кода.** Разложи по местам (таблица в разделе 3):
серверная логика — `Script` в `ServerScriptService`; клиентская — `LocalScript` в `StarterPlayerScripts`
(или `StarterCharacterScripts`, если логика привязана к персонажу); общий код, конфиги и remotes —
`ReplicatedStorage`; серверные ассеты и шаблоны — `ServerStorage`.

**Шаг 4. Сетевой контракт.** Перечисли remotes: имя, направление, аргументы и их типы, частоту, что сервер
проверяет. Каждый `OnServerEvent` = недоверенный ввод (см. `09-networking-remotes-security.md`).

**Шаг 5. Жизненный цикл.** Что создаётся, когда уничтожается, что происходит при respawn, выходе игрока,
уничтожении объекта, перезапуске раунда, выключении сервера. Каждое `:Connect` имеет владельца, который
его отключит (или объект, чей `Destroy` его отключит).

**Шаг 6. Сверь API.** Все незнакомые или сомнительные классы и члены проверь через `tools/roblox_api.py`.
Особенно имена свойств, которые легко перепутать (`JumpPower`/`JumpHeight`+`UseJumpPower`,
`AssemblyLinearVelocity`, `FilterDescendantsInstances`, `ApplyDescriptionAsync`).

**Шаг 7. Напиши код.** Начни со скелетов из раздела 5. `--!strict`, сервисы через `GetService` наверху,
типизированные публичные функции, ранние `return` в валидации, без глобалов, без `wait()`.

**Шаг 8. Прогони чек-лист** (раздел 8) и **typecheck**. Исправь всё найденное. Не подавляй ошибки кастом в `any`.

**Шаг 9. Сдай результат** в формате раздела 6: где какой скрипт, полный код, настройка Studio, как проверить,
что не проверено.

---

## 3. Решения по умолчанию

### Где что лежит
| Что | Куда | Тип |
|---|---|---|
| Серверная логика, обработчики remotes, DataStore | `ServerScriptService` | `Script` (+ `ModuleScript` рядом) |
| Серверные модули, секреты, конфиги цен/дропов (сервер-only) | `ServerScriptService` или `ServerStorage` | `ModuleScript` |
| Шаблоны карт, NPC, предметов для клонирования сервером | `ServerStorage` | Model/Folder |
| Общие модули (типы, утилиты, конфиг предметов, который видит UI) | `ReplicatedStorage` | `ModuleScript` |
| RemoteEvent / RemoteFunction | `ReplicatedStorage/Remotes` (создаёт сервер или заранее в Studio) | Remote* |
| Клиентская логика (ввод, UI-контроллеры, камера, эффекты) | `StarterPlayer/StarterPlayerScripts` | `LocalScript` |
| Логика, привязанная к одному персонажу и умирающая с ним | `StarterPlayer/StarterCharacterScripts` | `LocalScript`/`Script` |
| UI, сделанный в Studio | `StarterGui` (копируется в `PlayerGui`) | ScreenGui |
| Загрузочный экран | `ReplicatedFirst` | `LocalScript` |
| Ассеты эффектов, которые клонирует клиент | `ReplicatedStorage/Assets` | — |

### Какой инструмент выбрать
| Задача | Используй | Не используй |
|---|---|---|
| Пауза | `task.wait(t)` | `wait()` |
| Запустить параллельно | `task.spawn(fn)` / `task.defer(fn)` | `spawn`, `coroutine.wrap` для fire-and-forget |
| Отложить | `task.delay(t, fn)` | `delay` |
| Каждый кадр (сервер/клиент) | `RunService.Heartbeat` (или `PostSimulation`) | `while true do wait() end` |
| Камера каждый кадр | `RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 1, fn)` | Heartbeat |
| Луч | `workspace:Raycast(origin, direction, params)` | `FindPartOnRay`, `Ray.new` |
| Области/хитбоксы | `workspace:GetPartBoundsInBox/InRadius/GetPartsInPart` + `OverlapParams` | `Region3`, спам `Touched` |
| Анимации | `humanoid:FindFirstChildOfClass("Animator"):LoadAnimation(anim)` (кэшировать track) | `Humanoid:LoadAnimation` |
| Двигать модель | `model:PivotTo(cf)` | `SetPrimaryPartCFrame` |
| Физические силы | `LinearVelocity`, `AlignPosition`, `AlignOrientation`, `VectorForce`, `ApplyImpulse` | `BodyVelocity`, `BodyPosition`, `BodyGyro` |
| Сохранения | `DataStore:UpdateAsync` + pcall + retry + session lock (или ProfileStore) | голый `SetAsync` при выходе |
| Реплицируемое маленькое состояние | атрибуты (`SetAttribute`) | десятки `IntValue` |
| Пометить объекты для системы | `CollectionService` теги | поиск по имени в workspace |
| Взаимодействие «нажми E» | `ProximityPrompt` | `Touched` + клавиша |
| Анимация свойств | `TweenService` | ручной цикл для каждой детали |
| Время для таймеров, синхронизированное | `workspace:GetServerTimeNow()` | `tick()` |
| Бенчмарк/кулдаун | `os.clock()` | `tick()` |
| Unix-время (дейлики) | `os.time()` / `DateTime.now()` | `tick()` |
| Случайность в системе | `Random.new()` (свой экземпляр) | глобальный `math.random` в важной логике |
| Чат | `TextChatService` | legacy `Chat` |
| Фильтрация текста игроков | `TextService:FilterStringAsync` | показывать сырой текст |

### Решения по архитектуре
- Маленькая фича: один `Script` + один `LocalScript` + общий модуль-конфиг. Фреймворк не нужен.
- Средняя и большая игра: одна точка входа на сторону (`Main.server`, `Main.client`), модули-сервисы с
  `Init/Start`, общие типы и конфиги в `ReplicatedStorage/Shared` (см. `14-architecture-patterns.md`).
- Состояние храни в одном месте (single source of truth) на сервере. Клиент получает копию (атрибуты или
  снимок через remote) и только отображает её.

---

## 4. Золотые правила

Сжатые знания эксперта. Каждое правило раскрыто в тематических файлах.

**Безопасность и authority**
1. Клиент враждебен. Любой `OnServerEvent`/`OnServerInvoke` может прийти с любыми аргументами, в любом
   количестве, в любой момент. Проверяй тип, конечность (`x == x` и `math.abs(x) ~= math.huge`), диапазон,
   права, состояние, дистанцию, кулдаун. Дешёвые проверки идут первыми.
2. Первый аргумент `OnServerEvent` — настоящий `Player`, его подставляет движок. Всё остальное — ложь, пока
   не доказано обратное. Никогда не принимай `player`, `userId`, цену, урон или количество из payload.
3. Деньги, урон, инвентарь, прогресс, награды, покупки меняет только сервер.
4. Никогда не вызывай `RemoteFunction:InvokeClient` на сервере в критическом пути: клиент может не ответить
   никогда. Для request/response с клиента используй `InvokeServer` (сервер отвечает) или пару RemoteEvent'ов.
5. Изменения клиента не реплицируются на сервер (кроме физики его персонажа и деталей, которыми он владеет,
   и анимаций на своём Animator). Это значит, что `Humanoid.Health = 0` на клиенте — только локальная иллюзия.

**Время и потоки**
6. `task.*` вместо `wait/spawn/delay`. `task.wait()` возвращает реально прошедшее время.
7. После **любого** yield (`task.wait`, `WaitForChild`, `...Async`, `:Wait()`) мир мог измениться: игрок вышел,
   персонаж умер, объект уничтожен, раунд закончился. Перепроверь всё, от чего зависит продолжение
   (`player.Parent`, `character.Parent`, токен поколения).
8. Все `...Async`-вызовы к сети (DataStore, Marketplace, Teleport, Http, Badge, `GetNameFromUserIdAsync`,
   `FilterStringAsync`) оборачивай в `pcall`: они **могут** упасть.
9. Кулдауны меряй временем (`os.clock()`), а не флагом с `task.wait`. Кулдаун — per-player или per-object,
   не один глобальный `debounce`.
10. Зависимое от времени движение умножай на `dt`. Сглаживание: `alpha = 1 - math.exp(-speed * dt)`.

**Инстансы и жизненный цикл**
11. `Instance.new(class)` → свойства → `Parent` **последним**. Никогда `Instance.new(class, parent)`.
12. На клиенте реплицируемые объекты могут ещё не существовать: используй `WaitForChild` (с кастом `:: Type`).
    На сервере объекты, положенные в Studio, уже есть к старту скриптов.
13. `PlayerAdded`: сначала подключи обработчик, потом пройди `Players:GetPlayers()` для уже вошедших.
    То же с `CharacterAdded` и `player.Character`.
14. Каждое соединение, созданное на время жизни чего-то (персонажа, раунда, UI-экрана), отключай, когда
    это что-то заканчивается. Таблицы с ключом `Player` чисти в `PlayerRemoving`.
15. `Destroy()` то, что создал и больше не нужно. `Debris:AddItem(obj, t)` или `task.delay(t, obj.Destroy, obj)`.
16. `ScreenGui.ResetOnSpawn = false` для UI, который не должен пересоздаваться при смерти (почти любой HUD).
    Меняй `PlayerGui`, а не `StarterGui`.
17. Не ищи игроков, предметы и объекты по `Name` из пользовательских данных. Данные игрока храни по `UserId`.

**Язык и типы**
18. `--!strict` в каждом новом файле. Payload remotes и данные из DataStore имеют тип `unknown`,
    пока ты их не проверил.
19. `FindFirstChild` возвращает `Instance?`. Проверь на nil и `IsA`, прежде чем обращаться к свойствам.
20. `a and b or c` ломается, если `b` может быть `false`/`nil`. Используй `if a then b else c`.
21. `#t` у таблицы с дырами не определён. `table.remove` в прямом цикле пропускает элементы: иди с конца.
22. Порядок `pairs`/обхода словаря не гарантирован. Для детерминизма сортируй ключи.
23. `table.clone` и `table.freeze` поверхностные.
24. Вызов метода через `:`. Точка вместо двоеточия даёт ошибку `Expected ':' not '.'` или неверный `self`.
25. Передавай функцию, а не результат её вызова: `:Connect(onTouched)`, а не `:Connect(onTouched())`.

**Данные и деньги**
26. Неудачная загрузка профиля ≠ новый пустой профиль. Не давай играть с дефолтами и не перезаписывай
    ими настоящие данные.
27. Функция-трансформер `UpdateAsync` не yield'ит и может быть вызвана несколько раз. Никаких побочных эффектов
    внутри.
28. `ProcessReceipt` идемпотентен: запиши `PurchaseId` в сохраняемые данные вместе с выдачей награды. Возвращай
    `PurchaseGranted` только после успешного сохранения, иначе `NotProcessedYet`.
29. `game:BindToClose` сохраняет всех параллельно с дедлайном.

**Производительность**
30. Одна петля `Heartbeat` на систему, а не по одной на каждый объект.
31. Визуальные эффекты и твины декора делай на клиенте. Сервер реплицирует состояние, а не каждый кадр анимации.
32. Декор: `Anchored = true`, `CanCollide/CanTouch/CanQuery = false`, если физика не нужна.
33. Не вызывай `GetDescendants()` каждый кадр. Кэшируй списки, обновляй по событиям (теги, ChildAdded).

**Сдача**
34. Каждый скрипт в ответе сопровождается типом (`Script`/`LocalScript`/`ModuleScript`) и точным местом.
35. Не пиши «протестировано», если не запускал. Разделяй: typecheck пройден / запущено в CLI / не проверено в Studio.
36. Не выдумывай asset ID, API и свойства. Если нужен ассет, используй плейсхолдер `rbxassetid://0` и скажи,
    что его нужно заменить.

---

## 5. Скелеты

Все скелеты проходят typecheck против Roblox API (`tools/check_code_blocks.py`).

### 5.1 Серверный скрипт (Script в ServerScriptService)
```luau
--!strict
-- @path ServerScriptService/Start/Example.server
-- Script, ServerScriptService. Server-authoritative example: one remote, validated, rate-limited.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Remotes: created by the server so clients can WaitForChild them.
local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
if not remotesFolder then
	local folder = Instance.new("Folder")
	folder.Name = "Remotes"
	folder.Parent = ReplicatedStorage
	remotesFolder = folder
end
assert(remotesFolder, "Remotes folder missing")

local requestAction = Instance.new("RemoteEvent")
requestAction.Name = "RequestAction"
requestAction.Parent = remotesFolder

local COOLDOWN = 0.5
local lastUse: { [Player]: number } = {}

local function isFiniteNumber(value: unknown): boolean
	return type(value) == "number" and value == value and math.abs(value) ~= math.huge
end

requestAction.OnServerEvent:Connect(function(player: Player, amount: unknown)
	-- 1) cheap checks first
	local now = os.clock()
	if now - (lastUse[player] or 0) < COOLDOWN then
		return
	end
	if not isFiniteNumber(amount) then
		return
	end
	local n = amount :: number
	if n < 1 or n > 10 or n % 1 ~= 0 then
		return
	end
	-- 2) state checks
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	-- 3) commit (no yield between the last check and the commit)
	lastUse[player] = now
	print(`{player.Name} performed action x{n}`)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	lastUse[player] = nil
end)
```

### 5.2 Клиентский скрипт (LocalScript в StarterPlayerScripts)
```luau
--!strict
-- @path StarterPlayer/StarterPlayerScripts/Start/Example.client
-- LocalScript, StarterPlayerScripts. Sends intent; the server decides.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local requestAction = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RequestAction") :: RemoteEvent

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessedEvent: boolean)
	if gameProcessedEvent then
		return -- the player is typing in chat / clicking a UI button
	end
	if input.KeyCode == Enum.KeyCode.E then
		requestAction:FireServer(1)
	end
end)

-- Per-character setup: runs for the current character and every respawn.
local function onCharacterAdded(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.Died:Connect(function()
		print(`{player.Name} died`)
	end)
	-- connections to the character's own instances die with the character (Destroy on respawn)
end

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
	task.spawn(onCharacterAdded, player.Character)
end
```

> `StarterPlayer/StarterPlayerScripts` в `@path` — это условность проверяльщика. В Studio положи LocalScript в
> `StarterPlayer → StarterPlayerScripts`.

### 5.3 Модуль-сервис с жизненным циклом
```luau
--!strict
-- @path ServerScriptService/Start/CurrencyService
-- ModuleScript. Owns the per-player coin balance on the server.
local Players = game:GetService("Players")

export type CurrencyService = {
	get: (player: Player) -> number,
	add: (player: Player, amount: number) -> (),
	trySpend: (player: Player, amount: number) -> boolean,
	start: () -> (),
}

local balances: { [Player]: number } = {}

local CurrencyService = {} :: CurrencyService

function CurrencyService.get(player: Player): number
	return balances[player] or 0
end

function CurrencyService.add(player: Player, amount: number)
	assert(amount >= 0 and amount == amount, "amount must be a non-negative number")
	balances[player] = CurrencyService.get(player) + amount
	player:SetAttribute("Coins", balances[player]) -- replicated read-only view for UI
end

function CurrencyService.trySpend(player: Player, amount: number): boolean
	local current = CurrencyService.get(player)
	if amount <= 0 or amount ~= amount or current < amount then
		return false
	end
	balances[player] = current - amount
	player:SetAttribute("Coins", balances[player])
	return true
end

function CurrencyService.start()
	Players.PlayerRemoving:Connect(function(player: Player)
		balances[player] = nil
	end)
end

return CurrencyService
```

### 5.4 Класс с очисткой
```luau
--!strict
-- @path ReplicatedStorage/Start/Spinner
-- ModuleScript. A typed class: one instance per spinning part; Destroy() releases everything.
local RunService = game:GetService("RunService")

local Spinner = {}
Spinner.__index = Spinner

type SpinnerFields = {
	_part: BasePart,
	_speed: number, -- radians per second
	_connection: RBXScriptConnection?,
}
export type Spinner = typeof(setmetatable({} :: SpinnerFields, Spinner))

function Spinner.new(part: BasePart, speed: number): Spinner
	local self = setmetatable({
		_part = part,
		_speed = speed,
		_connection = nil,
	} :: SpinnerFields, Spinner)
	self._connection = RunService.Heartbeat:Connect(function(dt: number)
		self._part.CFrame *= CFrame.Angles(0, self._speed * dt, 0)
	end)
	return self
end

function Spinner.setSpeed(self: Spinner, speed: number)
	self._speed = speed
end

function Spinner.Destroy(self: Spinner)
	if self._connection then
		self._connection:Disconnect()
		self._connection = nil
	end
end

return Spinner
```

### 5.5 Использование модуля из скрипта
```luau
--!strict
-- @path ServerScriptService/Start/UseModules.server
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CurrencyService = require(ServerScriptService.Start.CurrencyService)
local Spinner = require(ReplicatedStorage.Start.Spinner)

CurrencyService.start()

local part = Instance.new("Part")
part.Anchored = true
part.Size = Vector3.new(2, 2, 2)
part.Position = Vector3.new(0, 5, 0)
part.Parent = workspace

local spinner = Spinner.new(part, math.pi)
task.delay(10, function()
	spinner:Destroy()
	part:Destroy()
end)
```

---

## 6. Формат ответа пользователю

Хороший ответ на задачу «сделай X в Roblox» содержит:

1. **Кратко: как это работает.** 2–5 предложений: кто что решает (сервер или клиент), какие remotes, какие теги
   и атрибуты.
2. **Структуру** в виде дерева:
   ```text
   ServerScriptService
     └─ DoorService (Script)
   ReplicatedStorage
     └─ Remotes (Folder)          -- создаётся сервером автоматически
   StarterPlayer/StarterPlayerScripts
     └─ DoorClient (LocalScript)
   Workspace
     └─ Door (Model, tag "Door", attribute OpenAngle = 90)
   ```
3. **Полный код каждого скрипта.** Без `...` и без «остальное допишите сами». Над каждым блоком тип и место.
4. **Настройку в Studio:** какие объекты создать, какие теги и атрибуты поставить, какие настройки включить
   (например, Game Settings → Security → Enable Studio Access to API Services для DataStore).
5. **Проверку:** как протестировать (Play; Test → Clients and Servers на 2 игрока; что должно произойти).
6. **Ограничения:** что не проверено (например, «typecheck пройден, в Studio не запускалось»), какие ассеты заменить,
   что стоит сделать дальше.

Для **исправления бага** отвечай так: причина (с цитатой строки), исправленный фрагмент или файл, почему теперь
работает, как проверить. Для **ревью кода**: список проблем по убыванию серьёзности (безопасность → потеря данных →
баги → утечки → производительность → стиль), к каждой проблеме исправление.

Пиши на языке пользователя. API, имена классов и свойств не переводи.

---

## 7. Плейбуки по типам запросов

### «Сделай систему/механику X»
1. Найди близкий рецепт в `15-gameplay-cookbook.md` и тематическом файле (`INDEX.md`).
2. Пройди шаги 1–5 алгоритма (authority, места, remotes, жизненный цикл).
3. Возьми скелеты, адаптируй рецепт. Не копируй вслепую, подгони под проект пользователя: его имена папок,
   его remotes, его стиль.
4. Typecheck → чек-лист → ответ по формату.

### «Сделай игру как Y» (симулятор, tycoon, obby, tower defense, PvP-арена)
Нельзя сделать всю игру одним ответом, и не надо притворяться, что сделал. Выдели **core loop** (например,
симулятор: кликнуть → получить валюту → купить улучшение → кликать быстрее → сохранить прогресс) и сделай
вертикальный срез: данные (профиль), экономика на сервере, UI, одна механика, сохранение. Затем перечисли
следующие шаги. Стартовая архитектура из `14-architecture-patterns.md`, данные из `10-data-persistence-monetization.md`.

### «Почини мой скрипт» / «не работает»
1. Прочитай весь код. Определи host: где лежит скрипт, это Script или LocalScript, какой у него RunContext.
   Половина багов — не тот тип скрипта или не то место (LocalScript в Workspace не запускается).
2. Сопоставь симптом с `16-pitfalls-debugging-migration.md` (словарь ошибок Output).
3. Типовые причины: nil после yield; `WaitForChild` на неверном имени; клиент меняет то, что должен менять сервер;
   `ResetOnSpawn`; забытые уже вошедшие игроки; `Touched` спамит; debounce общий; точка вместо двоеточия.
4. Исправь минимально, объясни причину, покажи, как проверить.

### «Отрефактори / модернизируй старый код»
Сначала безопасность: бэкдоры (`require(<число>)`, `getfenv`, `loadstring`, обфускация, `HttpService` на
неизвестные URL). Затем таблица замен deprecated → modern (`16-...`, `reference/modernization-matrix.md`). Меняй
по одному шагу, сохраняя поведение.

### «Оптимизируй»
Сначала измерение (MicroProfiler, Developer Console → Scripts/Memory/Network). Потом правки по убыванию эффекта
(`17-performance.md`). Не обещай «+N FPS» без замера.

### «Сделай красиво» (графика, свет, эффекты)
`13-effects-tween-audio-lighting.md` + `handbook/20-22`, `tracks/graphics.md`. Визуальные эффекты делай на клиенте.
Предлагай пресеты как стартовую точку для арт-дирекции, а не как гарантию.

---

## 8. Чек-лист самопроверки перед сдачей

Пройди **каждый** пункт. Эксперт отличается от новичка не знанием синтаксиса, а тем, что проверяет это всегда.

**Размещение и запуск**
- [ ] У каждого скрипта указаны тип и место; LocalScript лежит там, где он реально запускается.
- [ ] Серверные модули не `require`'ятся с клиента; секреты и цены для валидации лежат на сервере.
- [ ] Клиент ждёт реплицируемые объекты через `WaitForChild`; сервер не ждёт то, что создаёт сам.

**Безопасность**
- [ ] Каждый `OnServerEvent`/`OnServerInvoke` проверяет типы, NaN/inf, диапазоны, права, состояние, дистанцию, частоту.
- [ ] Никаких цен, урона, количеств, userId от клиента, которым сервер верит.
- [ ] Нет `InvokeClient` в критическом пути сервера.
- [ ] Текст от игроков, который видят другие, фильтруется.

**Жизненный цикл**
- [ ] `PlayerAdded` обрабатывает и уже вошедших; `CharacterAdded` обрабатывает текущего персонажа.
- [ ] Состояние per-player чистится в `PlayerRemoving`.
- [ ] Соединения на время жизни (персонаж, раунд, UI) отключаются; созданные инстансы уничтожаются.
- [ ] После каждого yield перепроверено, что игрок, персонаж и объект ещё существуют.
- [ ] Нет бесконечных `while true do` без `task.wait`; нет неограниченно растущих таблиц и очередей.
- [ ] UI: `ResetOnSpawn` выставлен осознанно; изменяется `PlayerGui`, не `StarterGui`.

**Корректность**
- [ ] Нет `wait/spawn/delay`, `Humanoid:LoadAnimation`, `FindPartOnRay`, Body*-movers, `SetPrimaryPartCFrame`.
- [ ] Все `...Async` в `pcall`, с понятным поведением при ошибке.
- [ ] Debounce/кулдаун per-player или per-object, по времени.
- [ ] `Touched`: фильтр по `Humanoid`/игроку, защита от многократного срабатывания.
- [ ] Движение и анимация кода зависят от `dt`, а не от FPS.
- [ ] Нет `a and b or c` с возможным false/nil `b`; nil-проверки после `FindFirstChild`.

**Данные**
- [ ] Ключи сохранений по `UserId`; `UpdateAsync` без yield внутри; неудачная загрузка не превращается в пустой профиль.
- [ ] Покупки идемпотентны; `BindToClose` сохраняет всех.

**Качество**
- [ ] `--!strict`, typecheck пройден (`luau-lsp analyze` с определениями Roblox), нет `:: any` для подавления ошибок.
- [ ] Имена говорят о смысле; магические числа вынесены в константы/конфиг.
- [ ] В ответе есть настройка Studio, план проверки и честный статус проверки.

---

## 9. Правила для авторов этого пакета

Все файлы `knowledge/*.md` проверяются командой `python3 tools/check_code_blocks.py` (CI делает то же самое):

- ```` ```luau ```` — полноценный код. Typecheck через luau-lsp против API Roblox. Ошибки типов и **использование
  deprecated API** — FAIL. В таких блоках только рекомендуемый код.
- ```` ```lua ```` — фрагменты и «плохие» примеры: проверяется только синтаксис.
- `-- @path Service/Folder/Name(.server|.client)` — блок кладётся в виртуальное дерево Rojo. `require` между
  блоками и файлами резолвится и типизируется. Пути глобальны для всех файлов: используй папку своей темы.
- `-- @run` — чистый Luau, блок **исполняется** CLI `luau`. Утверждения о семантике доказываются `assert`.

Пример доказанной семантики:
```luau
--!strict
-- @run
assert(7 // 2 == 3 and -7 // 2 == -4)            -- floor division rounds toward -inf
assert(-7 % 3 == 2)                              -- result has the sign of the divisor
local t = { 1, 2, 3, 4 }
for i = #t, 1, -1 do                             -- remove while iterating: go backwards
	if t[i] % 2 == 0 then
		table.remove(t, i)
	end
end
assert(#t == 2 and t[1] == 1 and t[2] == 3)
local value = false
local picked = if value == false then "is false" else "other"
assert(picked == "is false")
assert((true and false or "fallback") == "fallback") -- the `a and b or c` trap
```
