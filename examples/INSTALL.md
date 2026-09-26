# Примеры: установка, зависимости и границы

**Все Luau-файлы — авторские reference examples. В этой сборке не запускались ни Luau compiler, ни Roblox Studio.** `--!strict` — запрос проверок, а не свидетельство их успешного выполнения. Никаких платных assets, скрытых requires, внешних HTTP calls или сохранений реальных профилей в этих примерах нет.

## Pure-модули
`examples/pure/*.luau` не обращаются к game/Instance/Roblox services. В Roblox создавай ModuleScript с соответствующим именем и вставляй выбранный код. В standalone Luau файлы могут использовать поддерживаемый этой версией filesystem require.

| Модуль | Назначение | Важная граница |
|---|---|---|
| FiniteNumbers | unknown → finite/ranged/integer | Не проверяет право игрока совершить действие |
| TokenBucket | Одна bounded rate bucket, явное время | Таблица buckets по игрокам и cleanup принадлежат вызывающему коду |
| Cleanup | Обратный порядок cleanup, idempotent destroy, список ошибок | Не знает, что выделил callback, который упал до регистрации cleanup |
| Generation | Инвалидация позднего результата | Не отменяет выполненную внешнюю запись |
| BoundedQueue | FIFO с пределом ёмкости | Переполнение возвращает false; nil зарезервирован |
| Result | Tagged success/failure, сохраняет false | Не runtime parser произвольной таблицы |
| Backoff | Расчёт full-jitter задержки | Не определяет безопасность повторной операции |
| ExponentialDamp | Frame-rate-aware scalar presentation | Не physics controller и не replay simulation |
| FrameStats | Bounded render intervals и nearest-rank percentiles | Не источник GPU/CPU timings |
| CombatState | Маленькая state machine | Нет hit detection, stamina, multiplayer или production rollback |
| Reachability | Bounded BFS по комнатам | Связность graph не доказывает физическую проходимость geometry |

Тестовый файл: `examples/tests/pure.spec.luau`, 16 групп assertions. Запуск в совместимом реальном Luau CLI:

```bash
luau examples/tests/pure.spec.luau
```

В Roblox такой файл нельзя механически запускать с относительными строковыми require: сначала адаптировать тестовый runner к реальным ModuleScript instances. Не заменять Luau обычным Lua 5.1 и не считать ошибки разного host доказательством неправильности языка.

## Демо безопасного взаимодействия
Используй отдельный пустой test place. Этот пример для обычной client/server архитектуры, не для BindToSimulation.

В `ServerScriptService` создай Folder `TKDemoServer`. Внутри размести `TokenBucket` как ModuleScript и `SecureInteract` как Script с RunContext Server. Скопируй соответствующие тела из пакета. В `ReplicatedStorage` размести `InteractAction` как Script с RunContext Client, **не LocalScript**. Не вставляй дубли в starter-контейнеры.

В Workspace создай обычный anchored BasePart, CanQuery=true, с тегом `InteractableDemo`. Поставь его перед персонажем, в пределах 12 studs от HumanoidRootPart. Наведи центр камеры и нажми E либо ButtonX. Сервер после проверок переключает boolean attribute `DemoActive`; визуальный цвет не меняется автоматически. В Output клиента появится подтверждение. Для наблюдения можно смотреть атрибут в server view.

Сервер создаёт `ReplicatedStorage/TKDemoRemotes/Interact`. Повторный entrypoint с таким remote — ошибка, не причина молча удалить чужой объект. Числа 12 studs, 4 burst, 2 запросов/сек и cooldown 0.5 — демонстрационная политика, не platform limits.

Что проверено логикой примера: payload type, membership/tag, anchored target, living character, finite delta и distance, range, rate, target cooldown, line-of-sight; между последними проверками и commit нет yield. Что НЕ решено: полноценная movement anti-cheat, latency compensation, inventory permissions, persistence, мобильный HUD, подменённые другие серверные scripts.

Перед использованием проверить два клиента, dead/respawn, цель за стеной, неподходящий Instance, nil/table/NaN payload, удаление цели до получения ack, spam, повторный запуск и остановку скрипта. Проверка расстояния по replicated character не исключает speed/fly exploits.

## Визуальные и инфраструктурные модули
`LightingBaseline.apply()` требует поддерживаемых LightingStyle/PrioritizeLightingQuality и подходящего host/capabilities. Выбери **одного** владельца конфигурации; он не сохраняет автоматически предыдущие значения, поэтому rollback place settings должен быть подготовлен отдельно. Это не законченный ultra preset.

`VisualLayer.new()` создаёт только собственные Bloom/ColorCorrection. Полученный объект имеет `.setReducedEffects(boolean)` и `.destroy()`. Не удаляет чужие эффекты. Числа — мягкий пример art direction; оценивать в своей сцене.

`StyleExample.mount(playerGui)` создаёт один ScreenGui с native style objects, возвращает cleanup. Проверить поддержку styling, иерархию и конфликт с существующим theme. `AudioGraph.connect2D(audioPlayer)` принимает уже настроенный и разрешённый AudioPlayer, создаёт output/wire и возвращает cleanup. Вызов Play/Stop и lifetime самого источника принадлежат тебе.

`FrameIntervals.client.luau` ставится как Script/Client рядом с ModuleScript `FrameStats` в ReplicatedStorage. Логирует **render intervals**, не GPU время. `SceneAudit.inspect(root)` — один read-only проход выбранного subtree, не per-frame сервис и не полный security audit.

`TaggedBinder.bind(tag, attach)` и `CharacterBinding.bind(player, attach)` возвращают release. Attach должен быть быстрым, non-yielding, возвращать функцию cleanup и сам очищать частично созданные ресурсы при ошибке. Для TaggedBinder фильтруй допустимый subtree внутри attach, если тег может находиться не только в Workspace.

## Feature probes
Четыре `feature-probes/` файла проверяют const, generic instantiation, attributes и новые math predicates. Они не должны автоматически запускаться при старте игры. Сначала отдельно parse/type/runtime в нужном host; затем решить, можно ли переносить конструкцию в проект. Никакие experimental exact-table/if-local варианты не приняты за baseline.
