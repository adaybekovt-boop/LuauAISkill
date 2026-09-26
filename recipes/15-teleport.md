# Переход в отдельный плейс

Маршрут: [tracks/persistence](../tracks/persistence.md).

## Постановка
Серверный state machine с проверкой прав destination и исправным failure UI.

## Реализация
Настрой access controls и TeleportAsync. Сохраняй только доверенные серверные данные, не разрешай client выбирать любое placeId. Обработай failure/retry без зависшего UI. Session handoff не должен создавать параллельных писателей одного профиля.

## Приёмка
Опубликованный test client: invalid target, blocked destination, повтор кнопки, reconnect, late failure, group partial success.

## Что не делать
Studio mock не является реальным успешным teleport. Secret reserved access не публикуется клиентам без необходимости.

## Сдача
Файлы и setup, точные использованные API/источники, реальные тесты и screenshots/profiler по необходимости. NOT RUN для отсутствующего evidence.
