# Профили, прогресс и покупки

## Порядок
- [14-persistence](../handbook/14-persistence.md)
- [15-purchases](../handbook/15-purchases.md)
- [08-security](../handbook/08-security.md)
- [28-testing](../handbook/28-testing.md)
- [31-release](../handbook/31-release.md)

## Решение задачи
Отказ загрузки и новый профиль различаются. Session ownership, ordered writes, schema migration и retry перед магазином. Никаких реальных денег или production keys в демонстрационном тесте.

## Критерий сдачи
Тесты повторных receipts, неизвестного результата записи, потери lock, stale save и shutdown; явные ограничения.

## Исходные документы
R21, R22, R23 — точные URL в `../sources/registry.json`. Полные тела не считаются включёнными без upstream manifest.

## Расширенные разделы
- [37. MemoryStore: временная координация, а не вечный сейв](../handbook/37-memory-stores.md)
- [38. Cross-server messaging и консистентность](../handbook/38-messaging.md)
- [39. Телепортация и переход между плейсами](../handbook/39-teleports.md)
- [40. Пользовательский текст, фильтрация и RichText](../handbook/40-text-safety.md)
- [46. Асинхронность, отмена и отсутствие скрытых гонок](../handbook/46-async-contracts.md)
