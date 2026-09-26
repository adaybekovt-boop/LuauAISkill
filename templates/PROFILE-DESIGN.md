# Persistent profile — design review, не готовый storage код
Schema version и допустимые значения:
Создание профиля vs load failure:
Session owner / lease / fencing / release:
Ordering всех операций одного ключа:
UpdateAsync callback: чистый, non-yielding, повторяемый:
Retry classification, budget, unknown write outcome:
Receipt grant и dedup marker в durable state:
Миграция: monotonic version, deterministic, bounds, rollback compatibility:
Autosave cadence, batching, shutdown deadline:
Player leave до завершения load / reconnect / concurrent servers:
Data deletion/privacy requirements и отдельная проверка текущих правил:
Failure-injection tests:
Production readiness: NOT ESTABLISHED
