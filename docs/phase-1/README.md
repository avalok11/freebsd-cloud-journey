# Фаза 1 — FreeBSD актуальный: сеть, ZFS, базовый сервисный SSH

**Статус:** в работе
**Период:** август 2026
**Цель фазы:** уверенная работа с сетью и ZFS на актуальной FreeBSD, понимание отличий от Linux, настроенная сервисная SSH-учётка для ZFS-репликации.

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
- [+] Базовая настройка PF на fbsd-1-sel и fbsd-2-sel (v1 с Фазы 0) + v2: antispoof, NAT-заглушка под jails
- [ ] Применить `pf-ruleset.conf` v2 на обе ноды (`pfctl -nf` → `pfctl -f`)
- [ ] ZFS: создание zpool, датасетов
- [ ] ZFS: эксперименты со снапшотами, rollback, clone
- [ ] ZFS send/receive: fbsd-1-sel → fbsd-2-sel
- [ ] Шифрованный dataset (keyfile, не passphrase — для автоподъёма после ребута)
- [ ] Сервисный SSH-пользователь `zfs-repl` с `forced-command` (комбинируем с Фазой 0.1 CA)
- [ ] Тест failover репликации
- [ ] Сравнение с Linux (ext4+LVM, btrfs) на deb-arm

## Теоретические заметки

- [01-network-stack.md](./01-network-stack.md) — сетевой стек FreeBSD vs Linux: ifconfig vs ip, netstat vs ss, rc.conf
- [02-pf-vs-iptables.md](./02-pf-vs-iptables.md) — PF (Packet Filter) vs iptables/nftables, история, синтаксис
- [03-zfs-advanced.md](./03-zfs-advanced.md) — ZFS продвинутый: ARC, zpool, dataset, snapshot, send/receive, encryption, dedup
- [04-bhyve-vs-kvm.md](./04-bhyve-vs-kvm.md) — bhyve vs KVM vs VMware ESXi, нюанс arm64

## Практика

- [ ] Поднять `fbsd-2-sel` в Selectel + базовый харденинг (по чек-листу Фазы 0)
- [ ] Полная настройка сети на FreeBSD (rc.conf, ifconfig, route, resolv.conf)
- [ ] Установка и базовая настройка PF (ssh in, всё остальное block, NAT для будущих jails)
- [ ] Создание zpool, датасетов
- [ ] Снапшоты, clone, rollback
- [ ] Репликация fbsd-1-sel → fbsd-2-sel через ssh
- [ ] Шифрованный dataset с keyfile (`/etc/zfs/keys/tank-secure.key`, chmod 400)
- [ ] Сервисный ssh `zfs-repl` с `forced-command` (можно подписывать ключ через `fbsd-ca-sel` из Фазы 0.1)

## План по неделям и дням (~6 ч/неделю)

### Неделя 1 — Сеть + PF
**Цель:** третья нода поднята и захардена, сеть и фаервол на обеих production-нодах задокументированы и проверены снаружи.

- **День 1 (~2 ч) — Поднять `fbsd-2-sel` в Selectel**
  - Создать VPS: 1 vCPU, 1 ГБ RAM, 10 ГБ SSD, FreeBSD 15.1 amd64, тот же регион что `fbsd-1-sel` и `fbsd-ca-sel`
  - Базовый харденинг по чек-листу Фазы 0: пользователь `avalok11` + sudo, sshd_config (PermitRootLogin no, PasswordAuthentication no, TOTP через Yandex Key), sshguard + PF, ntpd, баннер
  - Подписать host-ключ `fbsd-2-sel` через `fbsd-ca-sel` (TTL 52w)
  - Скопировать `host_ca.pub` на Mac M4, обновить `~/.ssh/ca_known_hosts`
  - Проверить вход по сертификату с Mac
  - **Артефакт:** строка с IP `fbsd-2-sel` в `architecture.md` и `roadmap.md`

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
  - На `fbsd-2-sel`: `pw useradd zfs-repl -s /sbin/nologin -m -d /home/zfs-repl`
  - `mkdir -p /home/zfs-repl/.ssh && chmod 700 /home/zfs-repl/.ssh`
  - На Mac M4: `ssh-keygen -t ed25519 -f ~/.ssh/zfs_repl -C "zfs-repl@avalok11-laptop"`
  - Скопировать `~/.ssh/zfs_repl.pub` на `fbsd-2-sel` в `/tmp/`, оттуда на `fbsd-ca-sel`
  - На `fbsd-ca-sel`: `sudo /usr/local/sshca/scripts/sign-user-cert.sh /tmp/zfs_repl.pub zfs-repl +52w` (TTL 52 недели — сервисный ключ долгий)
  - Скопировать `zfs_repl-cert.pub` обратно на `fbsd-2-sel` в `/home/zfs-repl/.ssh/`
  - Создать `/home/zfs-repl/.ssh/authorized_keys` с жёсткими ограничениями:
    ```
    from="178.72.xxx.xxx",command="/usr/bin/env zfs receive -F tank/repl",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty ssh-ed25519 AAAA... avalok11-laptop
    ```
    (IP — публичный `fbsd-1-sel`)
  - `chmod 600 /home/zfs-repl/.ssh/authorized_keys && chown -R zfs-repl:zfs-repl /home/zfs-repl/.ssh/`
  - **Артефакт:** `service-ssh-setup.md` — пошаговая инструкция + шаблон `authorized_keys`

