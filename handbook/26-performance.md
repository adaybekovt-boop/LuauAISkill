# 26. Профилирование: CPU, GPU, память и сеть

Срез проверки: **26 сентября 2026**. Это авторская рабочая методика, не полный перевод официальной страницы. Непроверенные в Studio рецепты требуют отдельного запуска.


## Метрика прежде оптимизации
FPS сам по себе скрывает spikes. Сохранять median/p95/p99 frame time и метод выборки, отдельно engine CPU/GPU где доступно, memory, количество объектов, network и server time. Данные Heartbeat или RenderStepped — наблюдение интервала, не достоверный GPU timer. Скрипт телеметрии обязан подписывать такую метрику правильно.

Числа 16.67 ms для 60 FPS и 33.33 ms для 30 FPS — арифметические бюджеты, а не обещания клиента. Части budget делит вся игра. Не обещать фиксированное число PointLight, Parts или triangles, подходящее каждому устройству: экран, материалы, visibility и geometry меняют стоимость.

## Авторская процедура A/B
Закрепить сцену, seed, маршрут, quality, разрешение, число игроков и warmup. Сделать несколько baseline runs, затем изменить один фактор и повторить. Не сравнивать пустой редактор с опубликованным тяжёлым сервером. Сохранять raw measurements, а не только красивый процент. Показать абсолютные ms и возможную вариативность.

Если лаг зависит от направления камеры — исследовать visible geometry, lights, transparency и draw calls. Если лаг растёт со временем — lifecycle/memory/queues. Если зависит от игроков — simulation, remotes и replication. Если редкий при первой встрече asset — loading/warmup path. Это гипотезы для профиля, не окончательный диагноз.

## Оптимизация
Сначала убрать ненужную работу и unbounded growth. Затем batching/reuse/culling/LOD с визуальным сравнением. Native/parallel — после доказанного CPU bottleneck. При каждом изменении проверить correctness: cache не должен возвращать устаревшую позицию, culling — удалять gameplay collider, pooling — выдавать старое состояние.

Принять изменение только с журналом теста и rollback path. «На моём ПК стало плавнее» полезное наблюдение, но не универсальная метрика.


## Первичные источники
- [R20] Improve performance: https://create.roblox.com/docs/performance-optimization/improve
- [R29] Native code generation: https://create.roblox.com/docs/luau/native-code-gen
- [R08] Parallel Luau: https://create.roblox.com/docs/scripting/multithreading
- [R24] SLIM: https://create.roblox.com/docs/workspace/streaming/slim
