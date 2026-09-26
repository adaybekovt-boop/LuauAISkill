# Модульные комнаты без рваных стыков

Маршрут: [tracks/world-streaming](../tracks/world-streaming.md).

## Постановка
Набор floor/wall/corner/doorway/ceiling с одной сеткой и socket contract.

## Реализация
Задай общий origin, thickness, bounds и ориентации. Стены на общей границе имеют одного владельца. Вычисляй transforms от room pivot. Тестируй все допустимые rotations. Декоративные trim закрывают стык художественно, но не заменяют правильный collision.

## Приёмка
Две комнаты, угол, Т-перекрёсток, лестница, петля, большой seed suite. Проверка walker clearance и ray/overlap diagnostics.

## Что не делать
Не раздувать каждую стену на случайный epsilon: overlap создаёт z-fighting и проблемы проёмов.

## Сдача
Файлы и setup, точные использованные API/источники, реальные тесты и screenshots/profiler по необходимости. NOT RUN для отсутствующего evidence.
