# Фаза 1 — FreeBSD актуальный: сеть, ZFS, базовый сервисный SSH

**Статус:** в работе (Неделя 3, День 2 закрыт)
**Период:** август — октябрь 2026
**Цель фазы:** уверенная работа с сетью и ZFS на актуальной FreeBSD, понимание отличий от Linux, настроенная сервисная SSH-учётка для ZFS-репликации.

> **Как читать файлы фазы.** Этот README — уровень фазы: доступ, безопасность, структура
> стенда, решения «почему так». Механизмы ZFS, команды и реальный вывод терминала живут в
> [`phase-1-zfs-report.md`](./phase-1-zfs-report.md), настройка сервисной учётки — в
> [`service-ssh-setup.md`](./service-ssh-setup.md). Детали сюда не дублируются, вместо них ссылки.

## Что сделано

- [+] Поднять `fbsd-2-sel` в Selectel (FreeBSD 15.1 amd64) — нода-реплика для ZFS
  - [+] VPS создан (1 vCPU, 1 ГБ RAM, 10 ГБ SSD)
  - [+] Пользователь `avalok11` + sudo
  - [+] sshd_config: PermitRootLogin no, PasswordAuthentication no
  - [+] sshguard + PF активированы
  - [+] ntpd синхронизирован
  - [+] Host-ключ подписан через `fbsd-ca-sel` (TTL 52w)
  - [+] `user_ca.pub` скопирован на `fbsd-2-sel` + `TrustedUserCAKeys` в `sshd_config` (user-cert вход работает)
  - [+] Вход по сертификату с Mac M4 работает (host + user проверка)
  - [+] Строка с IP `fbsd-2-sel` в `architecture.md` (внутренний `172.16.0.4`, без публичного IP)
  - [+] **TOTP снят** — jump-only нода, единственный путь входа через `fbsd-1-sel` (где TOTP уже стоит), двойной TOTP на цепочке избыточен
  - [+] Баннер — доделан (косметика)
- [+] Настройка сети на fbsd-1-sel и fbsd-2-sel (статический IP, gateway, DNS) — задокументировано в разделе «Сеть» ниже
- [+] Унификация сетевых настроек на `fbsd-2-sel` под `fbsd-1-sel`: search domain → `lab.sel`, IP в CIDR-нотации, DNS как у fbsd-1-sel
- [+] Базовая настройка PF на fbsd-1-sel и fbsd-2-sel (v1 с Фазы 0) + v2: antispoof, NAT-заглушка под jails
- [+] Применить `pf-ruleset.conf` v2 на обе ноды (`pfctl -nf` → `pfctl -f`)
- [+] Зафиксировано поведение Selectel edge (SYN/ACK на любой порт) в «Грабли»
- [+] ZFS: создание zpool, датасетов (на fbsd-1-sel: `zroot/tank` как дочерний dataset, иерархия `data/logs/repl/secure`, см. `phase-1-zfs-report.md`)
- [+] ZFS: эксперименты со снапшотами, rollback, clone
- [+] ZFS send/receive: fbsd-1-sel → fbsd-2-sel
  - [+] Первичная репликация `zroot/tank/data` → `zroot/tank/repl` по приватной сети Selectel
  - [+] Скрипт `zfs-replication.sh`: первая отправка полная, далее инкремент `zfs send -i`
  - [+] Проверено 4 итерации (1 полная + 3 инкремента), данные и снапшоты на месте
  - [+] Права на приём выданы через `zfs allow`, `sudo` на replica не требуется
  - [ ] Failover-тест (День 3) — *частично пройден 2026-10-25: шаги 4–5 успешны (реплика читается и пишется при недоступном master), шаг 6 (возврат master и продолжение инкрементов) ждёт ноду*
- [+] Шифрованный dataset (keyfile, не passphrase — для автоподъёма после ребута ) 
- [+] Сервисный SSH-пользователь `zfs-repl` с `forced-command` (ограничения в `auth_principals/%u` через `AuthorizedPrincipalsFile`, комбинируем с Фазой 0.1 CA, права на приём — `zfs allow` без sudo) — см. `service-ssh-setup.md`
- [ ] Сравнение с Linux (ext4+LVM, btrfs) на deb-arm

## Теоретические заметки

