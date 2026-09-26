# 42. Scene Analysis и утечки ресурсов

Авторский синтез; проверка первичных источников 26.09.2026. Не официальный перевод и не отчёт о выполненном Studio-тесте.

## Что измеряет инструмент
Scene Analysis работает во время play/test и показывает состав client/server сцен и распределение ресурсов. VM script memory — не память всех texture/audio assets. Unparented instances — не автоматически утечка: иногда объект намеренно находится в bounded pool. Ошибка определяется отсутствием владельца/срока и устойчивым ростом после повторяемых циклов.

В текущем инструменте доступны script memory, unparented references, instance composition, audio/animation memory и triangle/draw-call composition. Сценарий с 500 Parts нельзя оценить только числом Parts: прозрачность, тени, материалы, движения и render passes меняют стоимость. Собственный SceneAudit пример в пакете считает некоторые instances и не притворяется источником draw-call статистики.

## Цикл проверки
Сделать снимок baseline после прогрева; выполнить одинаковое действие много раз — respawn, открыть/закрыть меню, загрузить/выгрузить комнату, spawn/destroy NPC. После ожидаемого cleanup сравнить состав и память. Активный cache может оставить часть памяти намеренно; при этом upper bound и ownership должны быть объяснены.

При обнаружении роста искать удерживающий host script, closures, event handlers, AnimationTracks и tables. Destroy модели не очищает произвольную внешнюю таблицу ссылок на неё. Ссылка на Instance — ещё не доказательство дефекта, но цепочка к неограниченному registry после удаления сцены уже причина для анализа.

## Программный доступ
Документация описывает SceneAnalysisService через MCP, в том числе GetScriptMemoryAsync, GetUnparentedInstancesAsync и GetTriangleCompositionAsync. Проверить security/host перед использованием: доступность Studio diagnostic API не гарантирует вызов обычным игровым Script. Не встраивать admin-only анализ в каждый клиент.

Сравнение development PC и телефона ограничено device scaling. Принять решение по реальным целевым устройствам. Результат работы агента — не только удалённые тысячи объектов, но подтверждение, что удалены ненужные ресурсы, не gameplay state, и повторные циклы больше не приводят к необъяснимому росту.

## Первичные источники
- [R39] Scene Analysis: https://create.roblox.com/docs/performance-optimization/scene-analysis
- [R38] MicroProfiler: https://create.roblox.com/docs/performance-optimization/microprofiler
- [R20] Improve performance: https://create.roblox.com/docs/performance-optimization/improve
