# Умеренная bodycam-камера

Маршрут: [tracks/graphics](../tracks/graphics.md).

## Постановка
Чуть несовершенная камера при сохранении видимости. Нужны motion budget и reduced-motion/effects настройки, а не сильный фильтр на весь экран.

## Реализация
Выбери владельца Camera. Строй базовый transform каждый кадр и добавляй bounded offsets по dt. Сначала движение/позиция, затем слабый grade и редкие dirt details. Отдельно привяжи звук шагов и экипировки. Не обещай произвольный postprocess shader.

## Приёмка
Стоп движения, низкий/высокий FPS, menu, death/spectate, смена CurrentCamera, bright/dark rooms, отключённые effects.

## Что не делать
Нельзя скрывать geometry defects шумом. Нельзя накапливать sway на прошлом уже смещённом transform.

## Сдача
Файлы и setup, точные использованные API/источники, реальные тесты и screenshots/profiler по необходимости. NOT RUN для отсутствующего evidence.
