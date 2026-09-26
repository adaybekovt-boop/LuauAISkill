# Язык и строгие типы

## Порядок
- [01-language-model](../handbook/01-language-model.md)
- [02-modern-syntax](../handbook/02-modern-syntax.md)
- [03-types](../handbook/03-types.md)
- [04-tables-generics](../handbook/04-tables-generics.md)
- [06-scheduling](../handbook/06-scheduling.md)

## Решение задачи
Сначала host и версия parser/analyzer. Затем публичные типы, границы unknown и реальные feature probes. Не подключать experimental syntax в entrypoint.

## Критерий сдачи
Чистый модуль и его контракты; compile/typecheck и тесты, если доступны.

## Исходные документы
L01, L02, L03, L04, L05, L06, L07, L08, L09, L10, L12 — точные URL в `../sources/registry.json`. Полные тела не считаются включёнными без upstream manifest.

## Расширенные разделы
- [43. Luau: края языка, которые ломают надёжные системы](../handbook/43-language-edge-cases.md)
- [44. Buffers и компактные данные без хрупкого протокола](../handbook/44-binary-protocol.md)
- [46. Асинхронность, отмена и отсутствие скрытых гонок](../handbook/46-async-contracts.md)
- [47. Сентябрь 2026: новизна, эксперимент и противоречия](../handbook/47-release-status.md)
