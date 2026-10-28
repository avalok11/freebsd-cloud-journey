# fbsd-3-sel — конфиги ноды

Нода развёрнута 2026-10-27 как **дополнение** к стенду, после того как
`fbsd-1-sel` выбыла (Selectel не может её запустить — не хватает ресурсов).
Подробности — в
[`docs/phase-2/00-fbsd-3-sel-provisioning.md`](../../docs/phase-2/00-fbsd-3-sel-provisioning.md).

| Параметр | Значение |
|---|---|
| ОС | FreeBSD 15.1 amd64 |
| Ресурсы | **4 ГБ RAM**, 40 ГБ SSD; число vCPU отдельно не фиксировалось (`sysctl hw.ncpu`) |
| Публичный IP | выдаётся Selectel (в репо не публикуется) |
| Приватный IP | `172.16.0.5/16` |
| Роль | **master**: ZFS-пул, источник репликации, jails, Bastille, bhyve |
| Доступ | SSH по ключу + TOTP, с Mac M4 напрямую |

## Состав

Файл внутри `etc/` **совпадает с путём на ноде**:

| Файл в репо | Путь на ноде | Назначение |
|---|---|---|
| `etc/ssh/sshd_config.d/00-hardening.conf` | `/etc/ssh/sshd_config.d/00-hardening.conf` | hardening SSH |
| `etc/ssh/sshd_config.d/ca.conf` | `/etc/ssh/sshd_config.d/ca.conf` | доверие к CA: host-сертификат, User CA, CRL |
| `etc/pam.d/sshd` | `/etc/pam.d/sshd` | TOTP через `pam_google_authenticator` |
| `etc/rc.conf` | `/etc/rc.conf` | hostname, адрес, автозапуск служб |
| `etc/pf.conf` | `/etc/pf.conf` | файрвол |
| `etc/resolv.conf` | `/etc/resolv.conf` | DNS и search-домен |
| `etc/issue.net` | `/etc/issue.net` | баннер при входе по SSH |

Оба файла в `sshd_config.d/` подключаются через `Include /etc/ssh/sshd_config.d/*.conf`
в основном `sshd_config`, поэтому применяются при каждом `service sshd restart`
автоматически — отдельная строка `Include` в `sshd_config` не нужна.

`ca.conf` — «настройки для сервера данных по серверу сертификации»: нода
предъявляет свой host-сертификат, доверяет User CA и проверяет CRL.

```
HostCertificate /etc/ssh/ca/ssh_host_ed25519_key-cert.pub
TrustedUserCAKeys /etc/ssh/ca/user_ca.pub
RevokedKeys /etc/ssh/ca/revoked_keys
```

На `fbsd-2-sel` этот же файл отличается одной строкой — там добавлен
`AuthorizedPrincipalsFile /etc/ssh/auth_principals/%u`, без него сервисная
учётка `zfs-repl` не смогла бы войти по сертификату. На `fbsd-3-sel` такой строки
нет, и это правильно: `zfs-repl` живёт только на реплике.

### Раскладка материалов CA — единая для стенда

Все ноды кладут материалы CA в `/etc/ssh/ca/`:

| Файл | Путь | Права |
|---|---|---|
| User CA (публичный ключ) | `/etc/ssh/ca/user_ca.pub` | 644 |
| CRL (отозванные ключи) | `/etc/ssh/ca/revoked_keys` | 644 |
| host-сертификат | `/etc/ssh/ca/ssh_host_ed25519_key-cert.pub` | 644 |

Изначально на `fbsd-3-sel` материалы лежали прямо в `/etc/ssh/`
(`user_ca.pub`, `revoked_keys`), а на `fbsd-2-sel` — в `/etc/ssh/ca/`.
Расхождение выравнено 2026-10-28 — см. расхождение 4 ниже.

**Путь к host-сертификату — произвольный.** `HostCertificate` указывает sshd
**явный путь** к файлу; рядом с приватным host-ключом сертификат лежать не
обязан. Единственное требование — **публичный ключ в сертификате должен
совпадать с приватным host-ключом**, уже прописанным в `HostKey`:

> Specifies a file containing a public host certificate. The certificate's public
> key must match a private host key already specified by HostKey.
> — `sshd_config(5)`

Правило «сертификат должен лежать рядом с ключом» — это про **клиентскую**
сторону и **пользовательские** ключи: `ssh` ищет сертификат по шаблону
`<имя_приватного_ключа>-cert.pub` в том же каталоге. К host-сертификату оно
не относится.

Проверить совпадение ключей:

```sh
ssh-keygen -Lf /etc/ssh/ca/ssh_host_ed25519_key-cert.pub | head -1
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
# одинаковый fingerprint (SHA256:...) — значит, ключи совпадают
```

**Расхождение с `fbsd-2-sel`.** Там host-сертификат остался в `/etc/ssh/`
(`HostCertificate /etc/ssh/ssh_host_ed25519_key-cert.pub`). Функционально это
без разницы — путь произвольный, — но для единообразия ноды можно свести к
одному пути.

