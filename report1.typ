#set document(title: "ЛР1. Разработка защищенного REST API с интеграцией в CI/CD", author: "Чусовлянов Максим Сергеевич")
#set page(paper: "a4", margin: (x: 22mm, top: 20mm, bottom: 19mm))
#set text(font: "Libertinus Serif", size: 13pt, lang: "ru")
#set par(justify: true, leading: 0.55em)
#show heading.where(level: 1): set text(size: 16pt)
#show heading.where(level: 2): set text(size: 13pt)
#show raw: set text(size: 9pt)
#show figure.caption: set text(size: 10.5pt)
#set figure(gap: 5pt)
#let repo = "https://github.com/Vaneshik/infosec-lab1"
#let run = sys.inputs.at("run-url")
#let ref(url, body) = link(url, underline(body))

#align(center)[
  Федеральное государственное автономное образовательное учреждение высшего образования
  «Национальный исследовательский университет ИТМО»
  #v(49mm)
  *Информационная безопасность*

  #v(7mm)
  #text(size: 17pt, weight: "bold")[Работа 1. Разработка защищенного REST API #linebreak() с интеграцией в CI/CD]
]
#v(24mm)
#align(right)[Выполнил: Чусовлянов Максим Сергеевич #linebreak() Группа P3407]
#v(1fr)
#align(center)[Санкт-Петербург #linebreak() 2026]

#pagebreak()
#set page(numbering: "1")
= Методы API

Сделал на Flask API для личных заметок. Сначала пользователь входит по логину и паролю, затем с полученным токеном добавляет и читает свои заметки. Сервер принимает и возвращает JSON.

#block[
  #set text(size: 11pt)
  #set par(justify: false)
  #table(
    columns: (33%, 32%, 35%), inset: 6pt, stroke: 0.45pt + gray,
    table.header([*Метод и путь*], [*Что передаём*], [*Ответ при успехе*]),
    [`POST /auth/login` \ Вход], [Поля `login` и `password`. Токен для входа не нужен.], [`200 OK` \ `{"token":"…"}`],
    [`POST /api/data` \ Добавить заметку], [Поле `text` с текстом заметки и токен в заголовке.], [`201 Created` и номер новой заметки, например `{"id":1}`.],
    [`GET /api/data` \ Прочитать заметки], [Только токен в заголовке. Тело запроса пустое.], [`200 OK` и массив объектов с полями `id`, `text`. Пока записей нет, ответ — `[]`.],
  )
]

== Как вызвать методы

В первом терминале установил зависимости, создал пользователя `student` и запустил сервер. Ключ подписи сгенерировал локально, пароль задал по запросу команды `create-user`.

```
python3 -m venv .venv && . .venv/bin/activate
pip install -r requirements.txt
export JWT_SECRET="$(python -c 'import secrets; print(secrets.token_hex(32))')"
flask --app app create-user student
flask --app app run
```

Во втором терминале отправил логин и пароль. Вместо `ПАРОЛЬ` подставил значение из предыдущего шага. Из поля `token` в ответе взял JWT для следующих двух запросов.

```
url=http://127.0.0.1:5000
token=$(curl -s -X POST "$url/auth/login" \
  --json '{"login":"student","password":"ПАРОЛЬ"}' | jq -r .token)
```
Добавил заметку и запросил список с тем же токеном.

```
curl -i -X POST "$url/api/data" -H "Authorization: Bearer $token" \
  --json '{"text":"Сдать <ИБ> & ОПД"}'
curl -s -X GET "$url/api/data" -H "Authorization: Bearer $token" | jq .
```
При записи получил `201` и `{"id":1}`. При чтении сервер вернул `200` и ту же заметку с экранированным текстом.

```
[{"id":1,"text":"Сдать &lt;ИБ&gt; &amp; ОПД"}]
```
#pagebreak()
= Хранение данных и защита

== Пароль и токен

