# Проверенные источники

Ниже — источники, открытые при подготовке. Полные тела страниц не включены. Авторские заметки не являются дословными выдержками.

## [L01] Luau syntax

https://luau.org/syntax/

Синтаксис, continue, выражения if, интерполяция, обобщённая итерация, const. Наличие в документации языка не заменяет проверку версии Studio.

## [L02] Luau type checking

https://luau.org/types/

Структурная постепенная типизация; strict; статическое приведение не является проверкой входных данных.

## [L03] Basic types

https://luau.org/types/basic-types/

any, unknown, never, примитивы, singleton-типы, variadic packs.

## [L04] Table types

https://luau.org/types/tables/

Sealed/unsealed/generic — состояния типизации таблицы, а не runtime-заморозка.

## [L05] Unions and intersections

https://luau.org/types/unions-and-intersections/

Tagged unions, объединения и пересечения типов.

## [L06] Generics

https://luau.org/types/generics/

Параметры типов и явная инстанциация через <<...>>; проверять поддержку конкретным компилятором.

## [L07] Type refinements

https://luau.org/types/type-refinements/

Сужение типов по условиям, type, равенству и assert.

## [L08] OOP typing

https://luau.org/types/object-oriented-programs/

Метатаблицы, методы, self и необходимость явных аннотаций.

## [L09] Type functions

https://luau.org/types/type-functions/

Функции времени анализа типов; не обычная игровая логика.

## [L10] Standard library

https://luau.org/library/

Стандартная библиотека языка отделена от объектов Roblox и функций встраивающей среды.

## [L11] Luau performance

https://luau.org/performance/

Оптимизации языка и компилятора; улучшение микротеста не доказывает улучшение FPS.

## [L12] Luau attributes

https://luau.org/attributes/

Атрибуты функций — отдельная языковая возможность; не путать с Instance Attributes.

## [R00] Roblox AI documentation index

https://create.roblox.com/docs/llms.txt

Видимый индекс: 2279 страниц; дата в документе 2026-09-25T18:51:47Z. Индекс не равен локально скачанному корпусу.

## [R01] Script types and locations

https://create.roblox.com/docs/scripting/locations

Script определяется RunContext и местом; LocalScript не запускается в ReplicatedStorage.

## [R02] Client-server runtime

https://create.roblox.com/docs/projects/client-server

Сервер и клиенты имеют отдельное состояние; Workspace клиента может быть неполным.

## [R03] Remote events and callbacks

https://create.roblox.com/docs/scripting/events/remote

RemoteEvent, RemoteFunction, UnreliableRemoteEvent имеют разные гарантии и режимы вызова.

## [R04] Client-server security boundary

https://create.roblox.com/docs/scripting/security/client-server-boundary

Проверять тип, размер, диапазон, finite-числа, права и частоту действий на сервере.

## [R05] Network ownership security

https://create.roblox.com/docs/scripting/security/network-ownership

Физика клиента не доказывает законность игрового действия.

## [R06] Third-party asset vulnerabilities

https://create.roblox.com/docs/scripting/security/third-party-vulnerabilities

Ассеты и плагины требуют ревью кода и происхождения; визуально безобидный объект может содержать скрипты.

## [R07] Task scheduler

https://create.roblox.com/docs/scripting/scheduler

task.spawn запускает сразу через scheduler; task.defer откладывает. Автозамена старого spawn может изменить порядок.

## [R08] Parallel Luau

https://create.roblox.com/docs/scripting/multithreading

Actors, сериализация/параллельные фазы, разрешения API, require до desynchronize.

## [R09] Deferred events

https://create.roblox.com/docs/scripting/events/deferred

Нельзя полагаться на немедленный callback после изменения свойства; lifecycle должен учитывать очередь событий.

## [R10] Instance streaming

https://create.roblox.com/docs/workspace/streaming

Объекты могут отсутствовать или выгружаться на клиенте; ожидание не создаёт гарантию существования.

## [R11] Server authority

https://create.roblox.com/docs/projects/server-authority

