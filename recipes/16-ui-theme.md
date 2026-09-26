# Native theme и adaptive UI

Маршрут: [tracks/ui-input](../tracks/ui-input.md).

## Постановка
Один ScreenGui с владельцем theme и явными style tokens.

## Реализация
Проверь supported StyleRule selector/property, не генерируй CSS наугад. Раздели layout и theme. UI sizing зависит от контента/экрана; большой русский текст и локализация входят в тест. Input focus и модальные действия имеют priority.

## Приёмка
Размеры экрана/ориентации, длинный текст, gamepad navigation, touch targets, menu open/close, respawn.

## Что не делать
Не переписывать весь UI для использования нового API без измеримой задачи. Исключить конфликты двух StyleLink owners.

## Сдача
Файлы и setup, точные использованные API/источники, реальные тесты и screenshots/profiler по необходимости. NOT RUN для отсутствующего evidence.
