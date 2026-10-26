# Сервисная SSH-учётка `zfs-repl`

Используется для ZFS-репликации `fbsd-1-sel → fbsd-2-sel`. Принимает только одну команду
(`zfs receive`) и только с IP master-ноды. Интерактивного шелла нет, `sudo` не требуется.

## Параметры пользователя

| Поле | Значение |
|---|---|
| username | `zfs-repl` |
| home | `/home/zfs-repl` |
| shell | `/bin/sh` |
| comment | "ZFS replication service account" |
| авторизация | ed25519-ключ + сертификат CA (principal=`zfs-repl`), TOTP **не используется** |

> **Почему шелл, а не `/sbin/nologin`.** `force-command` sshd выполняет **через login-shell**
> пользователя. С `/sbin/nologin` принудительная команда не запустится вообще — сессия
> завершится с «This account is currently not available». Ограничение «никакого шелла»
> обеспечивается не шеллом, а опцией `no-pty` плюс тем, что `force-command` подменяет
> любую команду клиента. Это отличается от первоначального плана Фазы 1, где был указан
> `nologin` — на практике это оказалось нерабочим.

## Ключ и сертификат

- Тип: ed25519
- Приватный ключ: **`/root/.ssh/zfs_repl` на fbsd-1-sel** (master), chmod 600
- Публичный ключ: `/root/.ssh/zfs_repl.pub`
- Сертификат: `/root/.ssh/zfs_repl-cert.pub` (подписан `fbsd-ca-sel`, principal=`zfs-repl`, TTL 52w)

> **Почему ключ на master, а не на ноутбуке.** Ограничение `from="172.16.0.2"` разрешает
> вход только с master-ноды. Если хранить приватный ключ на Mac M4 и запускать репликацию
> оттуда, replica отклонит подключение — исходящий адрес ноутбука не `172.16.0.2`.
> Репликацию запускает master; это и есть production-подобная схема: в случае потери
> ноутбука реплика продолжает работать по расписанию.

## Настройка `/etc/ssh/sshd_config.d/ca.conf` на fbsd-2-sel

```sh
TrustedUserCAKeys /etc/ssh/ca/user_ca.pub
RevokedKeys /etc/ssh/ca/revoked_keys
HostCertificate /etc/ssh/ssh_host_ed25519_key-cert.pub
AuthorizedPrincipalsFile /etc/ssh/auth_principals/%u
```

`AuthorizedPrincipalsFile` — ключевая директива. Без неё ограничения, описанные ниже,
не применяются к входам по сертификату.

## `/etc/ssh/auth_principals/zfs-repl` на fbsd-2-sel

```sh
from="172.16.0.2",command="/usr/bin/env /sbin/zfs receive -F zroot/tank/repl",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty zfs-repl
```

Формат строки — как в `authorized_keys`, но **в конце вместо публичного ключа стоит имя
principal'а**. Права на файл и каталог:

```sh
sudo chmod 755 /etc/ssh/auth_principals
sudo chmod 644 /etc/ssh/auth_principals/zfs-repl
sudo chown root:wheel /etc/ssh/auth_principals/zfs-repl
```

| Опция | Зачем |
|---|---|
| `from="172.16.0.2"` | только с fbsd-1-sel (master) |
| `command="/usr/bin/env /sbin/zfs receive -F zroot/tank/repl"` | единственная разрешённая команда |
| `no-port-forwarding` | нельзя использовать как SOCKS-прокси |
| `no-X11-forwarding` | не запрашивает X11 |
| `no-agent-forwarding` | нельзя прокинуть ssh-agent |
| `no-pty` | не выделяет псевдо-терминал |
| `zfs-repl` | principal, к которому применяются все опции выше |

Обратите внимание: имя датасета в `force-command` — `zroot/tank/repl`, то есть полный
путь от корня пула. Ранние версии плана Фазы 1 указывали `tank/repl`, что не совпадало
с фактической иерархией и приводило к ошибке `cannot receive new filesystem stream`.

