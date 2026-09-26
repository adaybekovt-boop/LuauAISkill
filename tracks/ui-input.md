# Управление и интерфейс

## Порядок
- [05-runtime-layout](../handbook/05-runtime-layout.md)
- [18-input-ui](../handbook/18-input-ui.md)
- [24-camera-effects](../handbook/24-camera-effects.md)
- [28-testing](../handbook/28-testing.md)

## Решение задачи
Разделить действие и устройство ввода; определить priority/modal ownership, focus и rebinding. Native styling не равен CSS.

## Критерий сдачи
Keyboard/gamepad/touch where supported; respawn, menu conflicts, localization overflow, no leaked callbacks.

## Исходные документы
R01, R12, R14 — точные URL в `../sources/registry.json`. Полные тела не считаются включёнными без upstream manifest.

## Расширенные разделы
- [32. Script Sync, внешний редактор и источник истины](../handbook/32-script-sync.md)
- [35. Character Controller Library и выбор движения](../handbook/35-ccl.md)
- [40. Пользовательский текст, фильтрация и RichText](../handbook/40-text-safety.md)
