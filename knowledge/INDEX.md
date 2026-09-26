# Слой знаний: маршрутизатор

Сначала всегда [00-START-HERE.md](00-START-HERE.md). Потом один–три файла по задаче. Не загружай всё сразу:
файлы большие, ищи нужный раздел по оглавлению в начале файла или через `python3 tools/search.py "тема"`.

## Файлы

| # | Файл | О чём |
|---|---|---|
| 00 | [00-START-HERE.md](00-START-HERE.md) | алгоритм эксперта, решения по умолчанию, золотые правила, скелеты, формат ответа, чек-лист |
| 01 | [01-luau-language.md](01-luau-language.md) | синтаксис и семантика Luau полностью: значения, операторы, таблицы, функции, метатаблицы, OOP, ошибки |
| 02 | [02-luau-types.md](02-luau-types.md) | система типов, `--!strict`, generics, refinements, типизация Roblox-инстансов, реальные сообщения анализатора |
| 03 | [03-luau-stdlib.md](03-luau-stdlib.md) | string (+ паттерны), utf8, table, math, bit32, buffer, vector, os, coroutine, debug, глобалы Roblox |
| 04 | [04-task-scheduler-events.md](04-task-scheduler-events.md) | yield, `task.*`, RunService, события и соединения, Signal, таймеры, debounce, гонки |
| 05 | [05-roblox-runtime-datamodel.md](05-roblox-runtime-datamodel.md) | сервисы, типы скриптов и RunContext, репликация, порядок загрузки, жизненный цикл игрока, streaming |
| 06 | [06-instances-attributes-tags.md](06-instances-attributes-tags.md) | создание и поиск инстансов, события, атрибуты, CollectionService, Model/Pivot, утечки |
| 07 | [07-datatypes-cframe-math.md](07-datatypes-cframe-math.md) | Vector3, CFrame (подробно), Color3, UDim2, sequences, Random, DateTime, игровая математика |
| 08 | [08-physics-raycast-movement.md](08-physics-raycast-movement.md) | Raycast/Shapecast/Overlap, collision groups, network ownership, constraints, снаряды, движение |
| 09 | [09-networking-remotes-security.md](09-networking-remotes-security.md) | RemoteEvent/Function/Unreliable, сериализация, валидация, rate limit, анти-эксплойт |
| 10 | [10-data-persistence-monetization.md](10-data-persistence-monetization.md) | DataStore, профили с session lock, лидерборды, MemoryStore, Messaging, покупки, геймпассы, бейджи |
| 11 | [11-characters-humanoid-animation.md](11-characters-humanoid-animation.md) | персонаж, Humanoid, урон, анимации, Tools, ragdoll, NPC и pathfinding |
| 12 | [12-ui-input-camera.md](12-ui-input-camera.md) | GUI, layout, твины UI, ввод на ПК, мобильных и геймпаде, камера |
| 13 | [13-effects-tween-audio-lighting.md](13-effects-tween-audio-lighting.md) | TweenService, частицы, beams, звук, освещение, пост-обработка |
| 14 | [14-architecture-patterns.md](14-architecture-patterns.md) | структура проекта, bootstrap, сервисы и контроллеры, классы, Trove, FSM, store, стиль кода |
| 15 | [15-gameplay-cookbook.md](15-gameplay-cookbook.md) | 20 готовых систем целиком: монеты, obby, двери, раунды, магазин, меч, оружие, инвентарь, питомцы, строительство |
| 16 | [16-pitfalls-debugging-migration.md](16-pitfalls-debugging-migration.md) | словарь ошибок Output, типичные баги агентов, отладка, миграция deprecated → modern |
| 17 | [17-performance.md](17-performance.md) | профилирование, Luau-оптимизации, движок, сеть, память, пулы, Parallel Luau |
| 18 | [18-tooling-testing.md](18-tooling-testing.md) | Rojo, Wally, selene, StyLua, luau-lsp, проверка кода пакета, тесты, CI |

## Задача → что читать

| Задача | Файлы |
|---|---|
| Любой новый скрипт | 00 → 05 → тематический |
| «Сделай механику/систему» | 00 → 15 (рецепт) → 09 (если есть remotes) → тематический |
| Магазин, валюта, покупки за Robux | 09 → 10 → 15 (#8) |
| Сохранение прогресса | 10 → 04 (ретраи, гонки) → `../handbook/14-persistence.md` |
| Боёвка, оружие, урон | 09 → 08 → 11 → 15 (#9, #10) |
| NPC, враги, pathfinding | 11 → 08 → 14 (FSM) |
| UI, HUD, меню | 12 → 13 (твины) → 14 (store) |
| Управление на мобилках и геймпаде | 12 |
| Камера, катсцены | 12 → 07 |
| Двери, лифты, платформы, движение объектов | 07 → 08 → 13 |
| Раунды, лобби, таймеры | 15 (#6) → 04 → 14 |
| Эффекты, звук, атмосфера | 13 → `../handbook/20-graphics-pipeline.md` |
| Архитектура большой игры | 14 → 05 → 18 |
| Лагает, утечки памяти | 17 → 04 → 06 |
| Ошибка в Output, «не работает» | 16 → 05 → тематический |
| Старый код, free model | 16 (миграция, бэкдоры) → `../reference/modernization-matrix.md` |
| Строки, паттерны, форматирование чисел и времени | 03 |
| Типы и ошибки анализатора | 02 |
| Математика, повороты, CFrame | 07 |
| Rojo, внешние редакторы, тесты | 18 |

## Проверенность
Каждый блок ```` ```luau ```` в этих файлах прошёл typecheck через `luau-lsp` против определений Roblox API, без
использования deprecated API. Блоки с `-- @run` выполнены Luau CLI. Команда: `python3 tools/check_code_blocks.py knowledge`.
Это статическая проверка и проверка чистой логики, **не** запуск в Roblox Studio. Поведение движка
(репликация, физика, тайминги) описано по документации и опыту; перед релизом проверяй в Studio.