В таблице `users` хранятся номер пользователя, логин и хэш пароля. При создании пользователя функция `generate_password_hash(password, method="scrypt")` генерирует соль и вычисляет хэш. При входе сервер ищет запись по логину и вызывает `check_password_hash`. Если пароль подошёл, сервер выдаёт JWT на 30 минут. В поле `sub` записан номер пользователя, в `exp` — время окончания действия токена.

Оба обработчика `/api/data` используют декоратор `@authenticated`. Он берёт токен из заголовка `Authorization: Bearer <токен>`, проверяет подпись HS256 ключом из `JWT_SECRET` и проверяет срок. Только после этого номер из `sub` попадает в `g.owner`.

== Свои заметки и защита от SQL-инъекций

В таблице `notes` у каждой записи есть поля `id`, `owner` и `text`. При создании заметки владельца подставляет сервер. При чтении SQLite выбирает строки по тому же номеру. Значения передаются отдельно от текста запроса через параметры `?`, поэтому кавычка в заметке остаётся частью текста.

```python
connection.execute("INSERT INTO notes (owner, text) VALUES (?, ?)", (g.owner, text))
db().execute("SELECT id, text FROM notes WHERE owner = ? ORDER BY id", (g.owner,))
```

== Экранирование текста для защиты от XSS

В базе хранится исходная строка. Перед выдачей JSON сервер применяет `html.escape` к тексту каждой заметки. Поэтому при чтении заметки со страницы 2 вместо `<ИБ>` пришло `&lt;ИБ&gt;`, а вместо `&` — `&amp;`.

== Проверка доступа и ошибок

Для проверки создал двух пользователей во временной базе. Проверил, что происходит при неверном пароле, недействительном токене и попытке прочитать список с другого аккаунта.

#block[
  #set text(size: 11pt)
  #set par(justify: false)
  #table(
    columns: (52%, 48%), inset: 5pt, stroke: 0.45pt + gray,
    table.header([*Что проверил*], [*Что вернул сервер*]),
    [Вход с неверным паролем], [`401`, сообщение `invalid credentials`.],
    [Чтение и запись без токена, с истёкшим сроком или с другой подписью], [`401` в каждом случае. Попытки записи не добавили заметку.],
    [Чтение из второго аккаунта после записи из первого], [`200` и пустой список `[]`. Первый пользователь по-прежнему видел свою запись.],
    [Создание заметки из одних пробелов], [`400`, сообщение `text required`. Список заметок остался пустым.],
  )
]

#pagebreak()
= Проверки в GitHub Actions

При `push` и `pull_request` GitHub Actions запускает четыре автотеста и два сканера. Bandit проверил 98 строк в `app.py` и не выдал замечаний. Для проверки зависимостей CI скачивает пакеты из `requirements.txt` и передаёт их OWASP Dependency-Check. Находка с оценкой CVSS от 9 останавливает сборку отчёта.

#figure(image("figures/bandit.png", width: 78%), caption: [Вывод Bandit из #ref(repo + "/actions/runs/45585964740/job/139107535760", [запуска №3]).])

OWASP Dependency-Check проверил восемь пакетов, включая транзитивные зависимости. Критических находок нет. Для PyJWT 2.15.1 сканер указал CVE-2025-45770 с оценкой 7,0. В #ref("https://www.cve.org/CVERecord?id=CVE-2025-45770", [карточке CVE]) указан PHP-пакет `lcobucci/jwt`; в проекте установлен Python-пакет `PyJWT`. Оставил это совпадение в отчёте сканера.

#figure(image("figures/dependency-check.png", width: 100%), caption: [Отчёт OWASP Dependency-Check из #ref(repo + "/actions/runs/45585964740/job/139107535219", [запуска №3]).])

= Вывод

Проверил API под двумя учётными записями. Каждый пользователь видел только свои заметки, а с просроченным токеном сервер возвращал `401`. На примере PyJWT увидел, зачем сверять пакет из карточки CVE с библиотекой, установленной в проекте.

- #ref(repo, [Репозиторий с кодом и README])
- #ref(run, [Успешный запуск GitHub Actions])