- [01-network-stack.md](./01-network-stack.md) — сетевой стек FreeBSD vs Linux: ifconfig vs ip, netstat vs ss, rc.conf
- [02-pf-vs-iptables.md](./02-pf-vs-iptables.md) — PF (Packet Filter) vs iptables/nftables, история, синтаксис
- [03-zfs-advanced.md](./03-zfs-advanced.md) — ZFS продвинутый: ARC, zpool, dataset, snapshot, send/receive, encryption, dedup
- [04-bhyve-vs-kvm.md](./04-bhyve-vs-kvm.md) — bhyve vs KVM vs VMware ESXi, нюанс arm64

## Практика

- [+] Поднять `fbsd-2-sel` в Selectel + базовый харденинг (по чек-листу Фазы 0)
- [+] Полная настройка сети на FreeBSD (rc.conf, ifconfig, route, resolv.conf)
- [+] Установка и базовая настройка PF (ssh in, всё остальное block, NAT для будущих jails)
- [+] Создание zpool, датасетов
- [+] Снапшоты, clone, rollback
- [+] Репликация fbsd-1-sel → fbsd-2-sel через ssh (сервисная учётка `zfs-repl`, `zfs allow` вместо sudo)
- [+] Шифрованный dataset с keyfile (`/etc/zfs/keys/tank-secure.key`, chmod 400)
- [+] Сервисный ssh `zfs-repl` с `forced-command` (ключ подписан через `fbsd-ca-sel` из Фазы 0.1, ограничения — в `AuthorizedPrincipalsFile`)

## План по неделям и дням (~6 ч/неделю)

### Неделя 1 — Сеть + PF
**Цель:** третья нода поднята и захардена, сеть и фаервол на обеих production-нодах задокументированы и проверены снаружи.

- **День 1 (~2 ч) — Поднять `fbsd-2-sel` в Selectel**
  - Создать VPS: 1 vCPU, 1 ГБ RAM, 10 ГБ SSD, FreeBSD 15.1 amd64, тот же регион что `fbsd-1-sel` и `fbsd-ca-sel`
  - Базовый харденинг по чек-листу Фазы 0: пользователь `avalok11` + sudo, sshd_config (PermitRootLogin no, PasswordAuthentication no, **TOTP через Yandex Key → затем снят 2026-09-06, см. решение в архитектурном разделе**), sshguard + PF, ntpd, баннер
  - Подписать host-ключ `fbsd-2-sel` через `fbsd-ca-sel` (TTL 52w)
  - Скопировать `host_ca.pub` на Mac M4, обновить `~/.ssh/ca_known_hosts`
  - Проверить вход по сертификату с Mac
  - **Артефакт:** строка с IP `fbsd-2-sel` в `architecture.md` и `roadmap.md`
  - **Итоговое состояние fbsd-2-sel по итогу Недели 1:** TOTP снят, единственная аутентификация — ed25519 + user-сертификат CA (TTL 8ч). Подробнее в `docs/architecture.md` → раздел «Безопасность на fbsd-2-sel (jump-only, без TOTP)».

- **День 2 (~2 ч) — Сеть на FreeBSD**
  - Пройтись по `fbsd-1-sel` и `fbsd-2-sel`: `/etc/rc.conf` (hostname, defaultrouter, ifconfig_vtnet0, ipv6_*), `/etc/resolv.conf`, `route -n show`, `ifconfig vtnet0`
  - Сравнить с Linux: `ifconfig` vs `ip addr`, `netstat -rn` vs `ip route`, `route add default` vs `ip route add default via`
  - Проверить `traceroute` от `fbsd-1-sel` до публичного DNS, от `fbsd-2-sel` до того же — оба должны идти через один gateway Selectel
  - Сверить с `01-network-stack.md` — если что-то устарело для FreeBSD 15.1, обновить бриф
  - **Артефакт:** раздел «Сеть» в этом README с фиксацией IP/gateway/DNS обеих нод

- **День 3 (~2 ч) — PF**
  - Поднять PF на `fbsd-1-sel` и `fbsd-2-sel`: разрешить ssh in, block всё остальное, antispoof, таблица `<sshguard>` уже работает с Фазы 0 — не сломать
  - Добавить NAT-правило под будущие jails (закомментировано, активируем в Фазе 2)
  - Проверить снаружи `nmap` — должен показать только 22/tcp
  - `telnet <ip> 80` — connection refused или timeout
  - **Артефакт:** `pf-ruleset.conf` в `docs/phase-1/`, закоммитить в репо

### Неделя 2 — ZFS
**Цель:** уверенная работа с zpool/датасетами, освоены snapshot/rollback/clone, шифрованный dataset с keyfile поднимается автоматически.

