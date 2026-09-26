# NPC с ограниченным pathfinding

Маршрут: [tracks/world-streaming](../tracks/world-streaming.md).

## Постановка
NPC с явными idle/seek/follow/repath/stuck/dead состояниями и budget на дорогие вычисления.

## Реализация
Планируй repath по событиям/изменению цели, а не каждый frame. Ограничь concurrent path requests, игнорируй stale results, проверяй blocked waypoint впереди агента. Раздели high-level intent и low-level movement. Учитывай rig dimensions, dynamic doors и ownership.

## Приёмка
Unreachable target, moving target, узкий проход, path result после death, десятки NPC одновременно, streaming transition.

## Что не делать
Нельзя маскировать stuck teleport-ом сквозь стены без игрового правила. Path graph success не гарантирует идеальное движение.

## Сдача
Файлы и setup, точные использованные API/источники, реальные тесты и screenshots/profiler по необходимости. NOT RUN для отсутствующего evidence.
