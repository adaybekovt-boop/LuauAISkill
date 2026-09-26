# 31. Релиз, права и поддержка

Срез проверки: **26 сентября 2026**. Это авторская рабочая методика, не полный перевод официальной страницы. Непроверенные в Studio рецепты требуют отдельного запуска.


## Не путать готовность исходников и готовность плейса
Перед публикацией проверить владельца experience, доступность mesh/texture/audio/animation assets, настройки test/production data, разрешения HTTP и секретов, приватность и текущие правила платформы. Этот handbook не является юридической консультацией или подтверждением соответствия правилам Roblox.

## Авторский release checklist
Собрать reproducible version с manifest зависимостей, pins и changelog. Сохранить rollback-версию place и schema strategy. Сделать smoke в опубликованном тестовом experience, где работают облачные функции, а не только в локальном файле. Провести late join, reconnect, teleport, empty server и multi-client сценарии.

Каждая внешняя зависимость имеет автора, лицензию и версию. Нельзя считать весь Creator Store open source. Удаление слова copyright из файла не меняет права. Отдельно учитывать ограниченные sample assets и сторонние элементы, даже если окружающая документация открыто лицензирована.

## Наблюдаемость после релиза
Нужны счётчики ошибок загрузки, save failures, remote rejects, очередь операций, memory growth и client crash/performance signals там, где они доступны. Метрика должна иметь определение и окно, иначе «ошибок стало меньше» может означать, что логирование выключено. Не загружать чувствительные пользовательские данные в отчёты AI без необходимости и разрешений.

Hotfix должен минимизировать blast radius: отключить проблемную необязательную функцию, не переписывая persistence в спешке. Данные и код откатываются разными способами: code rollback не отменяет уже изменённые записи. Агент обязан назвать это ограничение до релиза.

Итоговый deliverable содержит patch, setup steps, actual tests, known limitations и next verification action. Красивое обещание «всё готово» без этих материалов не считается завершением.


## Первичные источники
- [R06] Third-party asset vulnerabilities: https://create.roblox.com/docs/scripting/security/third-party-vulnerabilities
- [R22] Player data and purchasing: https://create.roblox.com/docs/cloud-services/data-stores/player-data-purchasing
- [R00] Roblox AI documentation index: https://create.roblox.com/docs/llms.txt