- **День 1 (~2 ч) — zpool + датасеты**
  - На `fbsd-1-sel`: посмотреть `gpart show`, выбрать второй диск (или раздел на системном диске — на Selectel один диск, делаем stripe)
  - `zpool create tank /dev/vtblk1` (или какой там vdev в Selectel)
  - Создать иерархию датасетов: `tank/data`, `tank/logs`, `tank/secure` (под шифрование), `tank/repl` (под реплику)
  - Квоты: `zfs set quota=10G tank/logs`, `zfs set reservation=5G tank/secure`
  - Проверить `zpool status`, `zfs list`, `df -h /tank`
  - **Артефакт:** `phase-1-zfs-report.md` — раздел «Структура zpool»

- **День 2 (~2 ч) — snapshot / rollback / clone**
  - Тест: создать 100 файлов в `tank/data/test`, snapshot `tank/data@test1`, удалить 50 файлов, `zfs rollback tank/data@test1`, проверить что все 100 на месте
  - Clone: `zfs clone tank/data@test1 tank/data-clone`, поиграть, `zfs destroy tank/data-clone`
  - `zpool scrub tank` (на Selectel диск маленький, пройдёт быстро)
  - `zfs send tank/data@test1 | zfs receive tank/data-restored` — локальный send/receive
  - **Артефакт:** `phase-1-zfs-report.md` — раздел «Snapshot/Rollback/Clone»

- **День 3 (~2 ч) — Шифрованный dataset**
  - `dd if=/dev/urandom of=/etc/zfs/keys/tank-secure.key bs=32 count=1` (256 бит = 32 байта)
  - `chmod 400 /etc/zfs/keys/tank-secure.key && chown root:wheel /etc/zfs/keys/tank-secure.key`
  - `zfs create -o encryption=aes-256-gcm -o keylocation=file:///etc/zfs/keys/tank-secure.key -o keyformat=raw -o mountpoint=/secure tank/secure`
  - Проверить `zfs get encryption,keylocation,keyformat tank/secure`
  - `zfs unmount tank/secure && zfs mount tank/secure` — поднимается без passphrase (autoload с keyfile)
  - Тест: создать файл с чувствительными данными, `zfs snapshot tank/secure@enc-test`, экспортнуть zpool (`zpool export tank`), импортнуть обратно (`zpool import tank`) — dataset подхватился автоматически
  - **Артефакт:** `phase-1-zfs-report.md` — раздел «Encryption с keyfile», чек-лист на passphrase-vs-keyfile решение

### Неделя 3 — Репликация + сервисный SSH
**Цель:** реплика работает end-to-end, сервисная SSH-учётка с `forced-command` принимает только `zfs receive` с правильного IP.

- **День 1 (~2 ч) — Сервисный пользователь `zfs-repl`**
  - На `fbsd-2-sel`: `pw useradd zfs-repl -s /bin/sh -m -d /home/zfs-repl` (шелл нужен, иначе `force-command` не выполнится)
  - На Mac M4: `ssh-keygen -t ed25519 -f ~/.ssh/zfs_repl -C "zfs-repl@avalok11-laptop"` (ключ рождается на ноутбуке, потому что подписывает CA на `fbsd-ca-sel`, а не нода назначения)
  - Скопировать `~/.ssh/zfs_repl.pub` на `fbsd-ca-sel`
  - На `fbsd-ca-sel`: `sudo /usr/local/sshca/scripts/sign-user-cert.sh /tmp/zfs_repl.pub zfs-repl +52w zfs-repl` (TTL 52 недели — сервисный ключ долгий; четвёртый аргумент — каталог хранения в `/usr/local/sshca/users/`)
  - **Приватный ключ положить на master** в `/root/.ssh/zfs_repl` + сертификат `zfs_repl-cert.pub`, `chmod 600`. На ноутбуке копию держать незачем — `from="172.16.0.2"` всё равно не пустит оттуда репликацию (см. «Ключевые решения»)
  - На `fbsd-2-sel`: включить `AuthorizedPrincipalsFile /etc/ssh/auth_principals/%u` в `/etc/ssh/sshd_config.d/ca.conf` + рестарт sshd
  - Создать `/etc/ssh/auth_principals/zfs-repl` с ограничениями (в конце строки — principal, а не публичный ключ):
    ```
    from="172.16.0.2",command="/usr/bin/env /sbin/zfs receive -F zroot/tank/repl",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty zfs-repl
    ```
  - `chmod 644 /etc/ssh/auth_principals/zfs-repl && chown root:wheel /etc/ssh/auth_principals/zfs-repl`
  - `/home/zfs-repl/.ssh/authorized_keys` **не создаётся** — иначе отзыв сертификата можно обойти входом по «голому» ключу
  - **Артефакт:** `service-ssh-setup.md` — пошаговая инструкция + схема ограничений

