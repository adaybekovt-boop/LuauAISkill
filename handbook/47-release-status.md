# 47. Сентябрь 2026: новизна, эксперимент и противоречия

Авторский синтез; проверка первичных источников 26.09.2026. Не официальный перевод и не отчёт о выполненном Studio-тесте.

## Дата не заменяет проверку
Эта глава фиксирует наблюдения на 26 сентября, а не обещает вечную актуальность. Встроенные знания модели, официальная страница, compiler master и конкретный клиент могут описывать разные этапы rollout. Следует хранить status и source date рядом с советом, а не один год в названии всего ZIP.

На просмотренном upstream commit от 25 сентября с release line 740 exact-by-default tables обозначены experimental; `if local` также ещё experimental. Такие конструкции не являются общим production baseline. При этом const bindings, function attributes и explicit generic instantiation уже описаны в актуальном справочнике языка. Наличие описания всё равно требует feature probe в целевом parser/Studio.

## Примеры расхождений
В актуальном Lighting YAML write security для LightingStyle/PrioritizeLightingQuality — None, для Technology — RobloxScriptSecurity. Запретить все три свойства одинаково по старому snippet неверно. С другой стороны, наличие нового свободного member не делает любые render settings доступными в игре.

Technology имеет deprecation message при пустом tags в просмотренном YAML; другие presentation слои могут показывать Deprecated. Это полезный regression test самого API extractor: смотреть несколько источников статуса и не терять предупреждение при нормализации.

Script capabilities и CCL явно обозначены beta/experimental в своих страницах. Script Sync feature guide и coding harness tutorial могут различаться в деталях beta включения. Агент должен проверить UI/build и зафиксировать факт, а не объявлять универсальную доступность или универсальную недоступность.

## Политика обновления
Обновлять snapshot отдельной операцией: новый SHA → diff источников → выбор затронутых глав → тесты probes/API → пересборка индекса → новый changelog. Не автоматически переписывать стабильный проект после каждого upstream релиза. Если новый материал противоречит старому, обозначить conflict и требуемое наблюдение. Выдумывать результат local test ради закрытия conflict запрещено.

Для каждого экспериментального feature оставить поддерживаемый fallback либо сознательно записать «проект требует эту версию/настройку». Не подменять fallback тихим исчезновением основной игровой функции.

## Первичные источники
- [G05] Luau upstream release 740 commit: https://github.com/luau-lang/luau/commit/c0e346edd89066b44dca174c9f54ce84c746a540
- [L01] Luau syntax: https://luau.org/syntax/
- [L12] Luau attributes: https://luau.org/attributes/
- [R30] Script Sync: https://create.roblox.com/docs/scripting/sync
- [R31] Build with a coding harness: https://create.roblox.com/docs/ai/coding-harness
- [R32] Script capabilities: https://create.roblox.com/docs/scripting/capabilities
- [R40] Character Controller Library: https://create.roblox.com/docs/characters/character-controller-library
- [R16] Lighting API: https://create.roblox.com/docs/reference/engine/classes/Lighting
