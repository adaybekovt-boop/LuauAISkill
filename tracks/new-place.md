# Новый плейс

## Порядок
- [00-contract](../handbook/00-contract.md)
- [05-runtime-layout](../handbook/05-runtime-layout.md)
- [16-architecture](../handbook/16-architecture.md)
- [07-remotes](../handbook/07-remotes.md)
- [08-security](../handbook/08-security.md)
- [11-streaming](../handbook/11-streaming.md)
- [20-graphics-pipeline](../handbook/20-graphics-pipeline.md)
- [28-testing](../handbook/28-testing.md)
- [31-release](../handbook/31-release.md)

## Решение задачи
Выделить один игровой цикл: войти → действовать → получить результат → умереть/повторить. Сначала вертикальный срез в маленькой карте; затем расширение. Не строить огромную карту до проверки кооперации систем.

## Критерий сдачи
Рабочий небольшой цикл, boot/respawn/2-client evidence, список незавершённых систем.

## Исходные документы
R01, R02, R03, R04 — точные URL в `../sources/registry.json`. Полные тела не считаются включёнными без upstream manifest.

## Расширенные разделы
- [32. Script Sync, внешний редактор и источник истины](../handbook/32-script-sync.md)
- [33. Capabilities и sandbox: права не лечатся pcall](../handbook/33-script-capabilities.md)
- [35. Character Controller Library и выбор движения](../handbook/35-ccl.md)
