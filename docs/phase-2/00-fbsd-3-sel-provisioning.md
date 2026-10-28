# fbsd-3-sel: новый master и восстановление после потери fbsd-1-sel

**Статус:** День 0 выполнен 2026-10-27, День 1 в работе
**Период:** Дни 0–1 Недели 1 Фазы 2

> Этот документ описывает **незапланированную** работу: мастер-нода `fbsd-1-sel`
> выбыла, и стенд пришлось восстанавливать. Для курса это оказалось полезным
> упражнением, а не просто потерей: сценарий «мастер потерян → восстановились с
> собственной реплики» — тот случай, которого нет ни в одном учебном курсе.

## Что случилось

После инцидента в дата-центрах и массовой миграции компаний в Selectel на
`fbsd-1-sel` перестало хватать ресурсов: **VPS не запускается**. Ноды
`fbsd-ca-sel` и `fbsd-2-sel` работают — вероятно, они на другом физическом
сервере, который не перегружен.

| Нода | Была | Статус | Судьба |
|---|---|---|---|
| `fbsd-1-sel` | master: ZFS-пул, источник репликации, jump-host | **не запускается** | не запускается; при возвращении — см. «Сценарий возвращения» |
| `fbsd-ca-sel` | SSH CA | работает | без изменений, CA на весь курс |
| `fbsd-2-sel` | реплика ZFS, jump-only | работает | **застревает без jump-host** — это чинится первым делом |
| `fbsd-3-sel` | — | **развёрнута 2026-10-27** | новая master-нода, `172.16.0.5`, 4 ГБ RAM |

## Что из этого следует

**Проблема №1 — `fbsd-2-sel` недоступна.** Её единственный путь входа — jump-host
через `fbsd-1-sel`. Пока та мертва, до реплики можно добраться только через
out-of-band консоль Selectel. Значит первое, что делаем на новой ноде: **становимся
jump-host'ом сами**.

**Проблема №2 — данные на мёртвом мастере.** Но у нас есть **реплика**:
`zroot/tank/repl` на `fbsd-2-sel` содержит данные до `@repl-5`. Восстановление
master'а с собственной реплики — ровно то, ради чего в Фазе 1 строилась машина
`zfs send`/`zfs receive`. **Это и есть проверка того, что Фаза 1 была не упражнением,
а рабочим механизмом.**

**Проблема №3 — приватный ключ репликации потерян.** Ключ `zfs_repl` лежал в
`/root/.ssh/` на `fbsd-1-sel`. Он недоступен. Но CA жив, а значит выпуск нового
ключа — штатная операция: сгенерировать, подписать, разложить, **отозвать старый**
через CRL. Это первый в истории курса реальный отзыв сертификата.

## Роли нод на весь курс

`fbsd-3-sel` — **дополнение** к стенду, не замена `fbsd-1-sel`. Отсюда важное:
адреса не переиспользуются, `172.16.0.2` остаётся за `fbsd-1-sel`, а `fbsd-3-sel`
живёт на `172.16.0.5` и имеет собственную роль.

| Нода | Роль | Фазы |
|---|---|---|
| `fbsd-ca-sel` | SSH CA: подпись ключей, CRL | 0.1 → 8 |
| `fbsd-3-sel` | **master**: ZFS-пул, источник репликации, jails, Bastille, bhyve; позже HA-мастер, Gitea, мониторинг | 1.5 → 8 |
| `fbsd-2-sel` | реплика ZFS; jump-only к `fbsd-3-sel`; позже HA-бэкенд | 1 → 8 |
| `fbsd-arm` (локально) | arm64-лаборатория: jails, PF, ZFS, Bastille, сравнение с amd64 | 0 → 8 |
| `deb-arm` (локально) | Linux-мост | 0 → 8 |
| `fbsd-1-sel` | **не запускается**; при возвращении — ре-сид либо третья нода HA-пары | — |

`fbsd-3-sel` занимает место `fbsd-1-sel` не «временно», а **по существу**: это и
master, и нода для jails/bhyve. Разница — в том, что на ней не будет накопленной
истории билдов, но для учебного стенда это неважно.

---

## День 0 (~3 ч) — развёртывание fbsd-3-sel

### 0.1. Создать VPS в Selectel

