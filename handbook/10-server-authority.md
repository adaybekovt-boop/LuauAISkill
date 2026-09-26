# 10. Новая server authority: prediction и rollback

Срез проверки: **26 сентября 2026**. Это авторская рабочая методика, не полный перевод официальной страницы. Непроверенные в Studio рецепты требуют отдельного запуска.


## Не смешивать два разных проекта
Обычная серверная проверка RemoteEvent и режим движка AuthorityMode.Server — не одно и то же. Существующий place не получает корректную rollback-симуляцию от одной смены галочки. В актуальном руководстве связаны настройки AuthorityMode, NextGenerationReplication, Input Action System, Deferred signals, fixed simulation и streaming.

В этом пути core simulation запускается на обеих сторонах через BindToSimulation и может исполняться повторно при rollback. Следовательно, выдача платной покупки, запись в DataStore, звук и создание декоративных эффектов не должны выполняться как необратимые side effects на каждом повторе симуляции. Для API внутри callback проверять Simulation Access, а не только existence/thread safety.

## Авторская стратегия внедрения
Сначала сделать отдельный branch и минимальную сцену с одним движущимся объектом. Записать движение на двух клиентах, ввести задержку и искусственно вызвать correction. Затем добавить один повторяемый gameplay state. Проверить, что повтор симуляции не удваивает события presentation. Сохранять action/frame identities и согласованный процесс вывода эффектов.

InputContext требует правильного владельца в дереве Player; общая схема расположения InputContext для обычного UI не переносится сюда без изменений. Источником core input служат действия, которые система может записать и повторить, а не произвольный локальный InputBegan вне симуляции.

## Gate для агента
До реализации открыть R11 и актуальные API BindToSimulation, SetPredictionMode и свойства Workspace, проверить доступность в конкретном Studio. Этот пакет содержит маршрут и требования, а не заявление, что каждый target-client уже поддерживает весь режим. При недоступности не маскировать её pcall: оставить прежнюю архитектуру или изолировать экспериментальный place.

Приёмка: повтор шага не выдаёт награду дважды; входы воспроизводятся; correction не ломает UI; остановка/возврат персонажа очищает локальные эффекты; нет запрещённых API в simulation callback. Числа лимитов брать из текущего источника, а не дублировать вечными константами.


## Первичные источники
- [R11] Server authority: https://create.roblox.com/docs/projects/server-authority
- [R12] Input Action System: https://create.roblox.com/docs/input/input-action-system
- [R09] Deferred events: https://create.roblox.com/docs/scripting/events/deferred
