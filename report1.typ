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
= Выполнение

Сделал API для личных заметок на Flask. В SQLite две таблицы: пользователи и заметки. У каждой заметки есть владелец. Проверил три метода через `curl`.

== Запуск и вход

Установил зависимости из `requirements.txt`, задал случайный ключ `JWT_SECRET` и создал пользователя командой `flask --app app create-user student`. Пароль вводится в терминале. Запустил приложение через `flask --app app run`.

```
url=http://127.0.0.1:5000
curl -i "$url/api/data"
```
Без токена сервер вернул `401` и сообщение `bearer token required`. Затем отправил логин и пароль. В примере вместо пароля стоит `ПАРОЛЬ`.

```
token=$(curl -s "$url/auth/login" \
  --json '{"login":"student","password":"ПАРОЛЬ"}' | jq -r .token)
```
При верном пароле получил `200` и JWT. Сервер подписывает его алгоритмом HS256 с ключом из `JWT_SECRET`. В токене записаны номер пользователя и срок действия — 30 минут. Оба метода работы с заметками проверяют подпись и срок.

== Запись и чтение заметки

```
curl -i "$url/api/data" -H "Authorization: Bearer $token" \
  --json '{"text":"Сдать <ИБ> & ОПД"}'
curl -s "$url/api/data" -H "Authorization: Bearer $token" | jq .
```
Первый запрос вернул `201` и номер заметки `1`. Во втором получил `200`. Вот текст из ответа после разбора JSON:

```
[{"id":1,"text":"Сдать &lt;ИБ&gt; &amp; ОПД"}]
```
Угловые скобки и амперсанд экранируются через `html.escape` при чтении. В базе остаётся исходный текст. Логин, текст заметки и идентификатор владельца передаются в SQL отдельно через параметры `?`. Для чтения сервер берёт владельца из проверенного JWT:

#raw("SELECT id, text FROM notes WHERE owner = ? ORDER BY id", block: true)
Пароли хранятся в виде scrypt-хэшей с индивидуальной солью. Четыре автотеста проверяют в том числе отказ при неверном пароле, просроченном токене или другой подписи. Под вторым пользователем список заметок остался пустым.

#pagebreak()
= Проверки в GitHub Actions

При `push` и `pull_request` запускаются тесты и два сканера. Bandit проверил 98 строк в `app.py` и не выдал замечаний.

#figure(image("figures/bandit.png", width: 78%), caption: [Вывод Bandit из #ref(repo + "/actions/runs/45585964740/job/139107535760", [запуска №3]).])

OWASP Dependency-Check проверил восемь пакетов, включая транзитивные зависимости. Критических находок нет. Для PyJWT 2.15.1 сканер указал CVE-2025-45770 с оценкой 7,0. В #ref("https://www.cve.org/CVERecord?id=CVE-2025-45770", [карточке CVE]) указан PHP-пакет `lcobucci/jwt`; в проекте установлен Python-пакет `PyJWT`. Оставил это совпадение в отчёте сканера.

#figure(image("figures/dependency-check.png", width: 100%), caption: [Отчёт OWASP Dependency-Check из #ref(repo + "/actions/runs/45585964740/job/139107535219", [запуска №3]).])

#ref(repo, [Репозиторий с кодом и README]) #h(6pt) · #h(6pt) #ref(run, [Запуск GitHub Actions для этой версии отчёта])
