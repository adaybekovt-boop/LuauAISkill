# 30. Миграция старого кода без слепых замен

Срез проверки: **26 сентября 2026**. Это авторская рабочая методика, не полный перевод официальной страницы. Непроверенные в Studio рецепты требуют отдельного запуска.


## Инвентаризация
Сначала зафиксировать рабочий baseline и tests. Найти legacy scheduling, старые ray APIs, BodyMover-подобное движение, устаревшие animation calls, старый chat stack, Technology и неизвестные remote require. Наличие legacy API не означает, что текущий place сломан; приоритет определяет риск, не возраст строки.

Миграция имеет две части: интерфейс и семантика. Новое имя метода недостаточно, если изменились filters, thread-safety, replication или timing. Особенно опасны task.spawn вместо отложенного spawn, изменение владельца физики и перенос Script в другой контейнер.

## Авторская процедура
Одна категория за commit. Для каждой замены записать before contract, after contract, конкретный source и regression test. Например, при переходе на Raycast сравнить дальность, фильтр character, коллизию декоративных деталей и нормаль hit. При переходе на Animator проверить rig, ownership и вид со второго клиента.

Нельзя менять весь проект regex-заменой `.wait` или `LoadAnimation` без AST/контекстного ревью. Некоторые совпадения являются пользовательскими именами, строками, комментариями или вызовами уже правильного объекта. Сканер в tools/audit_project.py выдаёт только кандидатов, а не автоматические исправления.

## Совместимость
Перед новыми const/generic features прогнать отдельные probes. Перед graphics migration сохранить screenshots старого результата. Перед schema migration сохранить test fixtures и backup реальных данных по одобренному процессу. Не объявлять «совместим со всеми версиями Roblox» без определённой матрицы.

Приёмка: нормальное поведение не изменилось; удалены только выбранные риски; диагностика источников сохранена; можно откатить отдельно код, конфигурацию и assets; нет незаметной потери client/server границы.


## Первичные источники
- [R07] Task scheduler: https://create.roblox.com/docs/scripting/scheduler
- [R01] Script types and locations: https://create.roblox.com/docs/scripting/locations
- [R16] Lighting API: https://create.roblox.com/docs/reference/engine/classes/Lighting
- [R26] Animations: https://create.roblox.com/docs/animation/using
- [R27] Raycasting: https://create.roblox.com/docs/workspace/raycasting
