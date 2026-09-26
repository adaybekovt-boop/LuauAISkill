# 13. Эффекты: Tween, частицы, звук, свет, пост-обработка

**Когда читать.** Перед любой задачей, где нужно что-то плавно подвинуть/перекрасить (двери, UI, платформы,
модели), показать попадание, взрыв, след, подсветку, проиграть звук или музыку, настроить освещение,
туман, день/ночь или пост-обработку. Документ отвечает на вопросы «где это должно выполняться (сервер или
клиент)», «что это стоит сети и GPU», «какие свойства реально существуют» и даёт готовые модули:
`TweenUtil`, `EffectPlayer` (пул VFX), сервер-триггер эффектов, playlist с кроссфейдом, шаги по материалу пола,
день/ночь, переходы освещения по зонам. Процессные правила графики/света/VFX/аудио — в
[../handbook/20-graphics-pipeline.md](../handbook/20-graphics-pipeline.md),
[../handbook/21-lighting.md](../handbook/21-lighting.md), [../handbook/25-particles.md](../handbook/25-particles.md),
[../handbook/19-audio.md](../handbook/19-audio.md); здесь — код и API.

## Оглавление

1. [Главное правило: визуал — на клиенте, состояние — на сервере](#1-главное-правило-визуал--на-клиенте-состояние--на-сервере)
2. [TweenService в глубину](#2-tweenservice-в-глубину)
3. [Твин моделей](#3-твин-моделей)
4. [Сервер или клиент: где твинить](#4-сервер-или-клиент-где-твинить)
5. [Своя интерполяция: GetValue, пружины, SmoothDamp](#5-своя-интерполяция-getvalue-пружины-smoothdamp)
6. [Визуальные эффекты: справочник классов](#6-визуальные-эффекты-справочник-классов)
7. [Система VFX: сервер-триггер + клиентский пул](#7-система-vfx-сервер-триггер--клиентский-пул)
8. [Hit feedback / «сочность»](#8-hit-feedback--сочность)
9. [Звук: Sound, SoundGroup, эффекты](#9-звук-sound-soundgroup-эффекты)
10. [Музыка с кроссфейдом, шаги, настройки громкости](#10-музыка-с-кроссфейдом-шаги-настройки-громкости)
11. [Новый Audio API: AudioPlayer, Wire, Emitter, Listener](#11-новый-audio-api-audioplayer-wire-emitter-listener)
12. [Освещение: Lighting, Atmosphere, Sky, Clouds](#12-освещение-lighting-atmosphere-sky-clouds)
13. [Пост-обработка](#13-пост-обработка)
14. [День/ночь и переходы освещения по зонам](#14-деньночь-и-переходы-освещения-по-зонам)
15. [Пресеты освещения](#15-пресеты-освещения)
16. [Бюджеты и производительность эффектов](#16-бюджеты-и-производительность-эффектов)
17. [Чек-лист](#чек-лист)
18. [Частые ошибки агентов](#частые-ошибки-агентов)

---

## 1. Главное правило: визуал — на клиенте, состояние — на сервере

Сервер владеет **фактом** (дверь открыта, игрок получил урон, взрыв произошёл в точке X). Клиент владеет
**представлением** (как дверь едет, какие искры летят, какой звук, как трясётся камера).

| Что | Где выполнять | Почему |
|---|---|---|
| Геймплейно значимое положение (дверь, блокирующая проход; движущаяся платформа, на которой стоят) | Сервер (или физика с `AlignPosition`/`PrismaticConstraint`) | Коллизия должна совпадать у всех, иначе клиент «проходит сквозь» дверь, которая у сервера закрыта |
| Декоративное движение (вращение монетки, пульсация, покачивание) | Клиент | Серверный твин шлёт обновление свойства по сети много раз в секунду и всё равно выглядит дёргано |
| Частицы, вспышки, тряска камеры, числа урона | Клиент | Только клиент видит экран; сервер эффекты не рисует |
| Звук одного игрока (UI-клик, hitmarker) | Клиент | Серверный `Sound:Play()` слышат все (если звук реплицирован) |
| Звук мира, который должны слышать все (взрыв) | Клиент каждого получателя по сигналу сервера, либо серверный `Sound` в Part | Сигнал — дёшево и гибко; серверный Sound — просто, но без per-client вариаций |
| Lighting/Atmosphere/ColorCorrection «у всех одинаково» | Сервер ставит **состояние** (атрибут/значение), клиент применяет с твином | Изменения Lighting на сервере реплицируются; частые изменения — постоянный трафик |
| Lighting по зоне игрока | Клиент | Каждый игрок в своей зоне |

Изменения, сделанные клиентом (LocalScript) в Workspace/Lighting, **не реплицируются** на сервер и другим
игрокам — это нормально и именно то, что нужно для эффектов.

---

## 2. TweenService в глубину

### 2.1 Минимум

```luau
--!strict
-- Script в Workspace/DoorModel (демо). Плавно меняет прозрачность и цвет части.
local TweenService = game:GetService("TweenService")

local part = Instance.new("Part")
part.Anchored = true
part.Size = Vector3.new(4, 1, 4)
part.Position = Vector3.new(0, 5, 0)
part.Parent = workspace

local info = TweenInfo.new(
	0.6, -- Time (секунды)
	Enum.EasingStyle.Quad, -- EasingStyle
	Enum.EasingDirection.Out, -- EasingDirection
	0, -- RepeatCount (0 = проиграть один раз, -1 = бесконечно)
	false, -- Reverses (вернуться к исходным значениям после каждого прохода)
	0 -- DelayTime (задержка перед стартом, секунды)
)

local tween = TweenService:Create(part, info, {
	Transparency = 0.5,
	Color = Color3.fromRGB(255, 80, 80),
	CFrame = part.CFrame * CFrame.new(0, 3, 0),
})
tween:Play()
```

### 2.2 TweenInfo: параметры и значения по умолчанию

`TweenInfo.new(time, easingStyle, easingDirection, repeatCount, reverses, delayTime)` — все аргументы
необязательны. Значения по умолчанию (по reference): `time = 1`, `EasingStyle.Quad`, `EasingDirection.Out`,
`repeatCount = 0`, `reverses = false`, `delayTime = 0`. Свойства `TweenInfo` **только для чтения** после
создания — чтобы «поменять длительность», создайте новый `TweenInfo` и новый `Tween`.

| Параметр | Смысл | Ловушки |
|---|---|---|
| `Time` | Длительность одного прохода | При `Reverses = true` полный цикл = `2 * Time` |
| `EasingStyle` | `Linear, Sine, Quad, Cubic, Quart, Quint, Exponential, Circular, Back, Elastic, Bounce` | `Back`/`Elastic` **выходят за целевое значение** (overshoot) — для Transparency это значения <0 или >1 (зажимаются движком), для Size — временно больше цели |
| `EasingDirection` | `In` (медленно→быстро), `Out` (быстро→медленно), `InOut` | Для UI-появления почти всегда `Out`; для исчезновения — `In` |
| `RepeatCount` | Сколько раз **повторить** после первого прохода. `-1` = бесконечно | `RepeatCount = 1` → проигрывается 2 раза. Бесконечный твин никогда не пошлёт `Completed` сам |
| `Reverses` | Вернуться к стартовым значениям | С `RepeatCount = -1` — классическое «пульсирование» |
| `DelayTime` | Задержка перед **каждым** стартом, включая повторы | Пока идёт задержка, `PlaybackState == Delayed`, и `Pause()` в этом состоянии не срабатывает |

Практичные наборы:

```luau
--!strict
-- @path ReplicatedStorage/Fx/TweenPresets
-- ModuleScript. Общие TweenInfo, чтобы не плодить магические числа по коду.
local TweenPresets = {
	UiIn = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	UiOut = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	Pop = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	Door = TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
	Pulse = TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
	Linear = TweenInfo.new(1, Enum.EasingStyle.Linear),
}

return table.freeze(TweenPresets)
```

### 2.3 Что можно твинить

Официальный список типов свойств, которые интерполирует `TweenService`: `number`, `boolean`, `CFrame`, `Rect`,
`Color3`, `UDim`, `UDim2`, `Vector2`, `Vector2int16`, `Vector3`, `EnumItem`.

- `boolean` и `EnumItem` **не интерполируются плавно** — промежуточных значений у них нет, значение
  переключается дискретно. Не полагайтесь на то, в какой именно момент твина это произойдёт: если важен момент
  (например, `CanCollide = false` в начале открытия двери), ставьте такое свойство вручную до/после твина.
- **Нельзя** твинить: `NumberSequence`, `ColorSequence`, `NumberRange` (например, `ParticleEmitter.Size`,
  `Beam.Transparency`), `string`, ссылки на Instance, `Content`. Для них — ручная интерполяция (раздел 5) или
  твин промежуточного `NumberValue`/`Color3Value` и перенос в `Changed`.
- Атрибуты (`SetAttribute`) твинить напрямую нельзя: твин работает по **свойствам** Instance. Твиньте
  `NumberValue`, а в `Changed` пишите атрибут — но чаще правильнее вообще не твинить реплицируемое значение.
- Имя свойства в таблице целей должно существовать и быть записываемым; опечатка = ошибка при `Create`.
  `Model` **не имеет** свойства `CFrame`/`Position` — `TweenService:Create(model, info, {CFrame = ...})` упадёт
  (см. раздел 3).
- Твинить `Position` у части, сваренной `WeldConstraint`, — сдвинет только её (сварка пересчитается); твинить
  `CFrame` — сдвинет всю сборку. Для анкерной (Anchored) детали и сборок — всегда `CFrame`.

### 2.4 Управление: Play / Pause / Cancel / PlaybackState / Completed

- `Play()` — старт; повторный `Play()` во время проигрывания ничего не делает. После `Completed`/`Cancel`/`Pause`
  — стартует снова (после `Cancel` — заново на полную длительность, от **текущих** значений).
- `Pause()` — останавливает, сохраняя прогресс; `Play()` продолжит. Работает только в состоянии `Playing`.
- `Cancel()` — останавливает и сбрасывает прогресс твина, **но не откатывает свойства**: деталь остаётся там,
  где её застал `Cancel`.
- `PlaybackState: Enum.PlaybackState` — `Begin, Delayed, Playing, Paused, Completed, Cancelled`.
- `Completed: RBXScriptSignal<Enum.PlaybackState>` — по reference срабатывает и при нормальном завершении, и при
  `Cancel()`. Всегда проверяйте аргумент, если логика зависит от того, дошёл ли твин до конца.
- **Конфликт:** если два твина меняют одно и то же свойство одного объекта, более ранний отменяется, и побеждает
  последний запущенный. Разные свойства одного объекта твинить параллельно можно.
- `Tween` — это Instance. Созданный и отработавший твин без ссылок собирается GC; держать в таблице тысячи
  твинов «на будущее» не нужно. Если храните твин в поле объекта — `Destroy()` при уничтожении владельца.

```lua
-- ПЛОХО: Completed:Wait() без таймаута. Если объект уничтожат, а твин отменит другой твин того же свойства,
-- или RepeatCount = -1 — поток может висеть вечно (или продолжит логику так, будто анимация дошла до конца).
tween:Play()
tween.Completed:Wait()
door:SetAttribute("Open", true)
```

Надёжное ожидание с таймаутом и проверкой результата:

```luau
--!strict
-- @path ReplicatedStorage/Fx/TweenUtil
-- ModuleScript. Утилиты для твинов: ожидание с таймаутом, твин с промисоподобным результатом.
local TweenService = game:GetService("TweenService")

local TweenUtil = {}

export type AwaitResult = "Completed" | "Cancelled" | "Timeout"

-- Ждёт окончания твина не дольше timeout секунд. Не запускает твин сам.
-- Возвращает, чем закончилось ожидание. Никогда не висит вечно.
function TweenUtil.await(tween: Tween, timeout: number?): AwaitResult
	local state = tween.PlaybackState
	if state == Enum.PlaybackState.Completed then
		return "Completed"
	elseif state == Enum.PlaybackState.Cancelled then
		return "Cancelled"
	end

	local limit = timeout or (tween.TweenInfo.Time + tween.TweenInfo.DelayTime + 1)
	local thread = coroutine.running()
	local finished = false
	local connection: RBXScriptConnection? = nil
	local timer: thread? = nil

	local function finish(result: AwaitResult)
		if finished then
			return
		end
		finished = true
		if connection then
			connection:Disconnect()
		end
		if timer and coroutine.status(timer) == "suspended" then
			task.cancel(timer)
		end
		task.spawn(thread, result)
	end

	connection = tween.Completed:Connect(function(playbackState: Enum.PlaybackState)
		finish(if playbackState == Enum.PlaybackState.Completed then "Completed" else "Cancelled")
	end)
	timer = task.delay(limit, function()
		finish("Timeout")
	end)

	local result: AwaitResult = coroutine.yield()
	return result
end

-- Создаёт, запускает и ждёт твин. Удобно в последовательных катсценах.
function TweenUtil.play(instance: Instance, info: TweenInfo, goals: { [string]: any }, timeout: number?): AwaitResult
	local tween = TweenService:Create(instance, info, goals)
	tween:Play()
	local result: AwaitResult = TweenUtil.await(tween, timeout)
	tween:Destroy()
	return result
end

-- Запускает твин без ожидания и уничтожает объект Tween по окончании.
function TweenUtil.fire(instance: Instance, info: TweenInfo, goals: { [string]: any }): Tween
	local tween = TweenService:Create(instance, info, goals)
	tween.Completed:Once(function()
		tween:Destroy()
	end)
	tween:Play()
	return tween
end

return TweenUtil
```

Почему `task.spawn(thread, result)`, а не `coroutine.resume`: `task.spawn` корректно возобновляет поток,
приостановленный через `coroutine.yield()` внутри движкового планировщика, и пробрасывает ошибки в Output, а не
глотает их.

### 2.5 Последовательности и отмена

Частая задача: «открыть дверь, подождать, закрыть; если во время открытия пришла новая команда — прервать».
Правило: у одного объекта — **один владелец анимации**, который хранит текущий твин и отменяет его перед новым.

```luau
--!strict
-- @path ReplicatedStorage/Fx/SingleTweenSlot
-- ModuleScript. Слот «не больше одного активного твина на объект»: новый твин отменяет прежний.
local TweenService = game:GetService("TweenService")

local SingleTweenSlot = {}
SingleTweenSlot.__index = SingleTweenSlot

export type SingleTweenSlot = typeof(setmetatable({} :: {
	_instance: Instance,
	_current: Tween?,
}, SingleTweenSlot))

function SingleTweenSlot.new(instance: Instance): SingleTweenSlot
	return setmetatable({ _instance = instance, _current = nil }, SingleTweenSlot)
end

function SingleTweenSlot.play(self: SingleTweenSlot, info: TweenInfo, goals: { [string]: any }): Tween
	local previous = self._current
	if previous then
		previous:Cancel()
		previous:Destroy()
	end
	local tween = TweenService:Create(self._instance, info, goals)
	self._current = tween
	tween.Completed:Once(function()
		if self._current == tween then
			self._current = nil
		end
	end)
	tween:Play()
	return tween
end

function SingleTweenSlot.destroy(self: SingleTweenSlot)
	local current = self._current
	if current then
		current:Cancel()
		current:Destroy()
		self._current = nil
	end
end

return SingleTweenSlot
```

---

## 3. Твин моделей

`Model` не имеет свойства `CFrame`. Два рабочих способа.

### 3.1 Способ A: твин `CFrameValue` + `PivotTo` в `Changed`

Работает для любой модели (анкерные части, без PrimaryPart, без сварок). Каждое изменение значения двигает все
части модели. Хорош на **клиенте**. На сервере каждое `PivotTo` меняет `CFrame` каждой части → репликация
каждой части каждый кадр (дорого для моделей из десятков частей).

```luau
--!strict
-- @path ReplicatedStorage/Fx/ModelTween
-- ModuleScript. Твин Model через промежуточный CFrameValue и PivotTo.
local TweenService = game:GetService("TweenService")

local ModelTween = {}

-- Плавно переносит модель в target. Возвращает Tween (уже запущен).
-- Временный CFrameValue уничтожается по окончании/отмене твина.
function ModelTween.pivotTo(model: Model, target: CFrame, info: TweenInfo): Tween
	local value = Instance.new("CFrameValue")
	value.Value = model:GetPivot()

	local changed = value.Changed:Connect(function(cf: CFrame)
		if model.Parent then
			model:PivotTo(cf)
		end
	end)

	local tween = TweenService:Create(value, info, { Value = target })
	tween.Completed:Once(function()
		changed:Disconnect()
		value:Destroy()
		tween:Destroy()
	end)
	tween:Play()
	return tween
end

return ModelTween
```

### 3.2 Способ B: анкерный PrimaryPart + сварка остальных частей

Все части кроме корня — **не анкерные**, сварены с корнем `WeldConstraint`; корень — анкерный. Твин `CFrame`
корня тащит всю сборку. Плюс: на сервере реплицируется **одна** деталь (остальные следуют за сваркой через
физическую сборку). Минус: требует правильной подготовки модели (Massless/CanCollide по вкусу), и все детали
должны быть сварены — иначе отвалятся и упадут.

```luau
--!strict
-- Script в ServerScriptService (демо): подготовка модели «лифт» к твину через PrimaryPart.
local TweenService = game:GetService("TweenService")

local function weldModelToRoot(model: Model): BasePart
	local root = model.PrimaryPart
	assert(root, `Model {model:GetFullName()} has no PrimaryPart`)
	root.Anchored = true
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant ~= root then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = descendant
			weld.Parent = descendant
			descendant.Anchored = false
		end
	end
	return root
end

local elevator = workspace:FindFirstChild("Elevator")
if elevator and elevator:IsA("Model") then
	local root = weldModelToRoot(elevator)
	local up = TweenService:Create(root, TweenInfo.new(4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, 1), {
		CFrame = root.CFrame * CFrame.new(0, 20, 0),
	})
	up:Play()
end
```

Замечания:

- Игроки на движущейся **анкерной** платформе, которую двигают через CFrame, не получают скорость платформы
  автоматически и могут «соскальзывать»/дёргаться. Для платформ, на которых стоят, надёжнее физика:
  не анкерная платформа + `AlignPosition`/`AlignOrientation` или `PrismaticConstraint` с `ActuatorType = Servo`.
- Выбор: способ A — клиентские декоративные модели; способ B — серверные двигающиеся конструкции из многих
  частей; физические констрейнты — всё, на чём стоят игроки.

---

## 4. Сервер или клиент: где твинить

Серверный твин реплицирует **каждое промежуточное значение свойства** (с частотой сетевых обновлений, а не
частотой кадров клиента). Итог: трафик пропорционален числу твинящихся объектов × свойства × длительность, а
клиент видит ступенчатое движение с интерполяцией сети (у анкерных частей интерполяции нет — рывки заметнее).

Паттерн «сервер меняет состояние, клиент анимирует»:

```luau
--!strict
-- @path ServerScriptService/Fx/DoorServer.server
-- Script. Сервер хранит только факт "открыта/закрыта" в атрибуте и переключает коллизию.
-- Каждая дверь: Model с тегом "Door", PrimaryPart "Panel", ProximityPrompt внутри Panel.
local CollectionService = game:GetService("CollectionService")

local function setupDoor(door: Instance)
	if not door:IsA("Model") then
		return
	end
	local panel = door.PrimaryPart
	if not panel then
		warn(`Door {door:GetFullName()} has no PrimaryPart`)
		return
	end
	local prompt = panel:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		return
	end
	door:SetAttribute("Open", door:GetAttribute("Open") == true)

	prompt.Triggered:Connect(function(_player: Player)
		local open = not (door:GetAttribute("Open") == true)
		door:SetAttribute("Open", open)
		-- Коллизию решает сервер: это геймплей, а не визуал.
		panel.CanCollide = not open
		prompt.ActionText = if open then "Close" else "Open"
	end)
end

CollectionService:GetInstanceAddedSignal("Door"):Connect(setupDoor)
for _, door in CollectionService:GetTagged("Door") do
	setupDoor(door)
end
```

```luau
--!strict
-- @path StarterPlayer/StarterPlayerScripts/Fx/DoorClient.client
-- LocalScript. Анимирует двери локально по атрибуту "Open". Панель на клиенте прозрачная/сдвинутая —
-- это только вид; коллизию уже поменял сервер.
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local OPEN_OFFSET = CFrame.new(0, 0, -5)
local INFO = TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

local connections: { [Instance]: RBXScriptConnection } = {}

local function bind(door: Instance)
	if not door:IsA("Model") or connections[door] then
		return
	end
	local panel = door.PrimaryPart
	if not panel then
		return -- при StreamingEnabled часть может ещё не прийти; см. knowledge по стримингу
	end
	local closedCFrame = panel.CFrame
	local current: Tween? = nil

	local function apply(instant: boolean)
		local goal = if door:GetAttribute("Open") == true then closedCFrame * OPEN_OFFSET else closedCFrame
		if current then
			current:Cancel()
		end
		if instant then
			panel.CFrame = goal
			return
		end
		local tween = TweenService:Create(panel, INFO, { CFrame = goal })
		current = tween
		tween:Play()
	end

	connections[door] = door:GetAttributeChangedSignal("Open"):Connect(function()
		apply(false)
	end)
	apply(true)
end

local function unbind(door: Instance)
	local connection = connections[door]
	if connection then
		connection:Disconnect()
		connections[door] = nil
	end
end

CollectionService:GetInstanceAddedSignal("Door"):Connect(bind)
CollectionService:GetInstanceRemovedSignal("Door"):Connect(unbind)
for _, door in CollectionService:GetTagged("Door") do
	bind(door)
end
```

Тонкость: клиент меняет `CFrame` анкерной панели, которой владеет сервер. Локальное изменение держится, пока
сервер не пришлёт новое значение этого свойства (сервер `CFrame` панели не трогает — значит, конфликта нет).
Если сервер **тоже** двигает ту же часть, клиентская анимация будет перезаписываться — выбирайте одного
владельца свойства.

| Сценарий | Решение |
|---|---|
| Декоративная анимация без геймплейного смысла | Только клиент, сервер ничего не знает |
| Состояние важно (дверь, мост), вид плавный | Сервер: атрибут + коллизия; клиент: твин |
| Движущаяся поверхность, на которой стоят | Физика (констрейнты) на сервере, не TweenService |
| UI | Только клиент |
| Быстрая однократная вспышка «для всех» | Сервер шлёт событие (RemoteEvent), клиенты рисуют |

---

## 5. Своя интерполяция: GetValue, пружины, SmoothDamp

### 5.1 `TweenService:GetValue(alpha, style, direction)`

Возвращает «изогнутую» альфу (0..1 на входе, зажимается) по кривой easing. Нужна, когда тип свойства не
твинится (`NumberSequence`, `ColorSequence`), когда интерполируете несколько объектов одной кривой, или когда
анимация управляется не временем, а, скажем, расстоянием.

```luau
--!strict
-- @path ReplicatedStorage/Fx/Interpolate
-- ModuleScript. Ручная интерполяция по кривым TweenService для нетвинящихся типов.
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Interpolate = {}

function Interpolate.numberSequence(a: NumberSequence, b: NumberSequence, t: number): NumberSequence
	-- Упрощение: интерполируем по ключам a; у b должно быть столько же ключей с теми же Time.
	local keysA, keysB = a.Keypoints, b.Keypoints
	assert(#keysA == #keysB, "NumberSequence keypoint count mismatch")
	local out = table.create(#keysA) :: { NumberSequenceKeypoint }
	for i, ka in keysA do
		local kb = keysB[i]
		out[i] = NumberSequenceKeypoint.new(ka.Time, ka.Value + (kb.Value - ka.Value) * t, ka.Envelope + (kb.Envelope - ka.Envelope) * t)
	end
	return NumberSequence.new(out)
end

-- Запускает анимацию на duration секунд, вызывая step(alpha) каждый кадр (alpha уже с easing).
-- Возвращает функцию отмены. Работает на клиенте (Heartbeat есть и на сервере, но см. раздел 4).
function Interpolate.run(duration: number, style: Enum.EasingStyle, direction: Enum.EasingDirection, step: (alpha: number) -> ()): () -> ()
	local elapsed = 0
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		local linear = math.min(elapsed / duration, 1)
		step(TweenService:GetValue(linear, style, direction))
		if linear >= 1 then
			connection:Disconnect()
		end
	end)
	return function()
		connection:Disconnect()
	end
end

return Interpolate
```

Пример: плавно «погасить» частицы, меняя `Transparency` (это `NumberSequence`, его не твинят):

```luau
--!strict
-- LocalScript (демо). Использует Interpolate для NumberSequence.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Interpolate = require(ReplicatedStorage.Fx.Interpolate)

local emitter = Instance.new("ParticleEmitter")
emitter.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(1, 0.5),
})
local from = emitter.Transparency
local to = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(1, 1),
})

local _cancel = Interpolate.run(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, function(alpha: number)
	emitter.Transparency = Interpolate.numberSequence(from, to, alpha)
end)
```

### 5.2 Пружина (spring): когда цель меняется постоянно

Твин плох, если цель меняется каждый кадр (камера следует за игроком, UI-полоска здоровья, «отдача» оружия):
каждый новый `Create` рвёт скорость, и движение дёргается. Пружина хранит **скорость** и плавно догоняет
подвижную цель. Критически задемпфированная пружина — без перелёта; недодемпфированная — «упругая».

```luau
--!strict
-- @path ReplicatedStorage/Fx/Spring
-- @run
-- ModuleScript. Пружина для number (полу-неявный Эйлер с субшагами — устойчива при больших dt).
local Spring = {}
Spring.__index = Spring

export type Spring = typeof(setmetatable({} :: {
	position: number,
	velocity: number,
	target: number,
	stiffness: number, -- «жёсткость», 1/с^2. 100..400 — бодро
	damping: number, -- коэффициент демпфирования; 2*sqrt(stiffness) = критическое
}, Spring))

function Spring.new(initial: number, stiffness: number?, dampingRatio: number?): Spring
	local k = stiffness or 170
	local ratio = dampingRatio or 1
	return setmetatable({
		position = initial,
		velocity = 0,
		target = initial,
		stiffness = k,
		damping = 2 * math.sqrt(k) * ratio,
	}, Spring)
end

function Spring.step(self: Spring, dt: number): number
	local steps = math.max(1, math.ceil(dt / (1 / 240)))
	local h = dt / steps
	for _ = 1, steps do
		local force = -self.stiffness * (self.position - self.target) - self.damping * self.velocity
		self.velocity += force * h
		self.position += self.velocity * h
	end
	return self.position
end

function Spring.impulse(self: Spring, velocity: number)
	self.velocity += velocity
end

-- Самопроверка (выполняется чекером): критическая пружина сходится к цели без заметного перелёта.
do
	local s = Spring.new(0, 200, 1)
	s.target = 10
	local maxSeen = 0
	for _ = 1, 120 do
		maxSeen = math.max(maxSeen, s:step(1 / 60))
	end
	assert(math.abs(s.position - 10) < 0.01, "critical spring must settle")
	assert(maxSeen < 10.05, "critical spring must not overshoot noticeably")

	local bouncy = Spring.new(0, 200, 0.3)
	bouncy.target = 10
	local peak = 0
	for _ = 1, 120 do
		peak = math.max(peak, bouncy:step(1 / 60))
	end
	assert(peak > 10.5, "underdamped spring overshoots")
end

return Spring
```

### 5.3 `TweenService:SmoothDamp`

В актуальных определениях есть `TweenService:SmoothDamp(current, target, velocity, smoothTime, maxSpeed?, dt?)
-> (newValue, newVelocity)` — критически задемпфированное сглаживание для `number`, `Vector2`, `Vector3`, `CFrame`.
Скорость нужно хранить и передавать в следующий вызов. Метод относительно новый: **проверь поддержку в целевой
Studio**; если его нет — используйте модуль `Spring` выше.

```luau
--!strict
-- LocalScript в StarterPlayerScripts (демо). Маркер плавно следует за мышью через SmoothDamp.
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local mouse = Players.LocalPlayer:GetMouse()
local marker = Instance.new("Part")
marker.Anchored = true
marker.CanCollide = false
marker.CanQuery = false
marker.Size = Vector3.one
marker.Parent = workspace

local velocity = Vector3.zero
RunService.RenderStepped:Connect(function(dt: number)
	local target = mouse.Hit.Position
	local newPosition, newVelocity = TweenService:SmoothDamp(marker.Position, target, velocity, 0.15, nil, dt)
	marker.Position = newPosition :: Vector3
	velocity = newVelocity :: Vector3
end)
```

---
