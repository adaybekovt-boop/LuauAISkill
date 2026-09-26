# Профиль с безопасным отказом

Маршрут: [tracks/persistence](../tracks/persistence.md).

## Постановка
Дизайн без production credentials: различать Loaded/New/Unavailable и владельца сессии.

## Реализация
Сначала profile schema и session/fencing strategy. Выстрой ordered writes и повторяемые transforms. Не выдавай inventory, пока доступ к данным не подтверждён. Протокол закрытия учитывает stop new work, flush deadline и неизвестный outcome записи.

## Приёмка
Load failure, throttling, disconnect before load, stale save, two servers, lease loss, old schema, shutdown under load.

## Что не делать
Здесь намеренно нет 30-строчного «готового DataStore wrapper», обещающего отсутствие потерь.

## Сдача
Файлы и setup, точные использованные API/источники, реальные тесты и screenshots/profiler по необходимости. NOT RUN для отсутствующего evidence.