- **День 2 (~2 ч) — ZFS send/receive**
  - На `fbsd-1-sel`: `zfs snapshot tank/data@repl-test`
  - `zfs send tank/data@repl-test | ssh -i ~/.ssh/freebsd_lab-cert avalok11@fbsd-2-sel.lab.sel "sudo /usr/bin/env zfs receive -F tank/repl/data"`
  - Если ssh-сессия под `avalok11`, а не `zfs-repl` — это для отладки. Для боевой реплики — отдельный ключ `zfs-repl`
  - На `fbsd-2-sel`: проверить `zfs list tank/repl/data`, смонтировать, `ls` — данные на месте
  - Обернуть в `zfs-replication.sh`: инкрементальный `zfs send -i tank/data@prev tank/data@new`
  - Добавить в cron (позже, в Фазе 4 через Ansible) — пока руками через `cron` на 15 минут для теста
  - **Артефакт:** `zfs-replication.sh` в `docs/phase-1/`

- **День 3 (~2 ч) — Тесты + failover**
  - **Тест 1 (forced-command):** с Mac M4 `ssh -i ~/.ssh/zfs_repl-cert zfs-repl@fbsd-2-sel.lab.sel ls` — должно отказать, выполняется только `zfs receive`
  - **Тест 2 (from=):** с другого IP (попробовать с `fbsd-arm.lab.local` через UTM-роутер, или просто записать левый IP в `from=` и убедиться что reject) — ключ не принимается
  - **Тест 3 (nologin):** `ssh -i ~/.ssh/zfs_repl-cert zfs-repl@fbsd-2-sel.lab.sel` — сразу `Connection closed by authenticating user zfs-repl`
  - **Тест 4 (failover):** остановить `fbsd-1-sel` через панель Selectel, проверить что `tank/repl` на `fbsd-2-sel` смонтирован и читаем
  - **Тест 5 (scrub):** `zpool scrub tank` на обеих нодах, `zpool status` — `done` без ошибок
  - **Артефакт:** `service-ssh-setup.md` — раздел «Тесты», `phase-1-zfs-report.md` — раздел «Failover»

## Тестирование

- [ ] Сетевое: PF правила работают, nmap снаружи показывает только ssh
- [ ] ZFS: snapshot, rollback, scrub
- [ ] ZFS replication: на вторую ноду отправить dataset, на второй ноде смонтировать
- [ ] Failover-тест: симулировать падение основной ноды
- [ ] Сервисный SSH-тест: зайти под `zfs-repl` интерактивно отказать, с другого IP ключ не принимается, с правильного IP работает только `zfs receive`

## Ключевые решения