- **День 2 (~2 ч) — ZFS send/receive** — *выполнен 2026-10-10 — 2026-10-11*
  - На `fbsd-1-sel`: `zfs snapshot zroot/tank/data@repl-1`
  - На `fbsd-2-sel`: подготовить приёмник `zfs create zroot/tank` и выдать права `sudo zfs allow -u zfs-repl compression,mountpoint,mount,create,receive zroot/tank/repl`
  - Отправка (запускается от root с master, ключ в `/root/.ssh/zfs_repl`):

    ```sh
    zfs send zroot/tank/data@repl-1 | ssh -i /root/.ssh/zfs_repl zfs-repl@172.16.0.4
    ```

    После адреса узла **никакой команды не пишем** — её подставляет `force-command` на replica (грабли №1 в разделе «Грабли»).
  - Инкремент на следующей итерации: `zfs snapshot zroot/tank/data@repl-2`, затем `zfs send -i zroot/tank/data@repl-1 zroot/tank/data@repl-2 | ssh -i /root/.ssh/zfs_repl zfs-repl@172.16.0.4`
  - На `fbsd-2-sel`: `zfs list -t all -o name,used,mountpoint | grep repl` — снапшоты приходят как `zroot/tank/repl@repl-N`, данные лежат в `/zroot/tank/repl`
  - Обернуть в `zfs-replication.sh`: первый запуск без `-i` (полный поток), дальше `zfs send -i $PREV $LATEST`, прогресс в `/var/db/zfs-replication/last-snapshot`
  - Добавить в cron (позже, в Фазе 4 через Ansible) — пока запуск руками от root
  - **Артефакт:** `zfs-replication.sh` + раздел «Репликация fbsd-1-sel → fbsd-2-sel» в `phase-1-zfs-report.md` — *выполнено*

- **День 3 (~2 ч) — Тесты + failover** — *выполняется 2026-10-26*
  - **Тест 1 (source-address):** с `fbsd-ca-sel` (172.16.0.3) валидно подписанным сертификатом с principal=`zfs-repl` — ожидаем `Permission denied (publickey)`. Сертификат обязан лежать рядом с приватным ключом, иначе клиент предъявит «голый» ключ и тест проверит не то. Плюс A/B-контроль: временно разрешить `172.16.0.3` в `auth_principals/zfs-repl` и убедиться, что тот же тест начинает проходить
  - **Тест 2 (force-command + no-pty):** `sudo ssh -v -i /root/.ssh/zfs_repl zfs-repl@172.16.0.4 id < /dev/null` **с master и от root** (иначе ключ в `/root/.ssh/` нечитаем) — в debug-логе строка `Remote: principals: key options: command user-rc` (в действующем наборе опций остались только `command` и `user-rc`, ни pty, ни форвардингов) и **нет** вывода `uid=`: команда `id` не выполнялась, вместо неё отработал `zfs receive`. Строка `Sending command: id` в логе — это запрос клиента, а не выполненная команда
  - **Тест 3 (failover):** после простоя master — `zfs snapshot zroot/tank/data@repl-5`, прогон `zfs-replication.sh`, проверка на replica появления `zroot/tank/repl@repl-5`. Проверяет, что остановка ноды не порвала цепочку инкрементов
  - **Артефакт:** `service-ssh-setup.md` — раздел «Тесты», `phase-1-zfs-report.md` — раздел «Failover»

## Тестирование

- [ ] Сетевое: PF правила применены на обеих нодах; внешний nmap **не может** показать «только ssh» — edge Selectel отвечает SYN/ACK на любой порт (см. «Грабли»), реальный state проверяется изнутри через `pfctl -sr` / `pfctl -ss`
- [+] ZFS: snapshot, rollback, scrub
- [+] ZFS replication: на вторую ноду отправить dataset, на второй ноде смонтировать
- [ ] Failover-тест: симулировать падение основной ноды и проверить читаемость реплики, затем — возобновление инкрементов (День 3)
- [ ] Сервисный SSH-тест: с другого IP ключ не принимается, с правильного IP работает только `zfs receive` и не выделяется терминал (тесты 1–2 описаны в плане Дня 3 и в `service-ssh-setup.md`)