## Расхождения, которые нужно закрыть

### 1. Баннер скопирован с CA-ноды — **исправлено 2026-10-28**

Было — баннер ноды CA, хотя `fbsd-3-sel` CA-нодой не является:

```
   FreeBSD Private Cloud — SSH Certificate Authority
   This is a SECURITY-SENSITIVE node (SSH CA).
```

Стало:

```
================================================================
   FreeBSD Private Cloud — staging Selectel
   All actions are logged. Authorized access only.

   Issues: a.@gmail.com
================================================================
```

Текст про CA убран — нода больше не выглядит нодой с приватными ключами CA.

> **Осталась опечатка в адресе:** `a.@gmail.com` вместо `a@gmail.com`. Адрес с
> точкой перед `@` Gmail не принимает — это опечатка, а не рабочий контакт.
> Файл в репозитории оставлен **как применено**, поэтому правка должна идти
> на ноду, а оттуда — сюда:
>
> ```sh
> sudo sed -i '' 's/a\.@gmail\.com/a@gmail.com/' /etc/issue.net
> ```

### 2. PF ruleset не тот, что в репо — сходим в День 3

Файл `etc/pf.conf` на ноде — упрощённая версия. Единый ruleset из
[`docs/phase-1/pf-ruleset.conf`](../../docs/phase-1/pf-ruleset.conf) отличается:

| Правило | Единый ruleset (v2) | На `fbsd-3-sel` сейчас | Разница |
|---|---|---|---|
| `antispoof quick for $ext_if` | есть | **нет** | **функциональная**: пакеты с чужим src IP изнутри не отбрасываются |
| `set block-policy return` | есть | **нет** | косметика: nmap видит «closed» вместо «filtered» |
| `set ruleset-optimization none` | нет | есть | косметика: не оптимизировать ruleset |
| переменная SSH-порта | `tcp_services = "{ ssh }"` (set) | `tcp_service = "ssh"` (scalar) | разные имена — при слиянии выбрать одно |
| ICMP | `pass proto icmp all` | `pass inet proto icmp all` | на ноде разрешён только ICMPv4, ping6 снаружи не проходит |
| NAT-заглушка под jails | закомментирована | отсутствует | добавится в День 3 вместе с anchor'ами Bastille |
| `set skip on lo` | `set skip on $lo_if`, где `lo_if = "lo0"` | `set skip on lo0` | **расхождения между нодой и ruleset нет** — расходится нужное значение: клонированный loopback `bastille0` принадлежит группе `lo`, а не `lo0`. Значит `set skip on lo` надо поставить **в обоих** местах |

Сходим в День 3, когда добавляем VNET: Bastille ждёт `table <jails>`,
`nat from <jails>`, `rdr-anchor "rdr/*"`, `anchor "bastille/*"` и `set skip on lo`.
Тогда и заменим файл на единый ruleset, расширенный под jails. Важно: `set skip on lo`
меняется и в самом `docs/phase-1/pf-ruleset.conf` — сейчас там тоже `lo0`
через `$lo_if`, то есть расхождение не «нода против репозитория», а «оба против
требования Bastille».

### 3. `ChallengeResponseAuthentication` устарел

В `etc/ssh/sshd_config.d/00-hardening.conf` есть и `ChallengeResponseAuthentication yes`,
и `KbdInteractiveAuthentication yes`. Первая директива переименована в OpenSSH 8.7
и с тех пор является синонимом второй. Дубликат безвреден, но лишний — убрать
при сведении с `fbsd-1-sel`/`fbsd-2-sel`.

### 4. Раскладка файлов CA отличалась от других нод — **исправлено 2026-10-28**

На ноде сначала лежало:

```
TrustedUserCAKeys /etc/ssh/user_ca.pub
RevokedKeys /etc/ssh/revoked_keys
```

а на `fbsd-2-sel` — в подкаталоге `/etc/ssh/ca/`:

```
TrustedUserCAKeys /etc/ssh/ca/user_ca.pub
RevokedKeys /etc/ssh/ca/revoked_keys
```

Расхождение было не косметическим: `TrustedUserCAKeys` и `RevokedKeys` указывают
sshd, **откуда** читать файлы, и CRL кладётся строго по указанному пути. Файл,
положенный не туда, sshd не прочитает — и отзыв сертификата **не сработает
молча**: выглядит как успех, а на деле только запись в файл.

**Исправлено:** нода переведена на общий путь `/etc/ssh/ca/`, файлы перенесены,
`ca.conf` переписан. Теперь раскладка материалов CA на всём стенде одинакова —
см. раздел «Раскладка материалов CA» выше.

Проверка после любой правки — не «файл лежит», а «sshd читает именно его»:

```sh
# на каждой ноде — что sshd читает на самом деле
sudo grep -h '^RevokedKeys' /etc/ssh/sshd_config.d/*.conf /etc/ssh/sshd_config
```

## Найденная проблема: `nullok` вырождает второй фактор

**Это самое важное в этом наборе файлов, и его надо закрыть.**

