# Binding к streaming-объектам

Маршрут: [tracks/world-streaming](../tracks/world-streaming.md).

## Постановка
Client effect/controller, который появляется и исчезает вместе с объектом мира.

## Реализация
Подпишись на tag add/remove до первоначального snapshot. Attach idempotent, ownership по instance identity. Return cleanup и освобождай connections/local effects. Async результат проверяет актуальную generation и ещё живой target. Не считать WaitForChild бессрочной гарантией.

## Приёмка
Объект появляется дважды в notification/snapshot, исчезает во время setup, возвращается с новой identity, игрок быстро меняет зоны.

## Что не делать
Одна global таблица всех когда-либо виденных объектов без eviction — утечка.

## Сдача
Файлы и setup, точные использованные API/источники, реальные тесты и screenshots/profiler по необходимости. NOT RUN для отсутствующего evidence.