## Ключевые решения

> Сюда попадают решения **уровня фазы**: доступ, безопасность, структура стенда.
> Решения по механизмам ZFS (чем выданы права на приём, как выбирается снапшот,
> почему датасет называется от корня пула, keyfile-vs-passphrase) живут в
> [`phase-1-zfs-report.md`](./phase-1-zfs-report.md) в разделах «Решения» рядом
> с соответствующими командами и выводом.

### 2026-08-30
- **`fbsd-2-sel`: только приватный IP, jump-host через `fbsd-1-sel`.** Экономит ~150–200 ₽/мес на публичном IP, ZFS-реплика и сервисный SSH идут по `172.16.0.0/16` (быстрее, без публичного egress). Минус: при падении `fbsd-1-sel` попасть на `fbsd-2-sel` можно только через out-of-band консоль Selectel — для Фазы 1 приемлемо, в Фазе 3 (CARP) решается через VIP.
- **Сервисный ключ `zfs_repl`: TTL 52w, не 8h как у обычного `freebsd_lab`.** Репликация должна идти по расписанию без ручной переподписи каждые 8 часов. Бонус: подписывается тем же CA, отзывается через тот же CRL.

### 2026-09-06
- **`fbsd-2-sel`: TOTP снят, single-factor (ed25519 + сертификат).** У ноды нет публичного IP, единственный путь входа — через `fbsd-1-sel`, где TOTP уже стоит. Двойной TOTP на цепочке избыточен. Tradeoff сознательный: компрометация ключа на ноутбуке = вход на `fbsd-2-sel` без TOTP-приложения.
- **Сетевые настройки унифицированы на обеих нодах.** На `fbsd-2-sel` приведено к виду `fbsd-1-sel`: `search lab.sel`, CIDR-нотация в `ifconfig_vtnet0`, DNS из 4 серверов. При росте до N нод одна и та же Ansible-роль раскладывает `/etc/rc.conf` без условий.
- **PF ruleset одинаковый на обеих нодах (v2).** Единый файл `pf-ruleset.conf` в репо, в Фазе 4 Ansible просто `copy`. Изменения v1→v2: `antispoof`, `set block-policy return`, NAT-заглушка под jails (Фаза 2).

