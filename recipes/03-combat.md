# Управляемая игровая боевая система

Маршрут: [tracks/network-combat](../tracks/network-combat.md).

## Постановка
Геймплейная state machine с telegraph, active window и recovery; сервер решает damage, клиент отвечает за немедленную presentation.

## Реализация
Опиши phase transitions и allowed actions. Раздели attack ID, server time, hit eligibility и визуальные markers. Один target не получает повторный hit от одного action без явного правила. Введи bounded action history и latency policy. Измеряй feel отдельно от security.

## Приёмка
Повтор action ID, attack после death, смена оружия во время windup, target respawn, high latency, simultaneous interactions и disconnect.

## Что не делать
Не доверять клиентскому damage, последнему clicked target или локальному Animation marker как единственному факту.

## Сдача
Файлы и setup, точные использованные API/источники, реальные тесты и screenshots/profiler по необходимости. NOT RUN для отсутствующего evidence.
