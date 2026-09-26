# 05. Script, LocalScript, ModuleScript и RunContext

Срез проверки: **26 сентября 2026**. Это авторская рабочая методика, не полный перевод официальной страницы. Непроверенные в Studio рецепты требуют отдельного запуска.


## Размещение — часть программы
Перед переносом файла проверить тип Instance, RunContext, контейнер и момент создания. Script не всегда server-only: его режим влияет на выполнение. LocalScript не запускается в любом произвольном месте. ModuleScript запускается через require в среде вызывающего кода; сервер и клиенты не разделяют его Lua-таблицу автоматически.

Современный документ Roblox предлагает server entrypoint в ServerScriptService и client Script с RunContext Client в ReplicatedStorage. Существующая структура с LocalScript в StarterPlayerScripts также поддерживается; мигрировать её только при понятной причине. Не переносить Client Script в starter-контейнер без анализа клонирования: можно получить два запуска.

## Рабочая структура
Shared содержит DTO, чистую математику, общие определения и клиент-доступную конфигурацию. Server содержит authoritative state, persistence и секреты. Client содержит камеру, UI, локальные эффекты и обработку ввода. Assets — подготовленные объекты; Tests — отдельно от runtime. Каждый entrypoint вызывает bootstrap один раз, сначала init всех зависимостей, затем start, а teardown идёт в обратном порядке.

## Проблемы и диагностика
«Ничего не происходит» — проверить Enabled/Disabled, location, RunContext и Output соответствующей стороны. «Событие срабатывает дважды» — проверить дублирование entrypoints, копию в PlayerScripts и второй Connect. «На сервере nil» — возможно код предполагает LocalPlayer. «Секрет виден клиенту» — он попал в ReplicatedStorage или атрибут реплицируемого объекта.

Нельзя размещать ServerScript в ServerStorage и ждать обычного автоматического запуска. Нельзя считать имя папки Server доказательством конфиденциальности, если папка лежит в реплицируемом контейнере. Файловый путь на диске не доказывает Instance path после импортера или синхронизации: итоговую иерархию нужно осмотреть.


## Первичные источники
- [R01] Script types and locations: https://create.roblox.com/docs/scripting/locations
- [R02] Client-server runtime: https://create.roblox.com/docs/projects/client-server
- [R10] Instance streaming: https://create.roblox.com/docs/workspace/streaming
