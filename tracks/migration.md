# Миграция старого кода

## Порядок
- [00-contract](../handbook/00-contract.md)
- [02-modern-syntax](../handbook/02-modern-syntax.md)
- [05-runtime-layout](../handbook/05-runtime-layout.md)
- [06-scheduling](../handbook/06-scheduling.md)
- [21-lighting](../handbook/21-lighting.md)
- [30-migration](../handbook/30-migration.md)
- [28-testing](../handbook/28-testing.md)

## Решение задачи
Составить inventory по файлам и capability/API evidence. Не заменять поддерживаемые паттерны просто за возраст. Не объединять миграцию и переделку gameplay.

## Критерий сдачи
Малые патчи, behavior parity, схема запуска, явный список pending changes и нужных feature flags.

## Исходные документы
L01, L12, R01, R07, R16 — точные URL в `../sources/registry.json`. Полные тела не считаются включёнными без upstream manifest.

## Расширенные разделы
- [32. Script Sync, внешний редактор и источник истины](../handbook/32-script-sync.md)
- [33. Capabilities и sandbox: права не лечатся pcall](../handbook/33-script-capabilities.md)
- [47. Сентябрь 2026: новизна, эксперимент и противоречия](../handbook/47-release-status.md)
