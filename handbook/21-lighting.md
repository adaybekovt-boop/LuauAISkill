# 21. Освещение и ограничения API

Срез проверки: **26 сентября 2026**. Это авторская рабочая методика, не полный перевод официальной страницы. Непроверенные в Studio рецепты требуют отдельного запуска.


## Сначала способ конфигурации
В современном руководстве выбор LightingStyle заменяет старое мышление «всегда поставить Technology.Future». Technology присутствует в reference как deprecated. Но нельзя из наличия property делать вывод, что обычный Script может его записывать. Для каждого member проверять security read/write, tags, capabilities и host. Без такой проверки configuring pipeline через Studio безопаснее, чем silent pcall вокруг всех присваиваний.

В reference/lighting-api-audit.json сохранены именно проверенные поля для ключевых свойств; это не полный API dump. Если HTML не показывает security, открыть исходный YAML или current member reference. Право read и thread-safety ReadSafe не являются правом write. Настройку, требующую Studio, включить в setup checklist и показать как неподтверждённую до реального применения.

## Проверенный срез исходного YAML
На коммите `cc850a83d75d8ad7ff638c2733fd3a1a7a0bdd91` у `LightingStyle` и `PrioritizeLightingQuality` действительно указаны **read: None / write: None** и capability `Environment`. Поэтому нельзя навсегда запрещать их runtime-запись по старому ответу модели. У `Technology` указан `RobloxScriptSecurity`: это другой контракт. `ReadSafe` не разрешает запись из parallel-контекста. Перед установкой всё равно проверить целевую Studio и capabilities.

В том же источнике описание ShadowSoftness ещё ссылается на старые Technology, а у Technology есть deprecation message при пустом массиве tags. Это реальные причины сверять несколько полей, а не искать только слово Deprecated.

## Авторская схема интерьера
Определить мотивированные источники: окна, потолочные светильники, аварийные лампы, экраны. Выбрать один главный световой акцент, общий слабый fill и при необходимости separation light. Каждому дополнительному источнику нужен смысл. Не лечить неверные normals и щели сотней PointLight.

Сначала подобрать экспозицию на нейтральном материале, затем яркость и цвет источников. Слишком яркий Ambient способен уничтожить глубину помещения. Слишком низкая экспозиция превращает scene в чёрный прямоугольник. Для реалистичного материала проверить sky contribution и specular response, а не подгонять albedo до компенсации каждого освещения.

## Сравнение
Снимки до/после делать с одним camera transform, FOV, quality tier, aspect ratio и временем суток. Проверить углы между комнатами, thin walls, moving light, мокрые surfaces и тёмный character. Изменения оценивать вместе с профилем GPU/CPU. Runtime-пример пакета управляет только небольшим presentation-слоем и не выдаётся за автоматический «RTX renderer».


## Первичные источники
- [R15] Global lighting: https://create.roblox.com/docs/environment/lighting
- [R16] Lighting API: https://create.roblox.com/docs/reference/engine/classes/Lighting
- [R19] Post-processing: https://create.roblox.com/docs/environment/post-processing-effects
