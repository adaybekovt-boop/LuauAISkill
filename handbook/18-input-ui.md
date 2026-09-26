# 18. Input Actions, UI и управление

Срез проверки: **26 сентября 2026**. Это авторская рабочая методика, не полный перевод официальной страницы. Непроверенные в Studio рецепты требуют отдельного запуска.


## Действие важнее клавиши
Определить Interact, Sprint, Crouch, Pause, Inventory как gameplay actions. Для каждого задать keyboard/gamepad/touch bindings и состояния Begin/End/Cancel. Контекст меню блокирует конфликтующие действия игры и возвращает управление при закрытии. Потеря фокуса и смена устройства не должны оставлять sprint зажатым навсегда.

Input Action System даёт InputContext/InputAction/InputBinding. Для нового проекта изучить его; для существующего не ломать рабочий ContextActionService без осмысленной миграции. В server-authority режиме R11 ввод входит в записываемую симуляцию и имеет особые требования к владению — обычный UI-рецепт не универсален.

## Структура интерфейса
View отображает состояние, controller переводит ввод в команды, model описывает данные. Не позволять кнопке напрямую изменять серверный инвентарь. Pending-state защищает от случайного double click в UI, но сервер всё равно выполняет dedup/rate limit.

Макет проверять на нескольких aspect ratio, safe area, локализациях и масштабе текста. AutoSize и constraints должны иметь понятный источник размера; цикл «родитель зависит от ребёнка, ребёнок от родителя» диагностировать, а не маскировать пикселями. Длинные списки требуют ограничения числа активных элементов.

## Современный styling
StyleSheet/tokens позволяют централизацию внешнего вида. Проверить propagation и конфликт со скриптами, которые вручную меняют те же properties. Roblox styling не равен браузерному CSS: не выдумывать arbitrary selectors, DOM и CSS-свойства. Для каждой используемой возможности открыть совместимость.

Приёмка: клавиатура, gamepad navigation, touch, смена устройства на ходу, закрытие меню во время respawn, потеря фокуса, повторные clicks, длинные RU/EN строки и отсутствие мыши.


## Первичные источники
- [R12] Input Action System: https://create.roblox.com/docs/input/input-action-system
- [R14] UI styling: https://create.roblox.com/docs/ui/styling
- [R01] Script types and locations: https://create.roblox.com/docs/scripting/locations