| Параметр | Значение | Почему |
|---|---|---|
| ОС | FreeBSD 15.1 amd64 | как на остальных нодах; amd64 обязателен для bhyve |
| vCPU | 2 по плану; **фактическое значение не подтверждено** — проверить `sysctl hw.ncpu` | 1 vCPU — впритык для bhyve (гость 512 МБ + хост) |
| RAM | **4 ГБ** | хост + jail'ы + VM в Фазе 2 + CARP/HAProxy в Фазе 3 |
| Диск | 40 ГБ SSD | `zroot` (система) + `zroot/tank` (данные, jail'ы, образы VM) |
| Публичный IP | да | вход с Mac M4 напрямую, как у `fbsd-1-sel` |
| Приватный IP | **`172.16.0.5`** | см. ниже |

> **Важное уточнение по формулировке.** `fbsd-3-sel` — это **не замена
> `fbsd-1-sel`, а дополнение к стенду**. Разница принципиальна:
>
> - **«Замена»** означала бы, что `fbsd-1-sel` больше никогда не вернётся, её
>   данные не нужны, и `fbsd-3-sel` просто занимает её адрес и место.
> - **«Дополнение»** — `fbsd-3-sel` добавляется к стенду как **ещё одна** нода с
>   собственным адресом и ролью. Если `fbsd-1-sel` когда-нибудь запустится, она
>   останется **своей** нодой, а не будет «восстановлена как раньше».
>
> Это меняет три вещи:
>
> 1. **Адрес не переиспользуется.** `fbsd-3-sel` получила `172.16.0.5`, а
>    `172.16.0.2` остаётся зарезервированным за `fbsd-1-sel`. Значит, ограничение
>    `from="172.16.0.2"` в principals-файле на реплике **больше не подходит** для
>    нового master'а — его надо менять на `172.16.0.5` (см. День 1).
> 2. **Данные не теряются — они дублируются.** На новой ноде будет свой
>    `zroot/tank/data`, восстановленный с реплики, а на `fbsd-1-sel`, если она
>    вернётся, останется её собственная копия. Их не нужно сливать: одну из них
>    можно пересоздать с нуля.
> 3. **Роль `fbsd-1-sel` меняется.** Не «выбывшая нода, ждём возвращения», а
>    «третья нода, которая сейчас не запущена». При возвращении — ре-сид и
>    место в HA-паре (см. «Сценарий возвращения»).

### 0.2. Установка FreeBSD и базовая настройка

Готовый образ Selectel, пароль root из панели. Дальше — по настройкам Фазы 0:

```sh
# смена паролей, sshd
# /etc/ssh/sshd_config: PasswordAuthentication no, PermitRootLogin no
# баннер
# /etc/issue.net
```

### 0.3. Hardening: PF, sshguard, TOTP

Набор файлов, применённых на ноде, сохранён в репозитории —
[`config/fbsd-3-sel/`](../../config/fbsd-3-sel/):

| Файл | Путь на ноде |
|---|---|
| `00-hardening.conf` | `/etc/ssh/sshd_config.d/00-hardening.conf` |
| `ca.conf` | `/etc/ssh/sshd_config.d/ca.conf` |
| `sshd` | `/etc/pam.d/sshd` |
| `rc.conf` | `/etc/rc.conf` |
| `pf.conf` | `/etc/pf.conf` |
| `resolv.conf` | `/etc/resolv.conf` |
| `issue.net` | `/etc/issue.net` |

Оба файла в `sshd_config.d/` подключаются через `Include /etc/ssh/sshd_config.d/*.conf`
в основном `sshd_config` — отдельная строка `Include` не нужна, файлы применяются
при каждом `service sshd restart`.

Содержимое лежит в том виде, в каком **реально применено** на ноде, — расхождения
с целевым состоянием зафиксированы в
[`config/fbsd-3-sel/README.md`](../../config/fbsd-3-sel/README.md). Оттуда три
важных пункта:

1. **Баннер скопирован с CA-ноды** — было написано «This is a SECURITY-SENSITIVE
   node (SSH CA)», хотя нода не CA. **Исправлено 2026-10-28:** текст про CA убран,
   остался общий баннер стенда.
2. **`nullok` в `/etc/pam.d/sshd` вырождает второй фактор** — подробный разбор
   в том же README. Кратко: `pam_google_authenticator` с `nullok` для пользователя
   без TOTP-секрета возвращает успех, а объявлен `sufficient` — значит, PAM
   возвращает успех сразу, не спросив ничего. При `AuthenticationMethods
   publickey,keyboard-interactive:pam` второй фактор для такого пользователя
   становится формальностью. **Надо убрать `nullok`.**
3. **Раскладка файлов CA приведена к общей** — изначально на ноде материалы лежали
   прямо в `/etc/ssh/`, а на остальных нодах — в `/etc/ssh/ca/`. CRL надо класть
   туда, откуда sshd его читает, иначе отзыв не сработает молча. Выровнено
   2026-10-28, теперь путь на всех нодах одинаковый — см. 0.4.

Применение:

```sh
sudo sysrc sshd_enable="YES" ntpd_enable="YES" sshguard_enable="YES" pf_enable="YES"
sudo pfctl -f /etc/pf.conf
```

### 0.4. Host-сертификат через CA

Ключи и сертификаты лежат в **стандартных путях FreeBSD** — `/etc/ssh/`, а не
в `/usr/local/etc/ssh/`:

```sh
# на новой ноде
cat /etc/ssh/ssh_host_ed25519_key.pub

# на CA — подписать
ssh fbsd-ca-sel 'sudo /usr/local/sshca/scripts/sign-host-cert.sh \
    /tmp/ssh_host_ed25519_key.pub fbsd-3-sel'

# сертификат — на ноду
scp fbsd-ca-sel:/usr/local/sshca/hosts/fbsd-3-sel/ssh_host_ed25519_key-cert.pub /tmp/
sudo cp /tmp/ssh_host_ed25519_key-cert.pub /etc/ssh/ca/
sudo chmod 644 /etc/ssh/ca/ssh_host_ed25519_key-cert.pub
```

В `sshd_config.d/ca.conf` на ноде (файл применён, лежит в репозитории как
[`config/fbsd-3-sel/etc/ssh/sshd_config.d/ca.conf`](../../config/fbsd-3-sel/etc/ssh/sshd_config.d/ca.conf)):

```
HostCertificate /etc/ssh/ca/ssh_host_ed25519_key-cert.pub
TrustedUserCAKeys /etc/ssh/ca/user_ca.pub
RevokedKeys /etc/ssh/ca/revoked_keys
```

Первая строка — нода предъявляет свой host-сертификат клиентам. Вторая — нода
доверяет User CA и проверяет сертификаты входящих. Третья — список отозванных
ключей. Материалы CA лежат в `/etc/ssh/ca/` — так на всех нодах стенда.

Путь к host-сертификату произвольный: `HostCertificate` — это явный путь, а
рядом с приватным host-ключом сертификат лежать не обязан. Требование одно —
публичный ключ в сертификате должен совпадать с host-ключом из `HostKey`.

Доверие к CA — на самой ноде и на всех, кто к ней ходит:

```sh
# user_ca.pub — на ноду: чтобы нода доверяла CA и проверяла сертификаты
sudo install -d -m 755 /etc/ssh/ca
sudo cp /tmp/user_ca.pub /etc/ssh/ca/user_ca.pub
sudo chmod 644 /etc/ssh/ca/user_ca.pub

# CRL — на всех нодах, где нужен отзыв (файл может отсутствовать, но sshd
# не сможет проверять отозванные ключи, если его нет)
sudo touch /etc/ssh/ca/revoked_keys
sudo chmod 644 /etc/ssh/ca/revoked_keys

# host_ca.pub — пользователю: чтобы клиент доверял host-сертификату ноды
cp /tmp/host_ca.pub ~/.ssh/host_ca.pub
```

Пользовательский каталог — `/home/avalok11/.ssh` (в документации всегда
`avalok11`, никогда реальное имя учётной записи).

> **Путь к CRL.** CRL кладётся строго туда, откуда его читает sshd: положим не
> туда — отзыв не сработает молча. На всех нодах стенда путь теперь одинаковый,
> `/etc/ssh/ca/revoked_keys`. Проверить, что sshd читает именно его:
>
> ```sh
> sudo grep -h '^RevokedKeys' /etc/ssh/sshd_config.d/*.conf /etc/ssh/sshd_config
> ```

### 0.5. ZFS-структура

**Пул `zroot` создавать не нужно** — он приходит с готовым образом Selectel
(в `rc.conf` уже стоит `zfs_enable="YES"`). Проверить и достроить иерархию:

```sh
zpool status zroot
zfs list -o name,used,refer,mountpoint
```

Дальше — создать `zroot/tank` и дочерние датасеты:

```sh
sudo zfs create zroot/tank
sudo zfs set compression=lz4 atime=off zroot/tank
sudo zfs create zroot/tank/logs
sudo zfs create zroot/tank/repl
sudo zfs create zroot/tank/secure
sudo zfs set compression=lz4 atime=off zroot/tank/secure
```

**`zroot/tank/data` пока не создаём** — его создаст приём потока (День 1). Если
создать заранее, `zfs receive` упадёт с «destination already exists».

> **`zpool create zroot /dev/da0` из первоначального плана — лишняя команда.**
> На этой ноде пул уже создан образом Selectel, и повторный `zpool create` его бы
> сломал. В плане Фазы 1 на `fbsd-1-sel` пул создавался вручную, потому что там
> был другой путь установки; здесь — нет.

---

## День 1 (~2 ч) — восстановление данных и смена ключа

### 1.1. `fbsd-3-sel` становится jump-host'ом для `fbsd-2-sel`

С этого момента `fbsd-2-sel` снова доступна:

```sh
ssh -J fbsd-3-sel avalok11@fbsd-2-sel.lab.sel
```

### 1.2. Восстановление данных с реплики

Поток идёт **с** `fbsd-2-sel` **на** `fbsd-3-sel`. Отправлять будет админская
учётка `avalok11` через `sudo` — сервисная `zfs-repl` на `fbsd-2-sel` умеет только
принимать (`force-command` = `zfs receive`), а для разового DR-восстановления
поднимать отдельный сервисный аккаунт с правом `zfs send` избыточно.

**Предусловие на новом master'е:** датасет `zroot/tank` должен существовать —
иначе `zfs receive` не сможет создать в нём `zroot/tank/data`.

```sh
ssh fbsd-3-sel 'zfs list zroot/tank' || \
  ssh fbsd-3-sel 'sudo zfs create zroot/tank && sudo zfs set compression=lz4 atime=off zroot/tank'
```

И поток — с Mac M4, двумя SSH-сессиями:

```sh
ssh -J fbsd-3-sel avalok11@fbsd-2-sel.lab.sel \
    'sudo -n zfs send -R zroot/tank/repl@repl-5' \
  | ssh avalok11@fbsd-3-sel.lab.sel \
    'sudo -n zfs receive zroot/tank/data'
```

- `-R` — переносим не только состояние, но и снапшоты и свойства датасета. При
  восстановлении это правильнее; обычный `zfs send` переносит только срез на
  момент снапшота.
- `sudo -n` — без пароля (нужен NOPASSWD на этих нодах). Если пароль запрашивается,
  добавь `-t` к ssh и введи его.
- Приёмник — `zroot/tank/data`: имя берётся из команды, а не из потока, поэтому
  в ZFS-дереве нового master'а датасет называется правильно.

Проверка:

```sh
# на fbsd-3-sel
zfs list -t all -o name,used,mountpoint | grep -E 'tank/(data|repl)'
zfs list -t snapshot -o name -r zroot/tank/data
ls -l /zroot/tank/data
```

Ожидание: 14 файлов (те же, что были на `fbsd-1-sel`) и снапшоты `repl-1..repl-5`.
Если снапшоты не перенеслись — создаём недостающие заново, они нам нужны как
цепочка для инкрементов.

### 1.3. Смена сервисного ключа репликации

Старый приватный ключ потерян вместе с нодой. Выпускаем новый — CA жив.

```sh
# на fbsd-3-sel — новый ключ
# -N "" обязателен: без него ssh-keygen спросит passphrase и зависнет.
# У сервисного ключа пароля быть не должно — скрипт репликации работает
# без участия человека (из cron в Фазе 4).
ssh fbsd-3-sel 'sudo install -d -m 700 /root/.ssh && \
    sudo ssh-keygen -t ed25519 -N "" -f /root/.ssh/zfs_repl -C "zfs-repl@fbsd-3-sel"'

# публичный ключ — на CA (файл лежит в /root, поэтому читаем через sudo)
ssh fbsd-3-sel 'sudo cat /root/.ssh/zfs_repl.pub' \
  | ssh fbsd-ca-sel 'cat > /tmp/zfs_repl.pub'

# на CA — подписать: principal тот же, каталог хранения ДРУГОЙ
ssh fbsd-ca-sel 'sudo /usr/local/sshca/scripts/sign-user-cert.sh \
    /tmp/zfs_repl.pub zfs-repl +52w zfs_repl_3'

# забрать сертификат (каталог CA — 700, поэтому читаем через sudo)
ssh fbsd-ca-sel 'sudo cat /usr/local/sshca/users/zfs_repl_3/zfs_repl-cert.pub' \
  > /tmp/zfs_repl-cert.pub

# положить на ноду РЯДОМ с приватным ключом
scp /tmp/zfs_repl-cert.pub fbsd-3-sel:/tmp/zfs_repl-cert.pub
ssh fbsd-3-sel 'sudo cp /tmp/zfs_repl-cert.pub /root/.ssh/zfs_repl-cert.pub && \
    sudo chmod 600 /root/.ssh/zfs_repl /root/.ssh/zfs_repl-cert.pub && \
    rm -f /tmp/zfs_repl-cert.pub'
```

> **Почему каталог `zfs_repl_3`, а не `zfs_repl`.** `sign-user-cert.sh` копирует
> публичный ключ в каталог CA **только если там ещё нет файла с таким именем**, а
> подписывает всегда **файл из каталога**, а не переданный. Старый ключ лежит в
> `users/zfs_repl/zfs_repl.pub`, поэтому повторная подпись с тем же именем тихо
> выпустила бы сертификат **на старый ключ** — новый приватный ключ ему не
> соответствует, и вход на реплику упал бы с невнятной ошибкой. Новый каталог
> `zfs_repl_3` отделяет поколения ключей. Скрипт теперь падает с понятной ошибкой,
> если в каталоге лежит другой ключ под тем же именем.

**Отозвать старый сертификат.** Иначе старый ключ (если он ещё где-то есть) продолжит
работать до конца TTL — 52 недели.

```sh
# на CA — старый ключ лежит в каталоге zfs_repl
ssh fbsd-ca-sel 'sudo /usr/local/sshca/scripts/revoke-ssh.sh user zfs_repl zfs_repl'

# --- раздать обновлённый CRL на ноды ---
# Путь на всех нодах стенда одинаковый — /etc/ssh/ca/revoked_keys.
# Но сначала убеждаемся, что sshd читает именно его: RevokedKeys указывает
# путь, и файл, положенный не по нему, просто не будет загружен.
ssh fbsd-3-sel "sudo grep -h '^RevokedKeys' /etc/ssh/sshd_config.d/*.conf /etc/ssh/sshd_config"
ssh -J fbsd-3-sel fbsd-2-sel "sudo grep -h '^RevokedKeys' /etc/ssh/sshd_config.d/*.conf /etc/ssh/sshd_config"
# ожидаем в обоих случаях: RevokedKeys /etc/ssh/ca/revoked_keys

# CRL — через Mac: scp между двумя удалёнными хостами требует -3,
# а хоп через локальную машину работает всегда
scp fbsd-ca-sel:/usr/local/sshca/revoked/revoked_keys /tmp/revoked_keys
scp /tmp/revoked_keys fbsd-3-sel:/tmp/revoked_keys
scp /tmp/revoked_keys fbsd-2-sel:/tmp/revoked_keys

ssh fbsd-3-sel "sudo cp /tmp/revoked_keys /etc/ssh/ca/revoked_keys && \
    sudo chmod 644 /etc/ssh/ca/revoked_keys && rm -f /tmp/revoked_keys && \
    sudo service sshd restart"

# то же — на реплику, там сертификаты zfs-repl и проверяются
ssh -J fbsd-3-sel fbsd-2-sel "sudo cp /tmp/revoked_keys /etc/ssh/ca/revoked_keys && \
    sudo chmod 644 /etc/ssh/ca/revoked_keys && rm -f /tmp/revoked_keys && \
    sudo service sshd restart"
```

Отзыв старого ключа **не затрагивает новый**: CRL хранит публичные ключи, а у нового
сертификата другой ключ.

> **Проверить, что CRL вообще читается.** Если sshd не может прочитать файл по
> `RevokedKeys`, он не сможет и отклонить отозванный сертификат — то есть
> отзыв будет выглядеть как успешный, а работать не будет. После рестарта sshd
> проверь в логе, что CRL прочитан:
>
> ```sh
> ssh fbsd-3-sel 'sudo grep -i "revok" /var/log/auth.log | tail -5'
> ```

### 1.4. Обновить `from=` на реплике

`fbsd-3-sel` получила приватный адрес **`172.16.0.5`**, а ограничение на реплике
по-прежнему `from="172.16.0.2"` — адрес выбывшего `fbsd-1-sel`. Пока это так,
репликация с нового master'а **отвергается**: sshd на `fbsd-2-sel` найдёт строку
в principals-файле, но `from=` не совпадёт, и доступ будет закрыт.

```sh
# на fbsd-2-sel
sudo sed -i '' 's/from="172.16.0.2"/from="172.16.0.5"/' /etc/ssh/auth_principals/zfs-repl
sudo service sshd reload
```

**Почему не оставляем оба адреса.** Можно написать `from="172.16.0.2",from="172.16.0.5"`
(в OpenSSH несколько `from=` означают «совпадение с любым из них»). Тогда реплику
сможет наполнять и `fbsd-1-sel`, когда вернётся, — но это **два master'а на одну
реплику**, а значит риск расхождения данных: две ноды делают снапшоты, инкременты
перестают быть линейной цепочкой, `zfs receive` начнёт отвергать потоки.

Правильнее держать **одного** источника репликации. Сейчас это `fbsd-3-sel`.
Когда `fbsd-1-sel` вернётся, вопрос «кто источник» решается осознанно, а не тем,
что адрес случайно остался в списке. Варианты — в разделе «Сценарий возвращения».

### 1.5. Восстановить маркер репликации

На новом master'е нет файла-маркера. Без него скрипт сделает **полную** отправку —
это безопасно, но тяжелее. Лучше посеять маркер тем снапшотом, который реплика уже
приняла:

```sh
# на fbsd-3-sel
sudo install -d -m 700 /var/db/zfs-replication
echo "zroot/tank/data@repl-5" | sudo tee /var/db/zfs-replication/last-snapshot
```

Значение берём **из фактического состояния реплики**, а не по памяти:

```sh
# на fbsd-2-sel
zfs list -t snapshot -o name -r zroot/tank/repl | tail -1
```

### 1.6. Установить скрипт репликации на новый master

Скрипт живёт в репозитории (`docs/phase-1/zfs-replication.sh`) и на `fbsd-1-sel`
стоял в `/usr/local/sbin/`. На новой ноде его нет — без него шаг 1.7 не запустится.

```sh
# с Mac M4 — положить скрипт на ноду
scp docs/phase-1/zfs-replication.sh fbsd-3-sel:/tmp/zfs-replication.sh
ssh fbsd-3-sel 'sudo install -m 755 /tmp/zfs-replication.sh /usr/local/sbin/zfs-replication.sh && \
    rm -f /tmp/zfs-replication.sh && ls -l /usr/local/sbin/zfs-replication.sh'
```

Проверить, что скрипт на месте и в нём правильные пути (master сменился, реплика
осталась прежней):

```sh
ssh fbsd-3-sel 'sudo grep -E "^(DATASET|REPLICA|KEY|STATE)=" /usr/local/sbin/zfs-replication.sh'
```

Ожидается:

```
DATASET="zroot/tank/data"
REPLICA="zfs-repl@172.16.0.4"
KEY="/root/.ssh/zfs_repl"
STATE="/var/db/zfs-replication/last-snapshot"
```

`DATASET` и `REPLICA` менять не нужно — нода стала master'ом с тем же набором
датасетов, реплика та же. А вот `KEY` теперь указывает на **новое** поколение
ключа, а `from=` на реплике — на новый адрес master'а (шаги 1.3 и 1.4).

### 1.7. Проверка сквозного цикла

```sh
# на fbsd-3-sel
zfs snapshot zroot/tank/data@repl-6
sudo /usr/local/sbin/zfs-replication.sh

# на fbsd-2-sel — через новый jump-host
ssh -J fbsd-3-sel avalok11@fbsd-2-sel.lab.sel \
    "zfs list -t snapshot -o name -r zroot/tank/repl"
```

Ожидание: `zroot/tank/repl@repl-6` появился. Это подтверждает весь цикл: новый
master → сервисный ключ → force-command → `zfs allow` → приём на реплике.

---

## Сценарий: fbsd-1-sel вернулась

`fbsd-3-sel` — дополнение, а не замена, поэтому у вернувшейся ноды **своя**
судьба, а не роль «восстановить как раньше». Данные не терялись — они
дублируются: у `fbsd-3-sel` свой `zroot/tank/data`, восстановленный с реплики.

| Вариант | Что даёт | Требования |
|---|---|---|
| **A. Ре-сид (рекомендуется)** | Наполнить ноду данными с `fbsd-3-sel`: `zfs send` → `zfs receive`. Второй практический кейс DR почти бесплатно | минимум работы; `zfs-1-sel` получает свой `zroot/tank/data` |
| **B. Третья нода HA-пары** | `fbsd-3-sel` + `fbsd-1-sel` — пара CARP для Фазы 3, `fbsd-2-sel` — реплика | сначала ре-сид, потом host-сертификат, потом в HA |
| **C. Новый источник репликации** | `fbsd-1-sel` возвращается как второй master, `fbsd-2-sel` становится общей репликой | **не рекомендуется**: два источника на одну реплику — расхождение цепочки инкрементов, `zfs receive` начнёт отвергать потоки |

**Рекомендация — A, потом B.** A даёт второй кейс восстановления почти бесплатно.
После этого нода остаётся в строю и становится вторым узлом HA-пары в Фазе 3 —
и тогда в Фазе 3 становится **три** ноды вместо двух, что позволяет проверить
split-brain, о котором в roadmap есть отдельный пункт.

**Важно:** при варианте A источником репликации остаётся `fbsd-3-sel`
(`from="172.16.0.5"`). Возвращение `fbsd-1-sel` само по себе не даёт ей права
писать в реплику — это осознанное решение, а не побочный эффект.

## Фолбэк: Selectel не даст новый VPS

Если ресурсов не будет и для `fbsd-3-sel`, план деградирует так:

| Задача | Куда переносится | Почему |
|---|---|---|
| jails, Bastille, VNET, снапшоты клонов | `fbsd-arm` (локально, arm64) | jails и Bastille архитектурно-независимы; локальную ноду можно ломать |
| bhyve и бенчмарк jail vs bhyve | `fbsd-2-sel` (Selectel, amd64, работает) | bhyve на arm64 не работает в принципе, нужен amd64 |
| репликация ZFS, DR-сценарий | отложить | требует двух нод в Selectel |
| master-функции | `fbsd-2-sel` | тогда она перестаёт быть репликой и становится единственной нодой данных |

Это хуже, чем с `fbsd-3-sel`, но работает: бhyve-часть Фазы 2 всё равно делается на
`fbsd-2-sel`, а jails-часть — локально на arm64 с честным сравнением «то же самое на
другой архитектуре».

## Чек-лист Дней 0–1

**День 0 — выполнен 2026-10-27**

- [x] VPS `fbsd-3-sel` создан: FreeBSD 15.1 amd64, 4 ГБ RAM, приватный IP `172.16.0.5`
- [x] FreeBSD установлена, sshd настроен, root-доступ закрыт
- [x] PF, sshguard, TOTP применены; конфиги сохранены в [`config/fbsd-3-sel/`](../../config/fbsd-3-sel/)
- [x] `sshd_config.d/ca.conf` применён (host-сертификат, User CA, CRL) — файл в репозитории
- [x] Host-сертификат выпущен на CA, положен в `/etc/ssh/`; `user_ca.pub` в `/etc/ssh/`, `host_ca.pub` — в `~/.ssh/` пользователя
- [x] `zroot` пришёл с образом Selectel — `zpool create` не выполнялся
- [x] Баннер исправлен — текст CA-ноды убран (2026-10-28)
- [ ] Поправить опечатку в адресе поддержки: `a.@gmail.com` → `a@gmail.com`
- [ ] **Убрать `nullok`** из `/etc/pam.d/sshd` — иначе второй фактор вырождается (см. `config/fbsd-3-sel/README.md`)
- [ ] Свести `/etc/pf.conf` с единым ruleset (делается в День 3, вместе с VNET)
- [x] Раскладка файлов CA выровнена по всему стенду: `/etc/ssh/ca/` (2026-10-28)

**День 1 — в работе**

- [ ] `fbsd-3-sel` работает как jump-host к `fbsd-2-sel`
- [ ] Данные восстановлены с реплики, 14 файлов на месте
- [ ] Новый сервисный ключ выпущен (`zfs_repl_3`), старый отозван
- [ ] CRL разложен в `/etc/ssh/ca/revoked_keys` на обеих нодах, sshd перезапущен
- [ ] `from=` в principals-файле заменён на `172.16.0.5`
- [ ] Маркер репликации посеян из фактического состояния реплики
- [ ] Скрипт репликации установлен в `/usr/local/sbin/` на новом master'е
- [ ] Сквозной цикл репликации проверен: `@repl-6` принят
