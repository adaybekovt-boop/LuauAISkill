# 45. CFrame, локальные оси, pivot и сетка

Авторский синтез; проверка первичных источников 26.09.2026. Не официальный перевод и не отчёт о выполненном Studio-тесте.

## Зафиксировать систему координат
У любой комнаты, двери, оружия и камеры есть local origin и правила forward/up. До генерации определить units в studs, pivot, масштаб и направление socket connections. World и local CFrame не взаимозаменяемы. Умножение transforms не коммутирует: rotation→translation и translation→rotation дают разные сцены.

Отдельно хранить placement transform комнаты и local transforms стен/пропов. Тогда перенос комнаты не требует пересчёта случайного набора мировых координат. Передавать между компонентами не голую Vector3 с неясным смыслом, а контракт «world position», «local offset», «normalized direction» и единицы.

## Нормализация и устойчивость
Нельзя безусловно брать Unit у нулевого или невалидного вектора. Сначала finite components и минимальная длина. Для look direction near-degenerate up/forward определить fallback. Не лечить редкий NaN общим teleport-to-origin: это скрывает повреждённый state и может стать exploit surface.

Для модульной карты размеры считать от одной сетки, а не независимо округлять обе стороны шва. Общая граница имеет одного владельца. Толщина стен и проёмов — часть геометрии, не приблизительные декорации. При прямоугольных bounds полезны проверки пересечения; для сложной геометрии такой тест только broad phase и не доказывает проходимость.

## Проверка сборки
Вставить один модуль в четырёх поворотах, затем связать два, затем Т-перекрёсток и вертикальный переход. Проверять дверь с реальным collider/character dimensions. Сравнить ожидаемые socket positions и normals с измеренными. Импортированный mesh с неверным pivot может смотреть правильно из одного ракурса, но ломать весь procedural pipeline.

В анимации камеры ownership ещё важнее: не умножать sway на уже изменённый прошлым кадром transform бесконечно. Каждый кадр строится от определённого baseline/owner pipeline. Отдельный presentation offset не должен изменять авторитетную физическую позицию игрока.

## Первичные источники
- [R27] Raycasting: https://create.roblox.com/docs/workspace/raycasting
- [R28] Physics network ownership: https://create.roblox.com/docs/physics/network-ownership
- [R33] Procedural models: https://create.roblox.com/docs/parts/procedural-models