- **2026-09-06 — fbsd-2-sel: TOTP снят, single-factor (ed25519 + сертификат).** У ноды нет публичного IP, единственный путь входа — через `fbsd-1-sel` (jump-host), на котором TOTP уже стоит. Двойной TOTP на цепочке избыточен. Защита ноды — пара ed25519-ключ + сертификат CA с TTL 8h. Tradeoff сознательный: компрометация ключа на ноуте = вход на fbsd-2-sel, но без TOTP-приложения. Если позже захочется жёстче — добавим `from="172.16.0.2"` в `authorized_keys` (только с jump-host'а).
- **2026-08-30 — fbsd-2-sel: только приватный IP, jump-host через fbsd-1-sel.** Экономит ~150–200 ₽/мес на публичном IP, ZFS-реплика и сервисный SSH идут по `172.16.0.0/16` (быстрее, без публичного egress). Минус: в случае падения fbsd-1-sel нужно лезть в панель Selectel, чтобы попасть на fbsd-2-sel напрямую — для Фазы 1 приемлемо, в Фазе 3 (CARP) — будет решена через VIP.
- **2026-08-30 — шифрованный dataset: keyfile, не passphrase.** `zfs create -o encryption=aes-256-gcm -o keylocation=file:///etc/zfs/keys/tank-secure.key -o keyformat=raw tank/secure`. Keyfile `chmod 400`, владелец `root:wheel`. Даёт автоподъём после ребута без ручного ввода passphrase — нужно для сервисных данных (`zfs-repl` будет туда писать). Passphrase-вариант отвергнут: некому вводить ключ после ребута ноды в Selectel.
- **2026-08-30 — сервисный ключ zfs_repl: TTL 52w (не 8h как у обычного freebsd_lab).** Сервисные репликации должны идти по расписанию без ручной переподписи каждые 8 часов. Бонус: ключ подписывается через `fbsd-ca-sel` (Фаза 0.1) — единый процесс с пользовательскими ключами, revoke через тот же CRL.
- **2026-09-06 — PF ruleset одинаковый на обеих нодах (v2).** Единый файл `docs/phase-1/pf-ruleset.conf` в репо, раскладывается одинаково на fbsd-1-sel и fbsd-2-sel. Преимущество: рассинхрона нет, в Фазе 4 Ansible просто `copy: src=pf-ruleset.conf dest=/etc/pf.conf`. Изменения в v1→v2: добавлен `antispoof` (обязательная гигиена, в v1 отсутствовал), `set block-policy return` (RST на закрытые порты — косметика, не безопасность), закомментированный NAT-блок под jails (Фаза 2), закомментированный rate-limit на ssh (уже есть sshguard).

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
| Search domain | `lab.sel` | `lab.local` |
| DNS | 8.8.8.8, 1.1.1.1, 77.88.8.8, 77.88.8.1 | 8.8.8.8, 77.88.8.8 |
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
ifconfig_vtnet0="inet 172.16.0.4 netmask 255.255.0.0"
defaultrouter="172.16.0.1"
```

> **Нюанс синтаксиса FreeBSD:** на `fbsd-1-sel` используется CIDR-нотация (`172.16.0.2/16`), на `fbsd-2-sel` — `inet + netmask`. Оба варианта валидны (`man rc.conf` → `ifconfig_<if>`), но непоследовательны — задокументировано в «Грабли» ниже. К единому виду приведём в День 3 (PF), когда будем править `rc.conf` под `pf`-загрузку.

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

- **2026-09-06 — search domain разный: `lab.sel` vs `lab.local`.** На `fbsd-1-sel` стоит `search lab.sel` (по умолчанию из панели Selectel при создании VPS), на `fbsd-2-sel` я (или шаблон Selectel) задал `search lab.local`. Технической проблемы нет, но выглядит как «две ноды в разных доменах». Решение: унифицировать на `lab.sel` (соответствует `*.lab.sel` hostname'ам) в День 3, когда будем править `rc.conf` под `pf` — заодно.
- **2026-09-06 — синтаксис IP в `rc.conf` непоследовательный.** `ifconfig_vtnet0="inet 172.16.0.2/16"` (CIDR) vs `ifconfig_vtnet0="inet 172.16.0.4 netmask 255.255.0.0"` (маска). Оба работают, оба задокументированы в `man rc.conf`. Привести к CIDR на `fbsd-2-sel` в День 3.

## Метрики

(заполнять по ходу)

## Артефакты

- [phase-1-zfs-report.md](./phase-1-zfs-report.md) — отчёт о результатах ZFS-тестов
- [pf-ruleset.conf](./pf-ruleset.conf) — **v2, актуальный**, единый ruleset для обеих нод
- [zfs-replication.sh](./zfs-replication.sh) — скрипт репликации
- [service-ssh-setup.md](./service-ssh-setup.md) — документация по сервисной SSH-учётке

## Что дальше

После завершения Фазы 1:
- **Фаза 2** — jails + Bastille + bhyve (3 недели)
- **Фаза 3** — HA: CARP, lagg, HAProxy (3 недели)
- И далее по roadmap.
