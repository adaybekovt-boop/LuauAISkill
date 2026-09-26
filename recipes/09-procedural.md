# Генератор с отменой и bounds

Маршрут: [tracks/world-streaming](../tracks/world-streaming.md).

## Постановка
Детерминированная функция параметров и ограниченный output. Для native ProceduralModel — актуальный OnGenerate contract.

## Реализация
Validate size/count/seed. Построй topology, проверь её, затем создавай геометрию в targetContainer вокруг origin. Пользуйся params:Pause для длинной работы. Не запускай внешние irreversible effects во время генерации. Ограничь максимальное количество частей и время.

## Приёмка
Rapid resize, cancellation, invalid size, huge count, same seed, undo/redo, save dirty→reopen.

## Что не делать
Не менять посторонний Workspace. Не помещать unsupported ProceduralModel generation в Actor.

## Сдача
Файлы и setup, точные использованные API/источники, реальные тесты и screenshots/profiler по необходимости. NOT RUN для отсутствующего evidence.
