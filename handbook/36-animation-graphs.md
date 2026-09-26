# 36. Animation Graph: клипы, параметры и сетевой режим

Авторский синтез; проверка первичных источников 26.09.2026. Не официальный перевод и не отчёт о выполненном Studio-тесте.

## Разделение ответственности
Animation Editor создаёт клипы, Animation Graph Editor связывает их в логику blend/select/sequence, gameplay определяет намерение и подтверждённое состояние. Graph asset не является AI-generated текстовым модулем: его надо создать, настроить, опубликовать и проверить права использования. Наличие кода LoadAnimation без доступного asset не даёт рабочую анимацию.

Текущий pipeline загружает опубликованный graph через Animator как Animation; параметры передаются через `AnimationTrack:SetParameter()`. Имена, типы и units параметров — часть контракта asset. Параметр speed не угадывается по похожему tutorial. Измерение скорости должно соответствовать gameplay: полная Magnitude включает вертикальное падение; для walk blend часто нужна горизонтальная относительная скорость по правилам контроллера.

## События и authority
Graph markers проходят через blend/selection со своими весами. Событие от нулевого влияния может не дойти до вершины. Поэтому боевой урон нельзя безусловно привязать к локальному визуальному marker как к авторитетному факту попадания. Маркер подходит для sync эффектов при продуманной дедупликации.

В Automatic и Server authority различаются управление graph state и предсказание. Документация говорит, что режим сгенерированного Animate определяется AuthorityMode на момент создания; после смены архитектуры проверить attrs и generated wrappers, не оставлять старую схему. Для NPC обычно серверное управление; для игрока нюансы owning client требуют источника.

## Практическая отладка
Проверить отдельно clip playback, затем один blend, затем переход idle→walk→run, затем верх тела и markers. Сравнить owning client, наблюдателя и server state. При respawn старые connections/AnimationTracks не должны продолжать обновлять параметры. Удалённый rig не должен удерживаться библиотекой animation references.

Фиксировать опубликованный asset/version и отличие preview от published. PreviewInStudio не заменяет проверку доступного другим игрокам опубликованного asset; текущий источник содержит ограничение preview для Server authority. Не объявлять это «полностью поддерживается» только потому, что редактор показал позу.

## Первичные источники
- [R41] Animation Graph Editor: https://create.roblox.com/docs/animation/graph-editor
- [R26] Animations: https://create.roblox.com/docs/animation/using
- [R11] Server authority: https://create.roblox.com/docs/projects/server-authority
