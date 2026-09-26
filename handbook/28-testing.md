# 28. Тестирование: от чистой функции до живого сервера

Срез проверки: **26 сентября 2026**. Это авторская рабочая методика, не полный перевод официальной страницы. Непроверенные в Studio рецепты требуют отдельного запуска.


## Лестница доказательств
Текстовая инспекция обнаруживает часть ошибок. Luau compiler подтверждает синтаксис конкретной версии. Анализатор с Roblox definitions проверяет часть контрактов API. Unit tests проверяют отдельные функции. Studio integration проверяет настоящие Instances. Два клиента проверяют authority/replication. Опубликованный тестовый place проверяет зависимые от облака возможности. Эти уровни нельзя сливать в одну галочку PASS.

## Авторская матрица
Pure tests: finite inputs, Result, cooldown, queue limits, state transitions, migration. Integration: bootstrap, lookup, tags, event lifecycle, camera ownership. Multi-client: remote злоупотребление, late join, respawn, simultaneity. Fault injection: timeout, permission denied, missing asset, throttling, unavailable profile. Visual: фиксированные камеры и видеомаршрут. Performance: повторяемый A/B и soak.

Assertions должны проверять поведение, а не строки Output. «Создано 1000 деталей» не доказывает отсутствие швов. «Функция вернула true» не доказывает сохранение при перезапуске. Имена тестов должны объяснять инвариант. Использовать reproducible seeds и сохранять failing fixtures.

## Отчёт
Для каждой команды: точная команда, окружение, exit status, log path, число tests, skipped и причина. Если Luau CLI отсутствует, запись SKIPPED, а не PASS. Если Studio недоступен, предоставить тестовый сценарий и назвать его непрогнанным. Пакет следует этому же правилу: Python-инструменты проверяются отдельно от Luau examples.

Release gate: нет data-loss blockers, авторитетное состояние не доверяет клиенту, нет unbounded tasks, visual review completed, есть backup/rollback. Принцип минимального релиза лучше сотни непроверенных feature-флагов.


## Первичные источники
- [L02] Luau type checking: https://luau.org/types/
- [G03] Luau implementation: https://github.com/luau-lang/luau
- [R02] Client-server runtime: https://create.roblox.com/docs/projects/client-server
- [R22] Player data and purchasing: https://create.roblox.com/docs/cloud-services/data-stores/player-data-purchasing
