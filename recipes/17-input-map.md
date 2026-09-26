# Action-based cross-platform input

Маршрут: [tracks/ui-input](../tracks/ui-input.md).

## Постановка
Действия interact/sprint/menu отдельно от клавиш/кнопок.

## Реализация
InputContext владеет группой действий. Создай подходящие InputBindings для устройств и явный UIButton для touch. Определи enabled/priority/sink и взаимодействие с chat/modal. При character replacement не дублируй action listeners.

## Приёмка
Удержание/отпускание, потеря focus, смена устройства, menu while moving, respawn, несколько contexts.

## Что не делать
Наличие KeyCode.E не означает поддержку телефона. Replay simulation не должна зависеть от обычного InputBegan напрямую.

## Сдача
Файлы и setup, точные использованные API/источники, реальные тесты и screenshots/profiler по необходимости. NOT RUN для отсутствующего evidence.
