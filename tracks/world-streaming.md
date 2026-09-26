# Большой мир и процедурные комнаты

## Порядок
- [11-streaming](../handbook/11-streaming.md)
- [13-physics](../handbook/13-physics.md)
- [17-npc-animation](../handbook/17-npc-animation.md)
- [23-geometry](../handbook/23-geometry.md)
- [26-performance](../handbook/26-performance.md)
- [27-quality-tiers](../handbook/27-quality-tiers.md)

## Решение задачи
Сначала граф связности, studs/grid и ownership объектов. Затем geometry validation, streaming lifecycle, LOD/SLIM prerequisites и NPC budgets.

## Критерий сдачи
Детерминированные seeds, отсутствие недостижимых mandatory rooms, streamed-out cleanup, профиль нагрузки.

## Исходные документы
R10, R24, R25, R27, R28 — точные URL в `../sources/registry.json`. Полные тела не считаются включёнными без upstream manifest.

## Расширенные разделы
- [34. Нативные ProceduralModel и безопасная генерация](../handbook/34-procedural-models.md)
- [35. Character Controller Library и выбор движения](../handbook/35-ccl.md)
- [45. CFrame, локальные оси, pivot и сетка](../handbook/45-transform-math.md)
