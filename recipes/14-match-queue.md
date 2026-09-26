# Очередь матчей

Маршрут: [tracks/persistence](../tracks/persistence.md).

## Постановка
Краткоживущие entries, explicit expiry и idempotent reservation. Persistent прогресс вне MemoryStore.

## Реализация
Определи matchmaking input, version, owner token и cancellation. Consume→reserve→teleport имеет восстановление после каждой фазы. Hot keys и quotas считаются на весь game. Попытки bounded, backoff с jitter. Stale entries истекают.

## Приёмка
Worker crash, queue repeat, expiration, player leaves, reservation duplicates, teleport partial success.

## Что не делать
Не хранить вечный баланс только в MemoryStore и не резервировать игрока навсегда.

## Сдача
Файлы и setup, точные использованные API/источники, реальные тесты и screenshots/profiler по необходимости. NOT RUN для отсутствующего evidence.
