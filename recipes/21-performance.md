# Повторяемый performance pass

Маршрут: [tracks/performance](../tracks/performance.md).

## Постановка
Один сценарий и явно выбранное устройство, baseline commit и thresholds проекта.

## Реализация
Собери реальные frame samples и profiler dump. Выбери dominant task и меняй одну гипотезу. Сохрани raw data; повтори A/B и correctness checks. Сравни CPU/GPU/allocations в измеряемой форме, не складывай несопоставимые метрики.

## Приёмка
Несколько повторов, cold/warm состояния, NPC/action burst, low target device, tail spikes и память после cleanup.

## Что не делать
Не использовать только лучший прогон. Не заявлять universal FPS gain из инстанс-статистики.

## Сдача
Файлы и setup, точные использованные API/источники, реальные тесты и screenshots/profiler по необходимости. NOT RUN для отсутствующего evidence.