AuthorityMode.Server, фиксированная симуляция, Input Actions, prediction/rollback; отдельный путь архитектуры.

## [R12] Input Action System

https://create.roblox.com/docs/input/input-action-system

InputContext, InputAction, InputBinding; действия отделены от устройств и контекстов UI.

## [R13] Audio objects

https://create.roblox.com/docs/audio/objects

Современный аудиограф: AudioPlayer, Wire, emitter/listener, output. Sound не единственная модель аудио.

## [R14] UI styling

https://create.roblox.com/docs/ui/styling

StyleSheet, StyleRule, StyleLink, tokens/themes; не обещать полную совместимость с CSS.

## [R15] Global lighting

https://create.roblox.com/docs/environment/lighting

LightingStyle Realistic/Soft; PrioritizeLightingQuality; разница яркости источника и общей экспозиции.

## [R16] Lighting API

https://create.roblox.com/docs/reference/engine/classes/Lighting

Проверять теги, security и capabilities по точному member; Technology помечена deprecated.

## [R17] Materials

https://create.roblox.com/docs/parts/materials

MaterialVariant — повторяемый материал; SurfaceAppearance — UV-развёртка конкретного меша.

## [R18] PBR textures

https://create.roblox.com/docs/art/modeling/surface-appearance

Color/normal/roughness/metalness/emissive; OpenGL tangent-space normals; alpha modes и runtime-ограничения.

## [R19] Post-processing

https://create.roblox.com/docs/environment/post-processing-effects

Постобработка — presentation-слой, не замена геометрии и света; эффекты возможны в Lighting/Camera.

## [R20] Improve performance

https://create.roblox.com/docs/performance-optimization/improve

Измерять draw calls, плотность, уникальные меши и материалы, прозрачность, сложность и память.

## [R21] Data stores

https://create.roblox.com/docs/cloud-services/data-stores

UpdateAsync не разрешает yielding в transform; конкуренция, ошибки, metadata и cache важны.

## [R22] Player data and purchasing

https://create.roblox.com/docs/cloud-services/data-stores/player-data-purchasing

Сериализация запросов по ключу, session locking, атомарность награды и записи. Сам официальный sample требует тестов.

## [R23] Data store best practices

https://create.roblox.com/docs/cloud-services/data-stores/best-practices

Бюджеты, надёжность, тестирование и наблюдаемость хранения.

## [R24] SLIM

https://create.roblox.com/docs/workspace/streaming/slim

Облачное создание LOD; требования streaming/publishing/Team Create; ограничения динамики и аватаров.

## [R25] Pathfinding

https://create.roblox.com/docs/characters/pathfinding

Параметры агента, ComputeAsync, статус маршрута, waypoints, blocked и replanning.

## [R26] Animations

https://create.roblox.com/docs/animation/using

Animator и AnimationTrack, размещение/права, репликация и жизненный цикл.

## [R27] Raycasting

https://create.roblox.com/docs/workspace/raycasting

Направление луча содержит длину; фильтры и частичный мир клиента влияют на результат.

## [R28] Physics network ownership

https://create.roblox.com/docs/physics/network-ownership

Сетевой владелец считает физику; серверная валидация всё равно нужна.

## [R29] Native code generation

https://create.roblox.com/docs/luau/native-code-gen

Выбирать вычислительные hot paths после профиля; это не настройка графики.

## [G01] Creator documentation repository

https://github.com/Roblox/creator-docs

README прочитан через GitHub; guides/tutorials/API YAML; проза CC BY 4.0, samples MIT.

## [G02] Luau documentation repository

https://github.com/luau-lang/site

Официальные исходники сайта Luau. Лицензия MIT; pin зафиксирован отдельно.

## [G03] Luau implementation

https://github.com/luau-lang/luau

Официальный compiler/runtime/analyzer. Самостоятельный CLI не запускает Roblox Engine.

## [G04] Luau RFC process

https://github.com/luau-lang/rfcs

Merged RFC не означает включённую возможность в целевом движке. Полный репозиторий здесь не распространяется.
