# 03. Стандартная библиотека Luau (+ Roblox-глобалы)

**Когда читать.** Перед любой работой со строками (форматирование чисел, таймеры, парсинг, паттерны,
русский текст в UI), таблицами (сортировка, копирование, удаление в цикле, reconcile профиля DataStore),
математикой (`math.round`, `math.noise`, `math.clamp`, RNG), бинарными данными (`buffer`, `bit32`),
временем (`os.time`/`os.clock`/`DateTime`), корутинами и `debug`. Все утверждения о поведении
помечены блоками `-- @run`: они реально выполнены Luau CLI, `assert` доказывают семантику.
Roblox-типы данных (Vector3, CFrame, Color3 …) подробно — в `07`; здесь только то, что относится к стандартной библиотеке.

## Содержание
1. [Быстрые факты, которые агенты путают](#1-быстрые-факты-которые-агенты-путают)
2. [string: все функции](#2-string-все-функции)
3. [string.format: спецификаторы и ловушки](#3-stringformat-спецификаторы-и-ловушки)
4. [Паттерны: полный синтаксис](#4-паттерны-полный-синтаксис)
5. [Строковые рецепты (StringUtil)](#5-строковые-рецепты-stringutil)
6. [utf8 и русский текст / эмодзи](#6-utf8-и-русский-текст--эмодзи)
7. [tonumber/tostring: ловушки ввода](#7-tonumbertostring-ловушки-ввода)
8. [table: все функции](#8-table-все-функции)
9. [Табличные рецепты (TableUtil)](#9-табличные-рецепты-tableutil)
10. [math](#10-math)
11. [Случайные числа: math.random vs Random](#11-случайные-числа-mathrandom-vs-random)
12. [bit32 и флаги](#12-bit32-и-флаги)
13. [buffer: бинарные данные](#13-buffer-бинарные-данные)
14. [vector (Luau) и Vector3 (Roblox)](#14-vector-luau-и-vector3-roblox)
15. [os и время](#15-os-и-время)
16. [coroutine](#16-coroutine)
17. [debug](#17-debug)
18. [Roblox-глобалы](#18-roblox-глобалы)
19. [Чек-лист](#чек-лист)
20. [Частые ошибки агентов](#частые-ошибки-агентов)

---

## 1. Быстрые факты, которые агенты путают

| Факт | Верно в Luau |
|---|---|
| `#s` у строки | число **байт**, не символов. `#"привет" == 12`. Символы — `utf8.len` |
| `string.upper/lower`, `%a`, `%l`, `%u` | работают **только с ASCII**. Кириллицу не трогают и не матчат |
| `string.format("%s", x)` | `x` обязан быть string или number, иначе ошибка. Для любых значений — `%*` или `tostring` |
| `string.format("%d", 3.7)` | `"3"` (усечение к нулю, без ошибки) |
| `string.format("%.0f", 2.5)` | `"2"` (банковское округление на точных половинах) |
| `math.round(2.5)` / `math.round(-2.5)` | `3` / `-3` (от нуля) |
| `math.clamp(x, min, max)` при `min > max` | ошибка. `math.clamp(nan, 0, 1)` = **nan** |
| `math.noise` в целых координатах | всегда `0` |
| `tonumber("inf")`, `tonumber("nan")` | `inf` и `nan` — валидируй ввод клиента через `math.isfinite`-подобную проверку |
| `table.sort` | не стабильна; компаратор должен быть строгим (`<`, не `<=`) |
| `table.insert(t, pos, v)` | позицию за пределами `#t+1` не проверяет — создаёт дыру |
| `table.freeze`, `table.clone` | **поверхностные** |
| `os.time({...})` | трактует таблицу как **UTC** (в Luau, в отличие от Lua 5.x) |
| `os.date("%H")` без `!` | локальный часовой пояс машины (на сервере — сервера) |
| `string.rep(s, n, sep)` | разделителя в Luau нет: третий аргумент игнорируется |
| `string.split(s, sep)` | `sep` — **простая строка**, не паттерн; пустые куски сохраняются |
| `^` в `gmatch` | не якорь |
| `math.lerp`, `math.map`, `math.isnan/isinf/isfinite` | существуют в текущем Luau и в типах Roblox, но **не зажимают** результат |

---

## 2. string: все функции

Все функции доступны и как методы: `s:upper()` ≡ `string.upper(s)`. Индексы 1-based, отрицательные
считаются с конца (`-1` — последний байт).

```luau
--!strict
-- @run
-- byte / char
assert(string.byte("A") == 65)
local b1, b2, b3 = string.byte("abc", 1, -1)
assert(b1 == 97 and b2 == 98 and b3 == 99)
assert(select("#", string.byte("")) == 0) -- пустая строка: ноль значений
assert(string.char(72, 105) == "Hi")

-- len / lower / upper / reverse / rep
assert(string.len("abc") == 3 and #"abc" == 3)
assert(("AbC"):lower() == "abc" and ("AbC"):upper() == "ABC")
assert(("Привет"):upper() == "Привет") -- кириллица НЕ меняется
assert(string.reverse("abc") == "cba")
assert(string.rep("ab", 3) == "ababab")
-- В Luau НЕТ разделителя (как в Lua 5.2+): string.rep(s, n) — два аргумента, третий игнорируется.
assert((string.rep :: any)("x", 3, ", ") == "xxx")
-- С разделителем: table.concat(table.create(n, s), sep)
assert(table.concat(table.create(3, "x"), ", ") == "x, x, x")
assert(string.rep("x", 0) == "" and string.rep("x", -1) == "")

-- sub: включительные границы, отрицательные индексы
assert(("hello"):sub(2, 4) == "ell")
assert(("hello"):sub(-3) == "llo")
assert(("hello"):sub(2, -2) == "ell")
assert(("hello"):sub(10) == "")
assert(("hello"):sub(0) == "hello") -- 0 трактуется как 1
assert(("hello"):sub(-0) == "hello") -- ЛОВУШКА: -0 == 0, это вся строка

-- find: возвращает start, end [, captures...]
local s, e = ("a.b"):find(".", 1, true) -- plain = true: точка — обычный символ
assert(s == 2 and e == 2)
local s2 = ("a.b"):find(".") -- без plain: "." = любой символ
assert(s2 == 1)
assert(("hello"):find("l", -2) == 4) -- init отрицательный: с конца
assert(("hello"):find("z") == nil)
local fs, fe, c1, c2 = string.find("abc", "(b)(c)")
assert(fs == 2 and fe == 3 and c1 == "b" and c2 == "c")
-- plain=true требует явного init: find(s, pattern, 1, true)

-- match: возвращает captures или весь матч
assert(string.match("key = value", "^(%w+)%s*=%s*(%w+)$") == "key")
assert(string.match("abc123", "%d+") == "123")
assert(string.match("abc", "%d") == nil)

-- gmatch: итератор по всем совпадениям
local pairsFound = {}
for k, v in string.gmatch("a=1, b=2", "(%w+)=(%w+)") do
	table.insert(pairsFound, `{k}{v}`)
end
assert(table.concat(pairsFound, ";") == "a1;b2")
local count = 0
for _ in string.gmatch("aaa", "^a") do
	count += 1
end
assert(count == 0) -- в gmatch "^" НЕ якорь (здесь это литерал "^")

-- split (Luau): простой разделитель, пустые куски сохраняются
local parts = ("a,b,,c"):split(",")
assert(#parts == 4 and parts[3] == "")
assert(#(""):split(",") == 1) -- пустая строка -> { "" }
local chars = ("abc"):split("")
assert(#chars == 3 and chars[2] == "b") -- пустой разделитель: по байтам (не по UTF-8 символам!)
local ws = ("a b"):split(" ")
assert(#ws == 2)
```

### gsub: все формы замены

`string.gsub(s, pattern, repl, n?)` возвращает **два** значения: новую строку и число замен.
`repl` — строка (с `%0` = весь матч, `%1..%9` = захваты, `%%` = процент), таблица (ключ — первый
захват или весь матч) или функция (аргументы — захваты). Если таблица/функция вернула `nil`/`false`,
исходный фрагмент сохраняется.

```luau
--!strict
-- @run
local r, n = string.gsub("hello world", "o", "0")
assert(r == "hell0 w0rld" and n == 2)

-- n: лимит замен
local r1 = string.gsub("hello world", "o", "0", 1)
assert(r1 == "hell0 world")

-- %0 и %1
assert((string.gsub("abc", "%w", "%0%0")) == "aabbcc")
assert((string.gsub("x=1;y=22", "(%w+)=(%w+)", "%2=%1")) == "1=x;22=y")
local ok = pcall(string.gsub, "abc", "%w", "%2")
assert(not ok) -- "invalid capture index"

-- таблица: ключ = первый захват; отсутствующий ключ -> фрагмент не меняется
local vars = { name = "Bob", age = "5" }
assert((string.gsub("$name is $age, $x", "%$(%w+)", vars)) == "Bob is 5, $x")

-- функция: nil -> оставить как есть
local up = string.gsub("abc", "(%w)", function(c: string): string?
	if c == "b" then
		return nil
	end
	return c:upper()
end :: any) -- типы Roblox не допускают nil-возврат из repl-функции, отсюда каст
assert(up == "AbC")

-- ЛОВУШКА: gsub возвращает 2 значения. В вызове функции/return оборачивай в скобки:
local function stripSpaces(str: string): string
	return (string.gsub(str, "%s", "")) -- без скобок вернулись бы (string, number)
end
assert(stripSpaces(" a b ") == "ab")
assert(select("#", string.gsub("a", "a", "b")) == 2)

-- пустой паттерн матчится между каждым байтом
assert((string.gsub("hi", "", "-")) == "-h-i-")

-- ЛОВУШКА: "%" в строке замены — спецсимвол. Пользовательский текст экранируй:
local userText = "100%"
local safeRepl = string.gsub(userText, "%%", "%%%%")
assert((string.gsub("Скидка: X", "X", safeRepl)) == "Скидка: 100%")
```

### pack / unpack / packsize (Luau)

Бинарная сериализация в строку по формату (как в Lua 5.3). Для новых задач в Roblox предпочтительнее
`buffer` (раздел 13) — он без аллокаций промежуточных строк и отправляется через remotes напрямую.

```luau
--!strict
-- @run
local packed = string.pack(">I2", 258) -- big-endian uint16
local hi, lo = string.byte(packed, 1, 2)
assert(hi == 1 and lo == 2)
local v = string.unpack("<i4", string.pack("<i4", -5))
assert(v == -5)
assert(string.packsize("i4i8") == 12)
-- несколько значений; unpack возвращает также позицию следующего байта
local blob = string.pack("<BHd", 7, 1000, 0.5)
local a, b, c, nextPos = string.unpack("<BHd", blob)
assert(a == 7 and b == 1000 and c == 0.5 and nextPos == #blob + 1)
-- строки: z = zero-terminated, s1 = с префиксом длины в 1 байт
local s = string.pack("s1", "hey")
assert(#s == 4 and string.unpack("s1", s) == "hey")
```

Основные коды формата: `<` `>` `=` (порядок байт), `b/B` int8/uint8, `h/H` int16/uint16,
`i4/I4`, `i8`, `f` float32, `d` float64, `s1/s2/s4` строка с длиной, `z` нуль-терминированная, `x` байт-заполнитель.

---

## 3. string.format: спецификаторы и ловушки

```luau
--!strict
-- @run
local f = string.format
-- целые
assert(f("%d", 42) == "42" and f("%i", 7) == "7")
assert(f("%5d|%-5d|%05d", 42, 42, 42) == "   42|42   |00042")
assert(f("%+d % d", 5, 5) == "+5  5")
assert(f("%03d", -7) == "-07")
assert(f("%d", 3.7) == "3" and f("%d", -3.7) == "-3") -- усечение к нулю, НЕ ошибка
assert((f :: any)("%d", "12") == "12") -- строка-число приводится в рантайме (тайпчекер такое запрещает)
-- hex / octal / char
assert(f("%x|%X|%o|%c", 255, 255, 8, 65) == "ff|FF|10|A")
assert(f("%08X", 0xBEEF) == "0000BEEF")
-- float
assert(f("%.2f", 3.14159) == "3.14")
assert(f("%5.2f", 3.14159) == " 3.14")
assert(f("%05.1f", 3.14159) == "003.1")
assert(f("%e", 12345.678) == "1.234568e+04")
assert(f("%g|%g|%g", 0.0001, 1e20, 123456789) == "0.0001|1e+20|1.23457e+08")
-- округление в %.Nf: по двоичному значению, точные половины -> к чётному
assert(f("%.0f", 2.5) == "2" and f("%.0f", 3.5) == "4")
assert(f("%.1f", 0.25) == "0.2") -- 0.25 точно представимо -> к чётному
assert(f("%.1f", 0.15) == "0.1") -- 0.15 на деле 0.1499999...
-- строки
assert(f("%s|%5s|%-5s|", "ab", "ab", "ab") == "ab|   ab|ab   |")
assert(f("%.3s", "abcdef") == "abc")
assert((f :: any)("%s", 12) == "12") -- number допустим в рантайме; тайпчекер для литерального формата требует string
-- %s с НЕ строкой/числом -> ошибка (даже с __tostring)
assert(not pcall(f, "%s", true))
assert(not pcall(f, "%s", nil))
assert(not pcall(f, "%s", {}))
-- %* (Luau): tostring любого значения
assert(f("%*|%*|%*", true, nil, 1.5) == "true|nil|1.5")
-- %q: строка в кавычках, пригодная как Luau-литерал
assert(f("%q", 'a"b') == '"a\\"b"')
-- %% — литерал процента
assert(f("%d%%", 50) == "50%")
-- неподдерживаемое: %a
assert(not pcall(f, "%a", 1))
-- ширина считает БАЙТЫ: кириллица "Привет" = 12 байт, выравнивание ломается
assert(f("%-10s|", "Привет") == "Привет|")
```

Правила:
- luau-lsp в `--!strict` **проверяет литеральную форматную строку**: `string.format("%d", "12")` и
  `string.format("%s", 12)` — TypeError, хотя в рантайме работают. Передавай ровно ожидаемые типы.
- Для логов с произвольными значениями: `string.format("hp=%* target=%*", hp, target)` или интерполяция
  `` `hp={hp}` `` (интерполяция сама вызывает `tostring`).
- Для денег/очков — целые числа и `%d`; дробные валюты хранить в целых «центах».
- Выравнивание таблиц с кириллицей через `%-Ns` не работает — считай длину через `utf8.len`.

---

## 4. Паттерны: полный синтаксис

Luau-паттерны — это **не** regex: нет `|` (альтернативы), нет `{n,m}`, квантификаторы применяются к
одному символу/классу, а не к группе.

| Элемент | Значение |
|---|---|
| `.` | любой байт |
| `%a` `%d` `%l` `%u` `%s` `%w` `%x` `%p` `%c` `%g` | буквы, цифры, строчные, заглавные, пробельные, буквы+цифры, hex-цифры, пунктуация, управляющие, печатаемые кроме пробела (**только ASCII**) |
| `%A` `%D` … (заглавная) | дополнение класса (`%S` — не пробел) |
| `%x` где x — не буква/цифра | литерал x: `%.` `%%` `%(` `%-` `%[` |
| `[abc]` `[a-z]` `[%w_]` | набор |
| `[^...]` | дополнение набора |
| `^` в начале / `$` в конце | якоря (в `gmatch` `^` не работает) |
| `*` | 0+ повторов, жадно |
| `+` | 1+ повторов, жадно |
| `-` | 0+ повторов, **лениво** |
| `?` | 0 или 1 |
| `( )` | захват; `()` пустой — захват **позиции** |
| `%1`..`%9` | обратная ссылка на захват внутри паттерна |
| `%b()` | сбалансированная пара символов |
| `%f[set]` | frontier: граница, где предыдущий символ не в set, а следующий — в set |

Магические символы, которые надо экранировать `%`: `^ $ ( ) % . [ ] * + - ?`.

```luau
--!strict
-- @run
-- классы
assert((("a b\tc\n"):gsub("%s", "")) == "abc")
assert((("a,b.c!"):gsub("%p", "")) == "abc")
assert((("ff 1G"):gsub("%x", "#")) == "## #G")
assert((("\1a\2"):gsub("%c", "")) == "a")
assert((("a b"):gsub("%g", "X")) == "X X")
assert((("Привет abc"):gsub("%a", "#")) == "Привет ###") -- кириллица не %a

-- наборы и дополнения
assert(("user_42"):match("^[%w_]+$") == "user_42")
assert(("user-42"):match("^[%w_]+$") == nil)
assert((("[test]"):gsub("[%[%]]", "")) == "test")
assert(("abc123"):match("[^%a]+") == "123")

-- жадный vs ленивый
assert(("hello"):match(".*l") == "hell")
assert(("hello"):match(".-l") == "hel")
assert(("<a><b>"):match("<(.-)>") == "a")
assert(("<a><b>"):match("<(.*)>") == "a><b")
-- ? — опциональный символ
assert(select(2, ("color colour"):gsub("colou?r", "C")) == 2)

-- якоря
assert(("abc"):match("^b") == nil)
assert(("abc"):match("c$") == "c")

-- захват позиции
local p1, p2 = string.match("hello", "()ll()")
assert(p1 == 3 and p2 == 5)

-- обратная ссылка: одинаковые кавычки
local _, quoted = string.match([[say "hi" now]], "([\"'])(.-)%1")
assert(quoted == "hi")

-- %b: сбалансированные скобки
assert(string.match("f(a(b)c) d", "%b()") == "(a(b)c)")

-- %f: целые слова
local replaced, n = string.gsub("THE (quick) fox", "%f[%a]%a+", "W")
assert(replaced == "W (W) W" and n == 3)
assert(select(2, string.gsub("cat concat cat", "%f[%w]cat%f[%W]", "")) == 2) -- только слово "cat"

-- экранирование
assert(("a-b"):find("%-") == 2)
assert(("1+1=2"):match("1%+1") == "1+1")
-- ошибки синтаксиса паттерна
assert(not pcall(string.find, "a", "[a"))  -- malformed pattern (missing ']')
assert(not pcall(string.find, "a", "%"))   -- malformed pattern (ends with '%')
```

**Нет альтернативы `|`.** Вместо `(cat|dog)` — несколько проверок или таблица допустимых значений:

```lua
-- ПЛОХО: string.match(word, "^(cat|dog)$") — "|" здесь обычный символ, паттерн ищет строку "cat|dog".
-- ХОРОШО:
local ALLOWED = { cat = true, dog = true }
if ALLOWED[word] then
	-- ...
end
```

---

## 5. Строковые рецепты (StringUtil)

Каждая функция доказана `@run`-тестом; ниже собранный модуль для копирования.

```luau
--!strict
-- @run
local function trim(s: string): string
	return (string.match(s, "^%s*(.-)%s*$")) :: string
end

local function startsWith(s: string, prefix: string): boolean
	return string.sub(s, 1, #prefix) == prefix
end

local function endsWith(s: string, suffix: string): boolean
	-- ЛОВУШКА: string.sub(s, -0) вернёт ВСЮ строку, поэтому пустой суффикс обрабатываем отдельно
	return suffix == "" or string.sub(s, -#suffix) == suffix
end

local function escapePattern(s: string): string
	return (string.gsub(s, "[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
end

local function countOccurrences(s: string, needle: string): number
	if needle == "" then
		return 0
	end
	local count, init = 0, 1
	while true do
		local _, e = string.find(s, needle, init, true)
		if not e then
			return count
		end
		count += 1
		init = e + 1
	end
end

local function splitPattern(s: string, sepPattern: string): { string }
	local out = {}
	local init = 1
	while true do
		local a, b = string.find(s, sepPattern, init)
		if a == nil or b == nil or b < a then -- b < a: паттерн сматчил пустую строку, прекращаем
			table.insert(out, string.sub(s, init))
			return out
		end
		table.insert(out, string.sub(s, init, a - 1))
		init = b + 1
	end
end

local function capitalize(s: string): string
	return (string.gsub(s, "^%l", string.upper)) -- ASCII only
end

local function titleCase(s: string): string
	local result = string.gsub(s, "(%a)([%w']*)", function(first: string, rest: string): string
		return first:upper() .. rest:lower()
	end :: any)
	return result
end

assert(trim("  hi there \n") == "hi there")
assert(trim("") == "" and trim("   ") == "")
assert(startsWith("ServerScript", "Server") and not startsWith("a", "abc"))
assert(endsWith("file.luau", ".luau") and endsWith("x", "") and not endsWith("x", "xx"))
assert(string.sub("hello", -0) == "hello") -- доказательство ловушки из endsWith
assert(escapePattern("1+1=2?") == "1%+1=2%?")
assert(string.find("price: 1+1=2? yes", escapePattern("1+1=2?")) == 8)
assert(countOccurrences("a.b.c", ".") == 2 and countOccurrences("aaaa", "aa") == 2)
local p = splitPattern("a, b,c ,  d", "%s*,%s*")
assert(#p == 4 and p[1] == "a" and p[2] == "b" and p[3] == "c" and p[4] == "d")
local q = splitPattern("one  two\tthree", "%s+")
assert(#q == 3 and q[3] == "three")
assert(capitalize("hello world") == "Hello world")
assert(titleCase("hELLO wORLD it's") == "Hello World It's")
```

### Числа: разделители тысяч, сокращения, время

```luau
--!strict
-- @run
local function formatThousands(n: number, sep: string?): string
	local separator = string.gsub(sep or ",", "%%", "%%%%") -- экранируем "%" для строки замены
	local sign = if n < 0 then "-" else ""
	local digits = string.format("%d", math.abs(n)) -- дробную часть отбрасываем
	local k
	repeat
		digits, k = string.gsub(digits, "^(%d+)(%d%d%d)", "%1" .. separator .. "%2")
	until k == 0
	return sign .. digits
end

local SUFFIXES = { "K", "M", "B", "T", "Qa", "Qi" }

local function abbreviate(n: number): string
	local sign = if n < 0 then "-" else ""
	local a = math.abs(n)
	if a < 1000 then
		return sign .. tostring(math.floor(a))
	end
	local tier, unit = 0, 1
	while a >= unit * 1000 and tier < #SUFFIXES do
		unit *= 1000
		tier += 1
	end
	-- округляем до десятых ДОЛИ единицы; a / (unit / 10) точно для целых a
	local tenths = math.floor(a / (unit / 10) + 0.5)
	if tenths >= 10000 and tier < #SUFFIXES then
		-- 999_950 -> 1000.0K -> переносим на следующий разряд: 1.0M
		unit *= 1000
		tier += 1
		tenths = math.floor(a / (unit / 10) + 0.5)
	end
	return string.format("%s%.1f%s", sign, tenths / 10, SUFFIXES[tier])
end

local function formatClock(totalSeconds: number): string
	local s = math.max(0, math.floor(totalSeconds))
	local h = s // 3600
	local m = (s % 3600) // 60
	local sec = s % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, sec)
	end
	return string.format("%02d:%02d", m, sec)
end

assert(formatThousands(1234567) == "1,234,567")
assert(formatThousands(-1000) == "-1,000")
assert(formatThousands(999) == "999" and formatThousands(0) == "0")
assert(formatThousands(1234567, " ") == "1 234 567") -- русский стиль
assert(formatThousands(1234.99) == "1,234")

assert(abbreviate(999) == "999")
assert(abbreviate(1000) == "1.0K")
assert(abbreviate(1234) == "1.2K")
assert(abbreviate(1250) == "1.3K") -- половина вверх
assert(abbreviate(999_949) == "999.9K")
assert(abbreviate(999_950) == "1.0M") -- граница: без переноса было бы "1000.0K"
assert(abbreviate(3_400_000) == "3.4M")
assert(abbreviate(1e9) == "1.0B")
assert(abbreviate(-2500) == "-2.5K")

assert(formatClock(0) == "00:00")
assert(formatClock(65) == "01:05")
assert(formatClock(3599) == "59:59")
assert(formatClock(3600) == "1:00:00")
assert(formatClock(3725.9) == "1:02:05") -- дробные секунды отбрасываются
assert(formatClock(-5) == "00:00")
-- Для ОБРАТНОГО отсчёта показывай math.ceil(remaining), чтобы "00:00" появлялось ровно в конце:
assert(formatClock(math.ceil(0.2)) == "00:01")
```

### Парсинг и валидация

```luau
--!strict
-- @run
local function parseKeyValues(s: string): { [string]: string }
	local out: { [string]: string } = {}
	for key, value in string.gmatch(s, "([%w_]+)%s*=%s*([^;]*)") do
		out[key] = (string.match(value :: string, "^%s*(.-)%s*$")) :: string
		-- gmatch в типах Roblox возвращает string?, отсюда касты
	end
	return out
end

local cfg = parseKeyValues("speed = 16; name=Bob Smith ;  debug=true")
assert(cfg.speed == "16" and cfg.name == "Bob Smith" and cfg.debug == "true")

-- Валидация "тега" своей системы: 3..20 символов ASCII, буквы/цифры/_, "_" не по краям, максимум один "_".
local function isValidTag(name: string): boolean
	if #name < 3 or #name > 20 then
		return false
	end
	if not string.match(name, "^[%w_]+$") then
		return false
	end
	if string.sub(name, 1, 1) == "_" or string.sub(name, -1) == "_" then
		return false
	end
	local _, underscores = string.gsub(name, "_", "")
	return underscores <= 1
end

assert(isValidTag("Player_1"))
assert(not isValidTag("ab"))
assert(not isValidTag("_abc") and not isValidTag("abc_"))
assert(not isValidTag("a_b_c"))
assert(not isValidTag("Игрок1")) -- кириллица: %w её не матчит
assert(not isValidTag("abc def"))
```

Любой текст, введённый игроком и показываемый другим игрокам, обязательно фильтруется через
`TextService:FilterStringAsync` (см. [../handbook/40-text-safety.md](../handbook/40-text-safety.md)).
Паттерн-валидация формата не заменяет фильтрацию.

### Собранный модуль StringUtil

```luau
--!strict
-- @path ReplicatedStorage/StdUtil/StringUtil
-- ModuleScript: ReplicatedStorage/StdUtil/StringUtil. Pure functions, usable on server and client.
local StringUtil = {}

function StringUtil.trim(s: string): string
	return (string.match(s, "^%s*(.-)%s*$")) :: string
end

function StringUtil.startsWith(s: string, prefix: string): boolean
	return string.sub(s, 1, #prefix) == prefix
end

function StringUtil.endsWith(s: string, suffix: string): boolean
	return suffix == "" or string.sub(s, -#suffix) == suffix
end

function StringUtil.escapePattern(s: string): string
	return (string.gsub(s, "[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
end

function StringUtil.countOccurrences(s: string, needle: string): number
	if needle == "" then
		return 0
	end
	local count, init = 0, 1
	while true do
		local _, e = string.find(s, needle, init, true)
		if not e then
			return count
		end
		count += 1
		init = e + 1
	end
end

function StringUtil.splitPattern(s: string, sepPattern: string): { string }
	local out = {}
	local init = 1
	while true do
		local a, b = string.find(s, sepPattern, init)
		if a == nil or b == nil or b < a then
			table.insert(out, string.sub(s, init))
			return out
		end
		table.insert(out, string.sub(s, init, a - 1))
		init = b + 1
	end
end

function StringUtil.formatThousands(n: number, sep: string?): string
	local separator = string.gsub(sep or ",", "%%", "%%%%")
	local sign = if n < 0 then "-" else ""
	local digits = string.format("%d", math.abs(n))
	local k
	repeat
		digits, k = string.gsub(digits, "^(%d+)(%d%d%d)", "%1" .. separator .. "%2")
	until k == 0
	return sign .. digits
end

local SUFFIXES = { "K", "M", "B", "T", "Qa", "Qi" }

function StringUtil.abbreviate(n: number): string
	local sign = if n < 0 then "-" else ""
	local a = math.abs(n)
	if a < 1000 then
		return sign .. tostring(math.floor(a))
	end
	local tier, unit = 0, 1
	while a >= unit * 1000 and tier < #SUFFIXES do
		unit *= 1000
		tier += 1
	end
	local tenths = math.floor(a / (unit / 10) + 0.5)
	if tenths >= 10000 and tier < #SUFFIXES then
		unit *= 1000
		tier += 1
		tenths = math.floor(a / (unit / 10) + 0.5)
	end
	return string.format("%s%.1f%s", sign, tenths / 10, SUFFIXES[tier])
end

function StringUtil.formatClock(totalSeconds: number): string
	local s = math.max(0, math.floor(totalSeconds))
	local h = s // 3600
	local m = (s % 3600) // 60
	local sec = s % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, sec)
	end
	return string.format("%02d:%02d", m, sec)
end

-- Truncate to at most maxChars UTF-8 code points (see section 6). Invalid UTF-8 falls back to bytes.
function StringUtil.truncateUtf8(s: string, maxChars: number, ellipsis: string?): string
	local length = utf8.len(s)
	if length == nil then
		return string.sub(s, 1, maxChars)
	end
	if length <= maxChars then
		return s
	end
	local suffix = ellipsis or "…"
	local keep = math.max(0, maxChars - (utf8.len(suffix) or 0))
	local cut = utf8.offset(s, keep + 1) :: number
	return string.sub(s, 1, cut - 1) .. suffix
end

return StringUtil
```

---

## 6. utf8 и русский текст / эмодзи

Строки Luau — массивы байт. Кириллический символ в UTF-8 занимает 2 байта, большинство эмодзи — 4,
составные эмодзи (с модификатором кожи, ZWJ-семьи) — несколько code points. `string.sub`, `#`,
`string.len`, `%-10s`, `string.reverse`, `split("")` работают с байтами и **режут символы пополам**,
что даёт «�» в TextLabel.

```luau
--!strict
-- @run
local s = "Привет, мир! 🙂"
assert(#s == 26)           -- байты
assert(utf8.len(s) == 14)  -- code points

-- string.sub режет символ пополам: "П" (2 байта) + первый байт "р"
local broken = string.sub(s, 1, 3)
assert(utf8.len(broken) == nil) -- невалидный UTF-8: len возвращает nil (+ позицию ошибки)

-- utf8.offset(s, n): байтовая позиция n-го символа
assert(utf8.offset(s, 1) == 1)
assert(utf8.offset(s, 3) == 5)
assert(utf8.offset(s, -1) == 23) -- начало последнего символа (эмодзи)

-- utf8.codes: итерация (byteIndex, codepoint)
local cps = {}
for pos, cp in utf8.codes("Пр") do
	table.insert(cps, `{pos}:{cp}`)
end
assert(table.concat(cps, ",") == "1:1055,3:1088")

-- codepoint / char
assert(utf8.codepoint("П") == 1055)
assert(utf8.char(1055, 128578) == "П🙂")
local a, b = utf8.codepoint("ab", 1, 2)
assert(a == 97 and b == 98)
assert(not pcall(utf8.codepoint, "\xff")) -- invalid UTF-8 code

-- charpattern: паттерн одного UTF-8 символа
local n = 0
for _ in string.gmatch("Ёж🙂", utf8.charpattern) do
	n += 1
end
assert(n == 3)

-- составные эмодзи: несколько code points на один видимый символ
assert(utf8.len("👍🏽") == 2)
assert(utf8.len("👨‍👩‍👧") == 5)
```

### Безопасная обрезка для UI

```luau
--!strict
-- @run
local function truncateUtf8(s: string, maxChars: number, ellipsis: string?): string
	local length = utf8.len(s)
	if length == nil then
		return string.sub(s, 1, maxChars) -- невалидный UTF-8: хотя бы не падаем
	end
	if length <= maxChars then
		return s
	end
	local suffix = ellipsis or "…"
	local keep = math.max(0, maxChars - (utf8.len(suffix) or 0))
	local cut = utf8.offset(s, keep + 1) :: number
	return string.sub(s, 1, cut - 1) .. suffix
end

local name = "Александр Великий"
local short = truncateUtf8(name, 10)
assert(short == "Александр…")
assert(utf8.len(short) == 10)
assert(truncateUtf8("Кот", 10) == "Кот")
assert(truncateUtf8("🙂🙂🙂🙂", 3, "") == "🙂🙂🙂")
assert(utf8.len(truncateUtf8("🙂🙂🙂🙂", 3)) == 3)

-- Посимвольный reverse (string.reverse ломает кириллицу)
local function reverseUtf8(str: string): string
	local chars = {}
	for _, cp in utf8.codes(str) do
		table.insert(chars, 1, utf8.char(cp))
	end
	return table.concat(chars)
end
assert(reverseUtf8("Привет") == "тевирП")
assert(utf8.len(string.reverse("Привет")) == nil) -- байтовый reverse даёт мусор
```

Что ещё важно для UI с русским текстом:
- Верхний регистр кириллицы стандартными функциями не сделать (`upper` — только ASCII). Для заголовков
  используй свойство шрифта/текста или заранее подготовленные строки.
- Составные эмодзи обрезка по code points может разорвать (👍 + 🏽). В Roblox есть
  `utf8.graphemes(s)` (итератор по графемам, есть в типах Roblox, в CLI Luau отсутствует) — для
  «видимых символов» используй его; проверь поведение в Studio.
- Ограничение длины ввода TextBox делай по `utf8.len`, а не по `#`: иначе русскому игроку
  «помещается» вдвое меньше символов.

```lua
-- Roblox-only (нет в CLI): подсчёт видимых символов
local function graphemeCount(s: string): number
	local n = 0
	for _first, _last in utf8.graphemes(s) do
		n += 1
	end
	return n
end
```

---

## 7. tonumber/tostring: ловушки ввода

```luau
--!strict
-- @run
assert(tonumber("12") == 12 and tonumber(" 12 ") == 12)
assert(tonumber("0x1F") == 31 and tonumber("1e3") == 1000)
assert(tonumber("12a") == nil and tonumber("") == nil)
assert(tonumber("1_000") == nil) -- "_" допустим только в литералах исходника: 1_000
assert(tonumber("z", 36) == 35)
-- ОПАСНО для серверной валидации: строки "inf" и "nan" превращаются в числа
local inf = tonumber("inf") :: number
local nan = tonumber("nan") :: number
assert(inf == math.huge)
assert(nan ~= nan)

-- правильная проверка числа из недоверенного источника
local function toFiniteNumber(v: unknown): number?
	local n = if type(v) == "number" then v elseif type(v) == "string" then tonumber(v) else nil
	if n == nil or n ~= n or n == math.huge or n == -math.huge then
		return nil
	end
	return n
end
assert(toFiniteNumber("5") == 5)
assert(toFiniteNumber("nan") == nil and toFiniteNumber(1 / 0) == nil and toFiniteNumber({}) == nil)

-- tostring
assert(tostring(12.0) == "12")
assert(tostring(0.1 + 0.2) == "0.30000000000000004")
assert(tostring(1e15) == "1000000000000000" and tostring(2 ^ 53) == "9007199254740992")
assert(tostring(-0) == "-0")
assert(tostring(nil) == "nil")
```

Сравнение `n ~= n` — канонический тест на NaN (работает везде). `math.isnan/isinf/isfinite`
тоже существуют (раздел 10).

---

