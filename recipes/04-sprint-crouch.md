# Спринт, приседание и clearance

Маршрут: [tracks/world-streaming](../tracks/world-streaming.md).

## Постановка
Два действия с явными конфликтами и допустимыми переходами. Выбор стандартного контроллера или CCL фиксируется до реализации.

## Реализация
Отдели input actions от stamina/state. Для вставания проверяй место над character и collision policy. Определи поведение на лестнице, платформе, в воде и при stun. Камера/bob/FOV — presentation. Каждое временное изменение имеет rollback на stop/respawn.

## Приёмка
Узкий потолок, быстрые нажатия, gamepad/touch, chat focus, stun during sprint, respawn while crouched.

## Что не делать
Не оставлять высоту/скорость испорченной после отмены. CCL beta не включается незаметно во всём production проекте.

## Сдача
Файлы и setup, точные использованные API/источники, реальные тесты и screenshots/profiler по необходимости. NOT RUN для отсутствующего evidence.