### 2026-09-13
- **`tank` сделан как дочерний dataset `zroot/tank`, а не отдельный zpool.** На Selectel VPS один диск `da0` на 30 ГБ, уже полностью размечен под систему — места под второй пул физически нет. В Фазе 3 переделать на `zpool create tank mirror ...`, данные мигрируют через `zfs rename -p`. Обоснование и параметры (`compression=lz4`, `atime=off`, `reservation=2G`) — в [отчёте](./phase-1-zfs-report.md#структура-zpool-день-1-2026-09-13).

### 2026-10-03
- **Ключ шифрования НЕ в публичном репо.** Положен в password manager (KeePassXC) в виде base64-строки. Это per-host secret, на `fbsd-2-sel` будет свой.

### 2026-10-08
- **Ограничения сервисной учётки задаются в `AuthorizedPrincipalsFile`, а не в `authorized_keys`.** При входе по сертификату sshd ищет опции по ключу CA, а не по публичному ключу пользователя, поэтому ограничения из `authorized_keys` не применяются (подробно — «Грабли» и [`service-ssh-setup.md`](./service-ssh-setup.md)). Побочный плюс: смена ограничений — правка одного файла на сервере, без переподписи. `authorized_keys` для `zfs-repl` намеренно не создаётся, иначе отзыв сертификата обходится входом по «голому» ключу.
- **У `zfs-repl` шелл `/bin/sh`, а не `/sbin/nologin`.** `force-command` sshd выполняет через login-shell, с `nologin` принудительная команда не запустится вовсе. Запрет шелла обеспечивается `no-pty` и подменой команды.

### 2026-10-11
- **Приватный ключ `zfs-repl` лежит на master (`/root/.ssh/zfs_repl`), а не на ноутбуке.** Причина техническая: `from="172.16.0.2"` пропускает соединения только с `fbsd-1-sel`, поэтому запуск репликации с Mac M4 был бы отвергнут. Побочная выгода — при потере ноутбука репликация продолжает работать, секрет не покидает периметр стенда.
- **TOTP на replica для `zfs-repl` не используется.** Учётка сервисная, вход по ed25519 + сертификату с principal=`zfs-repl`. Второй фактор для непубличной jump-only ноды избыточен: безопасность обеспечивается сертификатом, `from=`-ограничением и `force-command`.

## Сеть

Зафиксированное состояние на 2026-09-06. Снято с обеих нод командами `cat /etc/rc.conf | grep -E '...'`, `cat /etc/resolv.conf`, `ifconfig vtnet0`, `netstat -rn`. Совпадает с тем, что в `docs/architecture.md` (Принцип #6: межсервисный трафик — по `172.16.0.0/16`).

### Сводная таблица

| Параметр | `fbsd-1-sel` | `fbsd-2-sel` |
|---|---|---|
| Hostname | `fbsd-1-sel.lab.sel` | `fbsd-2-sel.lab.sel` |
| Внутренний IP | `172.16.0.2/16` (vtnet0) | `172.16.0.4/16` (vtnet0) |
| Публичный IP | `178.72.xxx.xxx` | **нет** (jump-only) |
| Gateway | `172.16.0.1` | `172.16.0.1` |
| MAC | `fa:16:3e:31:fe:bd` | `fa:16:3e:b6:60:00` |
| MTU | 1500 | 1500 |
| Link | 10Gbase-T full-duplex | 10Gbase-T full-duplex |
| IPv6 | SLAAC (`accept_rtadv`), `fe80::f816:3eff:fe31:febd` | **отключён** (`IFDISABLED` в nd6) |
| Search domain | `lab.sel` | `lab.sel` (унифицировано 2026-09-06) |
| DNS | 8.8.8.8, 1.1.1.1, 77.88.8.8, 77.88.8.1 | 8.8.8.8, 1.1.1.1, 77.88.8.8, 77.88.8.1 (унифицировано) |
| Вход с Mac M4 | напрямую | через `ssh -J fbsd-1-sel` |

### `/etc/rc.conf` (только сетевые строки)

**`fbsd-1-sel`:**
```
hostname="fbsd-1-sel.lab.sel"
ifconfig_vtnet0="inet 172.16.0.2/16"
defaultrouter="172.16.0.1"
ifconfig_vtnet0_ipv6="inet6 accept_rtadv"
```

**`fbsd-2-sel`:**
```
hostname="fbsd-2-sel.lab.sel"
ifconfig_vtnet0="inet 172.16.0.4/16"
defaultrouter="172.16.0.1"
```

> **Унифицировано 2026-09-06:** обе ноды теперь используют CIDR-нотацию (`ifconfig_vtnet0="inet .../16"`) и одинаковый search domain `lab.sel`. DNS-список тоже приведён к `fbsd-1-sel` (4 сервера: Google + Cloudflare + Yandex). См. «Ключевые решения» → 2026-09-06.

### Маршрутизация (`netstat -rn`)

Обе ноды идут через один gateway Selectel — `172.16.0.1`. Это означает, что Selectel даёт обоим VPS один L2-сегмент внутри ДЦ, и пакеты между `172.16.0.2` и `172.16.0.4` ходят **минуя публичный IP**, по приватной сети. ZFS-реплика в День 2 Недели 3 пойдёт по этому маршруту, без выхода в интернет.

Дефолтный маршрут — одинаковый на обеих нодах:
```
default            172.16.0.1         UGS         vtnet0
172.16.0.0/16      link#1             U           vtnet0
```

### Сравнение с Linux (для брифа `01-network-stack.md`)

| Действие | FreeBSD | Linux (deb-arm) |
|---|---|---|
| Посмотреть IP | `ifconfig vtnet0` | `ip addr show` |
| Таблица маршрутов | `netstat -rn` | `ip route` |
| Routing socket-статистика | `netstat -s` | `ip -s link` |
| DNS | `/etc/resolv.conf` | `/etc/resolv.conf` (идентично) |
| Статический IP | `/etc/rc.conf` (`ifconfig_vtnet0=...`) | `/etc/network/interfaces` или Netplan YAML |
| IPv6 SLAAC | `ifconfig_vtnet0_ipv6="inet6 accept_rtadv"` | `ipv6 ra_accept=1` (sysctl) или Netplan |

Самый заметный для меня как пришедшего из Linux — **отсутствие NetworkManager и netplan**. Вся сеть в одном `/etc/rc.conf`, после правки — `service netif restart` (или ребут). На маленьком стенде это плюс (прозрачно), в большом кластере с 20+ VLAN — минус (придётся писать свой шаблонизатор под `rc.conf`, отсюда в Фазе 4 — Ansible).

## Грабли и открытия

- **2026-09-06 — search domain разный: `lab.sel` vs `lab.local`.** ~~На `fbsd-1-sel` стоит `search lab.sel` (по умолчанию из панели Selectel при создании VPS), на `fbsd-2-sel` я (или шаблон Selectel) задал `search lab.local`. Технической проблемы нет, но выглядит как «две ноды в разных доменах». Решение: унифицировать на `lab.sel` (соответствует `*.lab.sel` hostname'ам) в День 3, когда будем править `rc.conf` под `pf` — заодно.~~ **Решено 2026-09-06:** на `fbsd-2-sel` поставлен `search lab.sel`, DNS-список расширен до 4 серверов (как у `fbsd-1-sel`).
- **2026-09-06 — синтаксис IP в `rc.conf` непоследовательный.** ~~`ifconfig_vtnet0="inet 172.16.0.2/16"` (CIDR) vs `ifconfig_vtnet0="inet 172.16.0.4 netmask 255.255.0.0"` (маска). Оба работают, оба задокументированы в `man rc.conf`. Привести к CIDR на `fbsd-2-sel` в День 3.~~ **Решено 2026-09-06:** на `fbsd-2-sel` переведено на CIDR-нотацию (`ifconfig_vtnet0="inet 172.16.0.4/16"`), теперь `rc.conf` обеих нод синтаксически идентичен.
- **2026-09-06 — Selectel edge отвечает SYN/ACK на любой порт публичного IP (anti-scan / port knocking).** При `nmap -Pn -p 1-1024 178.72.xxx.xxx` показывает 1024 open порта, хотя реально на ноде открыт только 22/tcp. Подтверждается тем, что `telnet 21` подключается, но `pfctl -ss` показывает только ssh/ntp-коннекты, ftp-демон не установлен, в `services` ничего сверх sshd не запущено. **Реальный state проверять через приватный IP** (`ssh -J fbsd-1-sel ... nmap -sS 172.16.0.2`) или `nmap -sA` (ACK-сканирование, показывает filtered/unfiltered вместо open). В Selectel-документации это «защита от сканирования». В проде, если захочется реальный nmap снаружи, можно попросить Selectel отключить (обычно платная опция) — для нашего кейса не блокер.
- **2026-10-08 — `authorized_keys` не применяется при входе по сертификату.** Ограничения (`from=`, `command=`, `no-*`), прописанные в `/home/zfs-repl/.ssh/authorized_keys`, **не срабатывают**, если клиент предъявляет сертификат вместо «голого» ключа. Наблюдение: с сертификатом в логе `Sending command: id` (принудительная команда не подменилась), а стоило убрать сертификат — те же ограничения отработали как надо. Причина: при аутентификации по сертификату sshd ищет опции **по ключу CA**, а не по публичному ключу пользователя; строка с пользовательским ключом как источник опций просто не читается. **Решение:** директива `AuthorizedPrincipalsFile /etc/ssh/auth_principals/%u` + файл `/etc/ssh/auth_principals/zfs-repl`, где ограничения привязаны к principal'у, а не к ключу.
- **2026-10-08 — `force-command` требует реальный шелл, `nologin` его ломает.** sshd выполняет `force-command` через login-shell пользователя. С `/sbin/nologin` сессия завершается «This account is currently not available» и принудительная команда не запускается. У `zfs-repl` шелл `/bin/sh`, запрет интерактивного входа обеспечивается `no-pty` и подменой команды. Второй эффект: `scp`/`sftp` под этой учёткой тоже не работают (им нужен шелл и Subsystem), что для сервисной реплики является плюсом.
- **2026-10-11 — `zfs allow` вместо sudoers: принцип наименьших привилегий.** На старте планировалось `zfs-repl ALL=(root) NOPASSWD: /sbin/zfs receive *`. Работает, но если `force-command` когда-нибудь обойдут — `zfs-repl` становится root на replica. Реальные права выдаёт механизм делегирования ZFS. Минимальный рабочий набор прав и почему одного `receive` мало — в разделе «Репликация» [отчёта](./phase-1-zfs-report.md).
- **2026-10-25 — ssh подставляет сертификат только если он лежит рядом с приватным ключом.** Клиент ищет сертификат по шаблону `<имя_приватного_ключа>-cert.pub` в том же каталоге. Если сертификат лежит отдельно (например, в каталоге CA `/usr/local/sshca/users/<user>/`), клиент предъявит **голый** публичный ключ — в логе это видно как `Offering public key: /tmp/zfs_repl_fromtest ED25519`, без `ED25519-CERT` и без `-cert.pub` в пути. Практический вывод: перед подключением всегда класть сертификат рядом с ключом либо указывать путь явно.

- **2026-10-25 — тест, прошедший не по той причине, хуже отсутствующего теста.** Первый прогон проверки `from=` с `fbsd-ca-sel` дал ожидаемый `Permission denied (publickey)` — и выглядел как успех. На деле он ничего не проверял: клиент предъявил голый ключ (см. предыдущий пункт), sshd не нашёл для него `authorized_keys` — а его у `zfs-repl` намеренно нет — и отказал по совершенно другой причине. Тест снёс бы `from="172.16.0.2"` из конфига и всё равно «прошёл» бы.

  Общее правило, которое стоит держать в голове при написании любых проверок: **ожидаемый результат должен быть достижим только через проверяемое свойство**. Если тест проходит при заведомо сломанной конфигурации — он ничего не проверяет. Два приёма, которые здесь помогли:
  1. Проверять в логе **механизм**, а не только результат: строка `Offering ... ED25519-CERT` доказывает, что предъявлен именно сертификат.
  2. Делать **positive control**: временно разрешить адрес (A/B) и убедиться, что тот же самый тест начинает проходить. Тогда единственной переменной остаётся `from=`.

  Это общий принцип тестирования, а не частный случай SSH: «тест зелёный» и «тест что-то доказал» — разные утверждения.
- **2026-10-26 — строка `Sending command:` в логе показывает запрос клиента, а не выполненную команду.** При проверке `force-command` ожидание было «в логе будет `Sending command: /usr/bin/env /sbin/zfs receive -F zroot/tank/repl`». Не будет: `Sending command:` формирует **клиент**, и он всегда пишит то, что *просил* выполнить. Подменённая команда подставляется на сервере и в логе клиента не видна.

  Где смотреть на самом деле — строки `Remote:` в `-v`-логе:

  ```
  debug1: Remote: cert: key options: agent-forwarding port-forwarding pty user-rc x11-forwarding
  debug1: Remote: principals: key options: command user-rc
  ```

  Вторая строка — набор опций, применённых сервером из principals-файла. Здесь в нём остались только `command` и `user-rc`: **ни** pty, **ни** port-forwarding, **ни** agent-forwarding, **ни** x11-forwarding. Это и есть доказательство подмены команды и запрета терминала.

  Побочный вывод, который стоит держать в голове отдельно: **первая строка показывает, что сам сертификат не ограничивает ничего** — в нём разрешены pty, port-forwarding, agent-forwarding и x11-forwarding. Ограничивает именно строка в `/etc/ssh/auth_principals/zfs-repl` на сервере, а эффективные права — пересечение наборов сертификата и principals-файла. Значит, граница безопасности этой учётки — не в сертификате, а в файле на сервере. И это ещё один аргумент не создавать `authorized_keys` для `zfs-repl`: появись он, principals-файл перестал бы быть единственным источником ограничений.
- **2026-10-26 — `force-command` с `zfs receive` зависает, если не перенаправить stdin.** `zfs receive` читает ZFS-поток из stdin; без `< /dev/null` stdin остаётся терминалом, и команда молча ждёт поток. В `-v`-логе это выглядит как остановка на `debug1: pledge: fork` — выглядит как «подвис SSH», а на самом деле это работает правильно, просто ждёт ввода. В тестовых командах редирект обязателен.


## Метрики

(заполнять по ходу)

## Артефакты

- [phase-1-zfs-report.md](./phase-1-zfs-report.md) — **актуально на 2026-10-11**: разделы «Структура zpool», «Snapshot/Rollback/Clone», «Encryption с keyfile», «Репликация fbsd-1-sel → fbsd-2-sel»; раздел Failover — День 3
- [pf-ruleset.conf](./pf-ruleset.conf) — **v2, актуальный**, единый ruleset для обеих нод
- [zfs-replication.sh](./zfs-replication.sh) — **создан 2026-10-11**, POSIX sh, запуск от root на master; первая отправка полная, далее инкремент
- [service-ssh-setup.md](./service-ssh-setup.md) — **актуально на 2026-10-11**: сервисная учётка `zfs-repl`, ограничения в `AuthorizedPrincipalsFile`, права через `zfs allow` (без sudo), тесты

## Что дальше

После завершения Фазы 1:
- **Фаза 2** — jails + Bastille + bhyve (3 недели)
- **Фаза 3** — HA: CARP, lagg, HAProxy (3 недели)
- И далее по roadmap.
