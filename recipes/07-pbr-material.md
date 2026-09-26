# Проверка PBR-материала

Маршрут: [tracks/graphics](../tracks/graphics.md).

## Постановка
Один material set с понятной лицензией и контрольный mesh с корректным UV/tangent space.

## Реализация
Проверь scale/texel density и map assignment. Сравни color, normal, roughness, metalness и emissive по текущему контракту. Отдельно проверь alpha mode. Различай SurfaceAppearance для UV и MaterialVariant для tileable material. Не меняй maps runtime без metadata.

## Приёмка
Сухой/мокрый образец, боковой свет, hard edge, шов UV, несколько камер, low quality и asset ownership в опубликованном тесте.

## Что не делать
Чёрный mesh не лечится максимальным Bloom. Texture resolution не исправляет неверные normals.

## Сдача
Файлы и setup, точные использованные API/источники, реальные тесты и screenshots/profiler по необходимости. NOT RUN для отсутствующего evidence.