В `etc/pam.d/sshd`:

```
auth sufficient /usr/local/lib/pam_google_authenticator.so nullok
auth required   pam_unix.so no_warn try_first_pass
```

а в `00-hardening.conf`:

```
AuthenticationMethods publickey,keyboard-interactive:pam
```

Как это работает:

1. `AuthenticationMethods` требует **два** метода: `publickey` и `keyboard-interactive:pam`.
   Значит, второй фактор — это PAM-диалог, и второй фактор **обязателен**.
2. `pam_google_authenticator` с флагом `nullok` для пользователя **без** TOTP-секрета
   возвращает **успех**, ничего не спрашивая.
3. Он объявлен `sufficient` — то есть при успехе стек PAM немедленно возвращает
   успех, и `pam_unix` (проверка пароля) **не выполняется вовсе**.

Итог: для пользователя, у которого не настроен TOTP, `keyboard-interactive:pam`
проходит без единого вопроса. Второй фактор превращается в пустую формальность —
достаточно предъявить публичный ключ.

Почему это не сработало бы на `fbsd-2-sel`: там `AuthenticationMethods publickey`
(без `keyboard-interactive`), и TOTP снят намеренно — нода без публичного IP,
доступ только через jump-host. Один фактор там осознанный, а не случайно
вырожденный.

На `fbsd-1-sel` и `fbsd-3-sel` ситуация другая: `keyboard-interactive` в списке
обязателен, значит замысел был «второй фактор обязателен», а из-за `nullok` это
не гарантировано.

**Исправление** — убрать `nullok`, чтобы отсутствие TOTP-секрета давало отказ,
а не успех. Модуль остаётся `sufficient`:

```
auth sufficient /usr/local/lib/pam_google_authenticator.so
auth required   pam_unix.so no_warn try_first_pass
```

Разбор по семантике PAM:

| Модуль | Тип | Что означает |
|---|---|---|
| `pam_google_authenticator.so` | `sufficient` | при успехе (задан TOTP-секрет, введён верный код) — **стек немедленно возвращает успех**, остальное не выполняется. При отказе (секрета нет или код неверен) — стек продолжается |
| `pam_unix.so` | `required` | проверка пароля; выполняется, только если первый модуль не дал успеха |

**Почему не `required` для модуля TOTP.** `required` означает «этот модуль должен
успешно отработать, иначе весь стек — отказ», но **не** прерывает стек при успехе:
после него продолжают выполняться остальные `required`-модули. Поставив `required`
на обоих, мы получили бы требование и TOTP, **и** пароля одновременно — то есть
администратору пришлось бы вводить и код, и пароль. `sufficient` здесь даёт ровно
то, что нужно: TOTP спрашивается, пароль не спрашивается.

**Как сделать TOTP неопциональным совсем.** Заменить `sufficient` на `requisite`:
тогда отказ модуля (нет секрета) обрывает аутентификацию мгновенно, и пароль уже
не спасёт. Цена — сервисные учётки без TOTP (например, `zfs-repl`, если бы он
был на этой ноде) перестанут проходить через PAM, а потеря секрета = доступ
только через консоль Selectel. На `fbsd-3-sel` сервисной учётки нет, так что
`requisite` допустим — но это отдельное решение, а не часть исправления `nullok`.

**Проверка после правки:**

1. Убедиться, что TOTP-секрет на месте — иначе после правки вход не пройдёт:
   ```sh
   ls -l ~/.google_authenticator
   ```
2. **Не закрывать текущую SSH-сессию.** Открыть вторую и проверить вход с TOTP.
   Если не получилось — вернуться в первую и откатить:
   ```sh
   sudo sed -i '' 's/ nullok$//' /etc/pam.d/sshd
   sudo service sshd restart
   ```
3. Проверить, что `AuthenticationMethods` по-прежнему требует оба фактора.

## Замечания по применению

- `etc/rc.conf` содержит `ifconfig_vtnet0="inet 172.16.0.5 netmask 255.255.0.0"`.
  Это единственный адрес ноды — при переносе на другой хост правится.
- `zfs_enable="YES"` — пул `zroot` приходит с образом Selectel, создавать его
  руками не нужно.
- `ntpd_sync_on_start="YES"` — при загрузке время синхронизируется само, но
  первое включение TOTP стоит делать после того, как часы сошлись: иначе
  проверка кода отклонит правильный токен.
- `sshguard_enable="YES"` + `pf_enable="YES"` — порядок загрузки: sshguard
  создаёт `/var/db/sshguard/blacklist.pf`, на который ссылается `table <sshguard>`.
  Если файл не создан, PF ругается на отсутствие таблицы.
- `/etc/ssh/ca/` — каталог с материалами CA (`user_ca.pub`, `revoked_keys`).
  Создаётся с правами 755, файлы внутри — 644. Если каталога нет, `ca.conf`
  ссылается на несуществующие пути: sshd стартует, но **проверять сертификаты
  и отзывать ключи не сможет** — молча.
