# Пользовательское имя или вывеска

Маршрут: [tracks/ui-input](../tracks/ui-input.md).

## Постановка
Ограниченная строка от реального автора, выбранная audience и безопасное состояние pending.

## Реализация
Проверь type/length/rate до фильтра. Получи current TextFilterResult и правильный broadcast/per-user output. Revision guard не даёт старому completion перезаписать новое имя. RichText escaping отдельно от moderation.

## Приёмка
Unicode, markup, filter failure, player leaving, repeated submissions, stale completion и audience change.

## Что не делать
Не показывать raw fallback. Не записывать лишний исходный user text в публичные логи.

## Сдача
Файлы и setup, точные использованные API/источники, реальные тесты и screenshots/profiler по необходимости. NOT RUN для отсутствующего evidence.