## Права на приём: `zfs allow`, а не sudo

На replica учётке `zfs-repl` выданы ZFS-права ровно на один датасет:

```sh
sudo zfs allow -u zfs-repl compression,mountpoint,mount,create,receive zroot/tank/repl
```

Этого достаточно, чтобы `zfs receive -F zroot/tank/repl` отработал от имени самого
`zfs-repl`. Права `create` и `mount` нужны потому, что при приёме потока ZFS создаёт
вложенные датасеты (снапшоты, клоны) и монтирует результат.

| Механизм | Даёт учётке | Итог |
|---|---|---|
| `sudoers`-правило `zfs-repl ALL=(root) NOPASSWD: /sbin/zfs receive *` | полноценный root на время команды | лишний: всякое `sudo` на этой учётке — дыра |
| `zfs allow` (используется) | операции **только** с `zroot/tank/repl` | принцип наименьших привилегий соблюдён |

sudoers-правило было создано на старте, но при переходе на `zfs allow` **удалено**.
Фактический способ повышения прав — механизм делегирования ZFS, а не sudo.

## Почему ограничения лежат здесь, а не в `authorized_keys`

Это главный грабль, на который наступили при настройке. Формулировка из опыта:

> **Если ограничения прописать в `authorized_keys` пользователя, то при аутентификации по
> сертификату они НЕ применяются.** Приоритет отдаётся авторизации по подписанному ключу.
> Ограничения из `authorized_keys` срабатывают только при входе «голым» ключом, без
> сертификата.

Причина в том, как sshd ищет опции для сертификата: он сопоставляет их не с публичным
ключом пользователя, а с **ключом CA**, которым подписан сертификат. Строка с публичным
ключом пользователя при входе по сертификату просто не читается как источник опций.

Два рабочих способа задать ограничения для сертификата:

1. **`AuthorizedPrincipalsFile /etc/ssh/auth_principals/%u`** — опции привязаны к
   конкретному principal'у. Выбран этот вариант: ограничения применяются только к
   `zfs-repl`, а не ко всем сертификатам нашего CA.
2. Строка в `authorized_keys` с **публичным ключом CA** (`user_ca.pub`) и опциями —
   ограничения применятся ко всем сертификатам, подписанным этим CA. Слишком широко,
   поэтому не используется.

## Что на fbsd-2-sel не используется

`/home/zfs-repl/.ssh/authorized_keys` **не создаётся**. Если бы файл существовал, то при
отзыве сертификата через CA (`revoke-ssh.sh`) вход по «голому» ключу всё равно остался бы
рабочим — обход отзыва. Отсутствие файла делает отзыв сертификата единственным рычагом
управления доступом этой учётки.

## Процедура переподписи

Каждые 52 недели:

```sh
ssh -i ~/.ssh/freebsd_lab-cert avalok11@fbsd-ca-sel.lab.sel \
    "sudo /usr/local/sshca/scripts/sign-user-cert.sh /tmp/zfs_repl.pub zfs-repl +52w zfs-repl"
```

> `fbsd-ca-sel` имеет публичный IP — `-J fbsd-1-sel` не нужен, вход с Mac M4 прямой.
> Четвёртый аргумент скрипта (`zfs-repl`) — имя каталога в
> `/usr/local/sshca/users/`, куда CA кладёт ключ и сертификат. Он должен совпадать с
> уже созданным каталогом, иначе получится вторая копия сертификата в другом месте.
> Скрипт неинтерактивный: раньше он спрашивал имя каталога через `read`, что ломало
> его работу из cron и Ansible.

Ограничения при этом **не меняются** — они живут в `auth_principals/zfs-repl` на сервере,
а не в сертификате. Это одно из преимуществ выбранной схемы: смена ограничений — правка
одного файла на сервере, без переподписи и без перекладывания сертификата на клиент.
После переподписи новый `-cert.pub` копируется на master в `/root/.ssh/`.

## Тесты

