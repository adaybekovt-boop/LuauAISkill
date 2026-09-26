# Частицы без постоянной GPU-дымы

Маршрут: [tracks/graphics](../tracks/graphics.md).

## Постановка
Один эффект с lifetime, максимальной плотностью и правом быть выключенным на low tier.

## Реализация
Определи trigger и owner, выбери bounded burst вместо постоянной эмиссии там, где событие краткое. Ограничь screen coverage и перекрывающиеся прозрачные слои. Pool только после профиля и с reset всех изменяемых полей.

## Приёмка
Много simultaneous events, камера внутри эффекта, low quality, repeated reuse, delete target mid-effect, reduced effects.

## Что не делать
Part count не показывает overdraw. Pool не должен бесконечно расти и хранить старые event handlers.

## Сдача
Файлы и setup, точные использованные API/источники, реальные тесты и screenshots/profiler по необходимости. NOT RUN для отсутствующего evidence.
