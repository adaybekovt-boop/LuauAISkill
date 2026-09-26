# Аудиограф и зоны окружения

Маршрут: [tracks/audio](../tracks/audio.md).

## Постановка
Лицензированный/разрешённый AudioPlayer и описанный путь source→effects→output или spatial routing.

## Реализация
Назначь владельца источника, wire и output. Раздели music/ambience/feedback buses. Ограничь одновременно активные sounds, плавно меняй параметры зоны и корректно останавливай ушедшие sources. Не захватывай voice/microphone без явных прав.

## Приёмка
Enter/leave/reenter zone, asset unavailable, two active zones, player respawn, cleanup, несколько audio devices/settings.

## Что не делать
Не считать legacy Sound удалённым. Поддержка modern graph не является разрешением на любое asset ID.

## Сдача
Файлы и setup, точные использованные API/источники, реальные тесты и screenshots/profiler по необходимости. NOT RUN для отсутствующего evidence.
