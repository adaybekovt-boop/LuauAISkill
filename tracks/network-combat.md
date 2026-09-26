# Сеть, PvP и взаимодействия

## Порядок
- [07-remotes](../handbook/07-remotes.md)
- [08-security](../handbook/08-security.md)
- [09-authoritative-combat](../handbook/09-authoritative-combat.md)
- [10-server-authority](../handbook/10-server-authority.md)
- [13-physics](../handbook/13-physics.md)
- [28-testing](../handbook/28-testing.md)

## Решение задачи
Определить серверный state machine и client intent protocol. Валидация, лимиты, повтор/задержка/смерть/выход. Новая authority architecture требует отдельной оценки replay.

## Критерий сдачи
Threat model, контракт remote, двухклиентный тест, stale/duplicate/NaN/range-negative cases.

## Исходные документы
R03, R04, R05, R11 — точные URL в `../sources/registry.json`. Полные тела не считаются включёнными без upstream manifest.

## Расширенные разделы
- [35. Character Controller Library и выбор движения](../handbook/35-ccl.md)
- [36. Animation Graph: клипы, параметры и сетевой режим](../handbook/36-animation-graphs.md)
- [44. Buffers и компактные данные без хрупкого протокола](../handbook/44-binary-protocol.md)
- [46. Асинхронность, отмена и отсутствие скрытых гонок](../handbook/46-async-contracts.md)
