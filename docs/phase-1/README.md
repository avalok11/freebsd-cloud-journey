# Фаза 1 — FreeBSD актуальный: сеть, ZFS, базовый сервисный SSH

**Статус:** в работе
**Период:** август 2026
**Цель фазы:** уверенная работа с сетью и ZFS на актуальной FreeBSD, понимание отличий от Linux, настроенная сервисная SSH-учётка для ZFS-репликации.

## Что сделано

- [+] Поднять `fbsd-2-sel` в Selectel (FreeBSD 15.1 amd64) — нода-реплика для ZFS
  - [+] VPS создан (1 vCPU, 1 ГБ RAM, 10 ГБ SSD)
  - [+] Пользователь `avalok11` + sudo
  - [+] sshd_config: PermitRootLogin no, PasswordAuthentication no, TOTP
  - [+] sshguard + PF активированы
  - [+] ntpd синхронизирован
  - [+] Host-ключ подписан через `fbsd-ca-sel` (TTL 52w)
  - [+] Вход по сертификату с Mac M4 работает (host-проверка)
  - [+] Строка с IP `fbsd-2-sel` в `architecture.md` (внутренний `172.16.0.4`, без публичного IP)
  - [ ] Баннер — **не доделан**
  - [ ] `user_ca.pub` скопирован на `fbsd-2-sel` + `TrustedUserCAKeys` в `sshd_config` + рестарт sshd — **не доделан** (без этого вход под `avalok11` по сертификату не работает)
- [ ] Настройка сети на fbsd-1-sel и fbsd-2-sel (статический IP, gateway, DNS)
- [ ] Базовая настройка PF на fbsd-1-sel и fbsd-2-sel
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

(заполнять по ходу)

## Грабли и открытия

(заполнять по ходу)

## Метрики

(заполнять по ходу)

## Артефакты

- [phase-1-zfs-report.md](./phase-1-zfs-report.md) — отчёт о результатах ZFS-тестов
- [pf-ruleset.conf](./pf-ruleset.conf) — базовый набор правил PF с комментариями
- [zfs-replication.sh](./zfs-replication.sh) — скрипт репликации
- [service-ssh-setup.md](./service-ssh-setup.md) — документация по сервисной SSH-учётке

## Что дальше

После завершения Фазы 1:
- **Фаза 2** — jails + Bastille + bhyve (3 недели)
- **Фаза 3** — HA: CARP, lagg, HAProxy (3 недели)
- И далее по roadmap.
