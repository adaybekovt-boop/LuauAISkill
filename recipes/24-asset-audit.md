# Проверка ассета до импорта

Маршрут: [tracks/migration](../tracks/migration.md).

## Постановка
Известный источник, лицензия, ownership и полный dependency список, отдельная копия place.

## Реализация
Сначала read-only список LuaSourceContainers, requires, edit-time generators и необычных capabilities. Проверь вложенные scripts и asset dependencies. Не запускай obfuscated код. После одобрения импортируй ограниченный subtree, сравни diff и test lifecycle.

## Приёмка
Никаких изменений вне allowed subtree, никаких неожиданных remotes/HTTP/storage calls, корректные permissions и cleanup.

## Что не делать
Наличие Creator Store страницы или слова Open Source не является доказательством безопасности и лицензии.

## Сдача
Файлы и setup, точные использованные API/источники, реальные тесты и screenshots/profiler по необходимости. NOT RUN для отсутствующего evidence.