Проверяются ограничения сервисной учётки: по адресу источника (`from=`) и по
подмене команды (`force-command` + `no-pty`). Оба ловятся одним и тем же
`-v`-логом, поэтому это два теста, а не три. Каждый тест имеет цель,
проверяемую гипотезу и ожидаемый результат.

| # | Что проверяем | Откуда запускаем | Ожидаемый результат |
|---|---|---|---|
| 1 | `from="172.16.0.2"` отсекает чужие адреса | `fbsd-ca-sel` (172.16.0.3) | `Permission denied (publickey)` |
| 2 | `force-command` подменяет команду клиента и `no-pty` запрещает терминал | master, от root | `Remote: principals: key options: command user-rc` и отсутствие вывода `uid=` |

> **Тест 2 запускается с master и от root.** Ключ лежит в `/root/.ssh/`, обычному
> пользователю файл не читается, и `ssh` падает на чтении ключа — до установки
> соединения. Из-под обычного пользователя с ключом в `/root/.ssh/` grep не находит
> ничего: это не проблема доступа, а просто нечитаемый ключ.

### Тест 1 — ограничение по адресу источника

**Гипотеза.** `from="172.16.0.2"` — работающий барьер: даже валидно подписанный
сертификатом ключ с правильным principal не даёт доступ с чужого адреса.

**Важно:** тест обязан предъявлять **сертификат**, иначе он не проверяет ничего.
Клиент ssh ищет сертификат по шаблону `<имя_приватного_ключа>-cert.pub` рядом с
самим ключом. Если сертификат лежит отдельно, клиент предъявит «голый» публичный
ключ, sshd не найдёт для него `authorized_keys` (а его у `zfs-repl` намеренно нет) и
откажет — но по другой причине, чем `from=`. Подробно — в «Грабли».

```sh
# на fbsd-ca-sel
ssh-keygen -t ed25519 -f /tmp/zfs_repl_fromtest -N "" -C "from-test@ca-sel"
sudo /usr/local/sshca/scripts/sign-user-cert.sh \
     /tmp/zfs_repl_fromtest.pub zfs-repl +52w zfs_repl_fromtest

# сертификат КЛАДЁМ РЯДОМ с приватным ключом — иначе клиент его не подхватит
cp /usr/local/sshca/users/zfs_repl_fromtest/zfs_repl_fromtest-cert.pub \
   /tmp/zfs_repl_fromtest-cert.pub

ssh -v -i /tmp/zfs_repl_fromtest zfs-repl@172.16.0.4 id < /dev/null 2>&1 \
  | grep -E 'Offering|Server accepts|Permission denied'
```

Ожидаемый вывод — в строке `Offering` обязан быть **`ED25519-CERT`** и путь с
`-cert.pub`:

```
debug1: Offering public key: /tmp/zfs_repl_fromtest-cert.pub ED25519-CERT SHA256:...
zfs-repl@172.16.0.4: Permission denied (publickey).
```

Строки `Server accepts key` быть не должно — она означала бы, что ключ принят и
`from=` не сработал.

**Positive control (A/B).** Чтобы исключить «сертификат невалиден вообще»,
разрешаем `ca-sel` временно (через out-of-band консоль Selectel):

```sh
sudo cp /etc/ssh/auth_principals/zfs-repl /etc/ssh/auth_principals/zfs-repl.bak
sudo sed -i '' 's/from="172.16.0.2"/from="172.16.0.2",from="172.16.0.3"/' \
     /etc/ssh/auth_principals/zfs-repl
sudo service sshd reload
```

Повтор подключения с `ca-sel` теперь должен **не** давать `Permission denied`,
а показывать ошибку ZFS про невалидный поток — то есть аутентификация прошла, а
`force-command` исполнил `zfs receive` с пустым stdin. Разница между провалом и
успехом объясняется **только** `from=`.

```sh
sudo mv /etc/ssh/auth_principals/zfs-repl.bak /etc/ssh/auth_principals/zfs-repl
sudo service sshd reload
rm -f /tmp/zfs_repl_fromtest*
sudo rm -rf /usr/local/sshca/users/zfs_repl_fromtest
```

