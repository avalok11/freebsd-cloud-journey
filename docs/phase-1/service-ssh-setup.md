# Сервисная SSH-учётка `zfs-repl`

Используется для ZFS-репликации `fbsd-1-sel → fbsd-2-sel`. Принимает только одну команду
(`zfs receive`) и только с IP master-ноды. Интерактивного шелла нет.

## Параметры пользователя

| Поле | Значение |
|---|---|
| username | `zfs-repl` |
| home | `/home/zfs-repl` |
| shell | `/bin/sh` |
| comment | "ZFS replication service account" |

> **Почему шелл, а не `/sbin/nologin`.** `force-command` sshd выполняет **через login-shell**
> пользователя. С `/sbin/nologin` принудительная команда не запустится вообще — сессия
> завершится с «This account is currently not available». Ограничение «никакого шелла»
> обеспечивается не шеллом, а опцией `no-pty` плюс тем, что `force-command` подменяет
> любую команду клиента. Это отличается от первоначального плана Фазы 1, где был указан
> `nologin` — на практике это оказалось нерабочим.

## Ключ и сертификат

- Тип: ed25519
- Приватный ключ: `~/.ssh/zfs_repl` на Mac M4, chmod 600
- Публичный ключ: `~/.ssh/zfs_repl.pub`
- Сертификат: `~/.ssh/zfs_repl-cert.pub` (подписан `fbsd-ca-sel`, principal=`zfs-repl`, TTL 52w)

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
from="172.16.0.2",command="/usr/bin/env zfs receive -F tank/repl",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty zfs-repl
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
| `command="/usr/bin/env zfs receive -F tank/repl"` | единственная разрешённая команда |
| `no-port-forwarding` | нельзя использовать как SOCKS-прокси |
| `no-X11-forwarding` | не запрашивает X11 |
| `no-agent-forwarding` | нельзя прокинуть ssh-agent |
| `no-pty` | не выделяет псевдо-терминал |
| `zfs-repl` | principal, к которому применяются все опции выше |

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
    "sudo /usr/local/sshca/scripts/sign-user-cert.sh /tmp/zfs_repl.pub zfs-repl +52w"
```

Ограничения при этом **не меняются** — они живут в `auth_principals/zfs-repl` на сервере,
а не в сертификате. Это одно из преимуществ выбранной схемы: смена ограничений — правка
одного файла на сервере, без переподписи и без перекладывания сертификата на клиент.

## Тесты

| # | Команда (с Mac M4) | Ожидаемый результат |
|---|---|---|
| 1 | `ssh -i ~/.ssh/zfs_repl-cert zfs-repl@<ip> id` без `-J` | `Permission denied` — `from="172.16.0.2"` не совпал с IP Mac M4 |
| 2 | `ssh -v -i ~/.ssh/zfs_repl-cert -J fbsd-1-sel zfs-repl@<ip> id` | в логе `Remote: auth_principals:zfs-repl: key options: ... command no-pty` и `Sending command: /usr/bin/env zfs receive -F tank/repl` — команда `id` подменена |
| 3 | то же + `-J fbsd-1-sel` и команда `ls /tmp` | та же подмена на `zfs receive`, вывода списка файлов нет |

## Защита в глубину

1. ed25519-ключ — brute-force бессмыслен
2. Сертификат подписан CA, principal=`zfs-repl` — без подписи CA ключ не примут
3. `from="172.16.0.2"` — вход только с master-ноды
4. `force-command` — только `zfs receive`, любую команду клиента подменяет
5. `no-port/X11/agent-forwarding`, `no-pty` — ssh-сессию не превратить в туннель или шелл
6. `authorized_keys` отсутствует — отзыв сертификата реально отключает доступ