# Идемпотентный grant покупки

Маршрут: [tracks/persistence](../tracks/persistence.md).

## Постановка
Авторитетный серверный pipeline и durable idempotency; тест не расходует реальные деньги.

## Реализация
Опиши идентификатор receipt и связь с profile owner. Grant и marker должны согласованно попадать в durable state. Повтор callback не повторяет выдачу. Ошибка записи/неизвестный outcome не превращается в безусловный success. Все yields вне чистого transform.

## Приёмка
Один receipt несколько раз, restart между grant/ack, profile unavailable, old server resumes, разные receipts в одном профиле.

## Что не делать
Не использовать client purchase popup result как доказательство оплаты. Не ждать принципиально невозможной абсолютной exactly-once сети.

## Сдача
Файлы и setup, точные использованные API/источники, реальные тесты и screenshots/profiler по необходимости. NOT RUN для отсутствующего evidence.