### Тест 2 — подмена команды клиента и запрет терминала

**Гипотеза.** `force-command` **заменяет** команду клиента целиком, а не дополняет
её: клиент просит `id` — выполняется `zfs receive`. И заодно: в действующем наборе
опций нет pty, то есть `no-pty` применился.

```sh
sudo ssh -v -i /root/.ssh/zfs_repl zfs-repl@172.16.0.4 id < /dev/null 2>&1 \
  | grep -E 'Authenticated|Remote: principals|Sending command|uid='
```

Ожидаемый вывод:

```
Authenticated to 172.16.0.4 ([172.16.0.4]:22) using "publickey".
debug1: Remote: principals: key options: command user-rc
debug1: Sending command: id
```

Строки `uid=` быть **не должно** — вместо неё придёт ошибка ZFS про невалидный
поток, потому что команда, которая реально выполнилась, была `zfs receive`.

> **Про строку `Sending command`.** Это вывод **клиента**: он всегда пишет, какую
> команду *просил* выполнить. Подменённую команду клиент не показывает — она
> подставляется на сервере. Поэтому искать в логе `Sending command: /usr/bin/env
> /sbin/zfs receive ...` бесполезно: такой строки там не бывает. Признак подмены
> виден в строке `Remote: principals: key options: command user-rc` — сервер
> применил `command="..."` из principals-файла, и в наборе опций остались только
> `command` и `user-rc`: **ни** pty, **ни** port-forwarding, **ни**
> agent-forwarding, **ни** x11-forwarding.

> **Про строку `Remote: cert: key options: ...`.** Сертификат сам по себе не
> ограничивает ничего: в нём разрешены agent-forwarding, port-forwarding, pty и
> x11-forwarding. Ограничивает именно строка principals-файла, и эффективные права
> — это пересечение двух наборов. Практический вывод: **граница безопасности здесь
> не в сертификате, а в `/etc/ssh/auth_principals/zfs-repl` на сервере**. Ещё один
> аргумент не создавать `authorized_keys` для `zfs-repl`: появись он — и
> principals-файл перестал бы быть единственным источником ограничений.

> **Редирект `< /dev/null` обязателен.** `force-command` — это `zfs receive`, а он
> читает ZFS-поток из stdin. Без редиректа stdin остаётся терминалом, и команда
> виснет, ожидая поток. В логе это выглядит как остановка на `debug1: pledge: fork`.

### Тест 3 — возобновление репликации после простоя master

**Цель.** Убедиться, что остановка master не порвала цепочку инкрементов.
**Гипотеза.** Маркер на master пережил (`@repl-4`), replica имеет
`zroot/tank/repl@repl-4`, поэтому инкремент `repl-4 → repl-5` примется. Это проверка
согласованности двух сторон после простоя.

```sh
# на master
zfs snapshot zroot/tank/data@repl-5
sudo /usr/local/sbin/zfs-replication.sh

# на replica
ssh -J fbsd-1-sel avalok11@fbsd-2-sel.lab.sel \
  "zfs list -t all -o name,used | grep repl"
```

Ожидаемый результат: на replica появляется `zroot/tank/repl@repl-5`, в маркере master
теперь `zroot/tank/data@repl-5`.

Разбор и результаты — в [отчёте](./phase-1-zfs-report.md) → «Failover».

## Защита в глубину

1. ed25519-ключ — brute-force бессмыслен
2. Сертификат подписан CA, principal=`zfs-repl` — без подписи CA ключ не примут
3. `from="172.16.0.2"` — вход только с master-ноды
4. `force-command` — только `zfs receive`, любую команду клиента подменяет
5. `zfs allow` вместо sudo — даже при обходе `force-command` учётка не станет root
6. `no-port/X11/agent-forwarding`, `no-pty` — ssh-сессию не превратить в туннель или шелл
7. `authorized_keys` отсутствует — отзыв сертификата реально отключает доступ