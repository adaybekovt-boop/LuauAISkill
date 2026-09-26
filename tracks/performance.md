# Оптимизация без самообмана

## Порядок
- [06-scheduling](../handbook/06-scheduling.md)
- [11-streaming](../handbook/11-streaming.md)
- [12-parallel](../handbook/12-parallel.md)
- [26-performance](../handbook/26-performance.md)
- [27-quality-tiers](../handbook/27-quality-tiers.md)
- [28-testing](../handbook/28-testing.md)

## Решение задачи
Зафиксировать baseline, тип bottleneck и репрезентативный сценарий. Менять одну гипотезу, повторять прогон; проверять tail latency и correctness.

## Критерий сдачи
До/после raw evidence, p95/p99 там где измеримы, нагрузка/устройство/quality, rollback неоправданных изменений.

## Исходные документы
R07, R08, R10, R20, R29 — точные URL в `../sources/registry.json`. Полные тела не считаются включёнными без upstream manifest.

## Расширенные разделы
- [41. MicroProfiler: от симптома к проверенной причине](../handbook/41-profiling-workflow.md)
- [42. Scene Analysis и утечки ресурсов](../handbook/42-scene-analysis.md)
- [46. Асинхронность, отмена и отсутствие скрытых гонок](../handbook/46-async-contracts.md)
