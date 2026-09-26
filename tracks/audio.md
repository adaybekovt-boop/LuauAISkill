# Звук и аудиограф

## Порядок
- [19-audio](../handbook/19-audio.md)
- [16-architecture](../handbook/16-architecture.md)
- [27-quality-tiers](../handbook/27-quality-tiers.md)
- [28-testing](../handbook/28-testing.md)

## Решение задачи
Проверить права asset, тип источника и graph path. Локальная шина и spatial routing различаются. Ограничить одновременные звуки.

## Критерий сдачи
Воспроизведение/остановка/cleanup, корректная громкость на устройствах и отсутствие приватного захвата без разрешения.

## Исходные документы
R13 — точные URL в `../sources/registry.json`. Полные тела не считаются включёнными без upstream manifest.

## Расширенные разделы
- [42. Scene Analysis и утечки ресурсов](../handbook/42-scene-analysis.md)
