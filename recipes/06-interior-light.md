# Свет в индустриальном интерьере

Маршрут: [tracks/graphics](../tracks/graphics.md).

## Постановка
Контрольная комната с одним потолочным источником, doorway, нейтральной стеной, тёмным объектом и rough/metal образцами.

## Реализация
Проверь Lighting permissions. Настрой основной pipeline, затем exposure и motivated sources. Согласуй Ambient/OutdoorAmbient и материал. Не множь lights для компенсации щелей. Тени и specular проверяй вместе с нормалями и roughness.

## Приёмка
Фиксированные camera captures: угол, doorway, character silhouette, мокрый участок; low/high quality; moving actor shadow.

## Что не делать
Нет одного универсального набора чисел для всех карт. Technology в обычном runtime Script не писать.

## Сдача
Файлы и setup, точные использованные API/источники, реальные тесты и screenshots/profiler по необходимости. NOT RUN для отсутствующего evidence.
