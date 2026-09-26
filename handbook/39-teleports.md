# 39. Телепортация и переход между плейсами

Авторский синтез; проверка первичных источников 26.09.2026. Не официальный перевод и не отчёт о выполненном Studio-тесте.

## Host и границы теста
Для нового кода текущая документация рекомендует server-side `TeleportService:TeleportAsync(placeId, players, options)`. Локальный старый Teleport описан как deprecated. TeleportService не проверяется полноценным Studio playtest: нужен опубликованный тест и Roblox client. Напечатанное «teleport success» перед вызовом не доказывает переход.

Проверка прав на вход в destination является частью game design: start-place-only, secure within universe, direct access overrides и разрешение third-party переходов. Защита destination не сводится к секретному placeId. Пользователь может прийти другим разрешённым маршрутом; сервер destination должен проверить собственную модель доступа и прогресса.

## State machine перехода
Idle → Requested → Preparing → Teleporting → Arrived либо Failed/Cancelled. На каждой фазе понятен владелец данных, ответственность за retry и отображение UI. Не хранить игрока навечно в frozen состоянии после неудачи. Не повторять переход каждые 0.1 секунды без верхней границы и отмены.

При group teleport учитывать выход одного участника, частичный успех и срок резервации. Non-sensitive контекст может сопровождать переход, но деньги, доказательство доступа и секретные reservation credentials не доверяются клиенту. Persistent данные читаются и проверяются на destination через надёжный серверный источник.

## UI и сохранение
Custom teleport GUI создаётся на клиенте; сама картинка загрузки не должна выполнять критическую игровую логику. Сохранение перед переходом имеет неопределённости записи/повтора: нельзя автоматически создать новый профиль только потому, что destination не успел его загрузить. Session transfer должен не допустить двух одновременно пишущих владельцев.

Проверить отмену, повторную кнопку, ошибку инициализации teleport, недоступный destination, rejoin старого сервера и arrival с устаревшим контекстом. Эту проверку выполнять на тестовых places без production-экономики. В release checklist перечислить реальные access settings, а не только строки Luau.

## Первичные источники
- [R36] Teleport between places: https://create.roblox.com/docs/projects/teleport
- [R34] Memory stores: https://create.roblox.com/docs/cloud-services/memory-stores
- [R21] Data stores: https://create.roblox.com/docs/cloud-services/data-stores
- [R04] Client-server security boundary: https://create.roblox.com/docs/scripting/security/client-server-boundary
