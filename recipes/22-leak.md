# Поиск утечки после respawn

Маршрут: [tracks/performance](../tracks/performance.md).

## Постановка
Повторяемый сценарий с ожидаемым возвращением ресурсов к bounded состоянию.

## Реализация
Сними Scene Analysis/heap baseline. Повтори respawn/UI/NPC cycles. Найди удерживающие references и неосвобождённые connections. Уменьшай проблему до одного owner и добавь teardown test. Учитывай осознанные asset caches.

## Приёмка
Сравнить после прогрева и после нескольких одинаковых циклов; destroy twice; callbacks after destroy; server/client отдельно.

## Что не делать
Unparented Instance не автоматически баг. Удаление содержимого Workspace ради падения памяти не является исправлением.

## Сдача
Файлы и setup, точные использованные API/источники, реальные тесты и screenshots/profiler по необходимости. NOT RUN для отсутствующего evidence.
