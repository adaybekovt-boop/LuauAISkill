# Свежесть и конфликты

Срез — 26.09.2026. Старый обучающий пример не исчезает из интернета после изменения API. Используйте цепочку: exact target build → current official API metadata → current guide → pinned source → authored handbook. При конфликте не скрывайте ни один источник.

Пример 1: LightingStyle/PrioritizeLightingQuality в текущем YAML имеют read/write None; Technology — RobloxScriptSecurity. Старый search snippet или чужой ответ может запрещать новые свойства. Проверенные поля находятся в lighting-api-audit.json; никаких runtime-тестов они не заменяют.

Пример 2: deprecation_message при пустом tags. Парсер, который проверяет только `Deprecated in tags`, потеряет важное предупреждение. HTML, YAML и release note могут обновляться несинхронно.

Пример 3: latest compiler experiment против Studio rollout. Exact-by-default tables и if local отмечены experimental в просмотренном 740 release sync. Написать их в boot-critical module только по merge status нельзя.

Пример 4: feature guide против step-by-step tutorial. Coding harness guide всё ещё называет Script Sync beta; отдельная Script Sync страница описывает общий запуск. Фактическое меню пользователя и ограничения sync важнее самоуверенного универсального совета.

Пример 5: сетевая ошибка не равна отсутствию темы. Markdown endpoint, raw GitHub или индекс могут временно не открываться. `404`, ошибка API, truncated tree, нескачанный full body и честное “no results” — разные состояния.

В реестре `body_bundled: false` означает, что ссылка/исследование не являются локальным полным документом. В downloaded mirror сохраняются commit/URL/hashes и manifest. Не повышать evidence status автоматически из-за большого размера ZIP.
