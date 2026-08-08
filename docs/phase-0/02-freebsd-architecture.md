# Архитектурный обзор FreeBSD 14/15

**Время чтения:** ~7–9 минут
**Фаза:** 0 (вводная теория перед практикой)
**Цель:** понимать ключевые подсистемы FreeBSD и расположение основных файлов — для эффективной работы в последующих фазах.

---

## 1. Общая архитектура

FreeBSD — **монолитное ядро с модулями**. Базовое ядро `GENERIC` содержит только критичные подсистемы (планировщик, VFS, базовые сетевые протоколы). Дополнительные файловые системы, файрволы, сетевые подсистемы, драйверы подгружаются как **модули ядра** (`.ko` файлы) в `/boot/kernel/` и `/boot/modules/`.

**Пример. Проверка текущей конфигурации ядра:**

```bash
# Базовая версия ядра
uname -v
# FreeBSD 14.3-RELEASE #1 releng/14.3-n1234567: ...

# Список загруженных модулей
kldstat
# Id Refs Address                Size     Name
#  1   97 0xffffffff80200000  1d4f4a0  kernel
#  2    1 0xffffffff81f4f000  1c7a8    pf.ko
#  3    1 0xffffffff81f6c000  5b340    zfs.ko
# ...

# Подключить модуль на лету (например, filesystems)
kldload ext2fs

# Выгрузить
kldunload ext2fs
```

Что это даёт на практике:
- **Минимальная базовая система** — `uname -v` показывает GENERIC, размер `/boot/kernel` — около 60–100 МБ.
- **Без пересборки ядра** можно подключить ZFS, PF, добавить драйверы через `kldload`.
- **Модули можно выгружать** на лету через `kldunload` — в Linux это работает не для всех модулей.

## 2. Файловая система и загрузка

**Корень по умолчанию — ZFS** (с FreeBSD 10). Это значит:
- Корневой пул `zroot` создаётся установщиком автоматически.
- `zfs list` показывает дерево датасетов.
- `beadm` (есть из коробки в 14.x) управляет загрузочными окружениями.

**Пример. Дерево датасетов и beadm:**

```bash
# Показать датасеты
zfs list
# NAME                 USED  AVAIL  REFER  MOUNTPOINT
# zroot               2.81G  27.2G    96K  /zroot
# zroot/ROOT          1.61G  27.2G    96K  none
# zroot/ROOT/default  1.61G  27.2G  1.58G  /
# zroot/home           188K  27.2G   112K  /home
# zroot/tmp           2.69M  27.2G  2.69M  /tmp
# zroot/var           1.13G  27.2G  1.13G  /var

# Загрузочные окружения
beadm list
# BE      Active Mountpoint  Space Created
# default NR      /            2.8G  2026-08-01
```

**Где что лежит:**

| Путь | Назначение |
|---|---|
| `/etc/rc.conf` | Главный конфиг сервисов (sshd_enable, hostname, IP) |
| `/etc/rc.d/` | Стартовые скрипты сервисов (sh, не bash) |
| `/etc/rc.local` | Локальные кастомизации, выполняется последним |
| `/etc/sysctl.conf` | Параметры ядра (sysctl) |
| `/etc/ssh/sshd_config` | Конфиг SSH-демона |
| `/etc/pf.conf` | Конфиг PF-файрвола |
| `/etc/syslog.conf` | Логирование |
| `/boot/loader.conf` | Параметры загрузчика (модули, тюнинг) |
| `/usr/local/etc/` | Конфиги портов и пакетов (аналог /etc в Linux) |
| `/var/log/` | Логи |

**Загрузка:**
- **UEFI-режим** (на современном железе) — загрузчик `loader.efi`, читает `/boot/loader.conf`.
- **Legacy BIOS** (для совместимости) — MBR + `boot0`/`boot1`/`boot2`.
- После загрузчика — старт ядра, монтирование корня (через `zfs` или `ufs`), запуск `/etc/rc` (POSIX sh-скрипт), который подтягивает `/etc/rc.d/*` и `/etc/rc.local`.

## 3. Capsicum — capability-режим

**Capsicum** — capability-based security подход, встроенный в FreeBSD. Идея:
- Процесс может находиться в «capability-режиме» — тогда ему доступны только заранее выданные capabilities (права на конкретные файлы, сокеты, операции).
- Процесс **не может** обойти это ограничение, даже если у него есть root-права.
- Используется в **jail v2** и **bhyve** для внутренней изоляции.

**Что это даёт:**
- Jail-процессы, даже скомпрометированные, не могут выйти за пределы выданного набора прав.
- Это сильнее, чем **AppArmor** в Linux (там ограничения навешиваются на пути, а не capabilities).
- Ближайший аналог в Linux — это **seccomp-bpf** (фильтр системных вызовов) + namespaces, но менее гранулярно.

## 4. Jail v2 — контейнеризация

**Jail** — механизм изоляции, появившийся ещё в FreeBSD 4.x. В 14/15 — **Jail v2** (полностью переписан в 13.x):
- Изолированная файловая система (через ZFS-датасет).
- Изолированная сеть (VNET или общий IP).
- Изолированные процессы, пользователи.
- Свой `uname`, hostname, IP-стек.
- Ограничения по CPU/памяти через RCTL.

**Пример. Базовые операции с jail:**

```bash
# Список активных jail-ов
jls
#   JID  IP Address    Hostname     Path
#     1  192.168.1.10  web-jail     /usr/local/jails/web

# Выполнить команду внутри jail
jexec 1 uname -a
# FreeBSD web-jail 14.3-RELEASE FreeBSD 14.3-RELEASE ...

# Остановить jail
jail -r 1
```

**Сравнение с Docker:**
- Docker использует namespaces + cgroups из Linux. Jail был раньше и нативно.
- Docker тащит overlayfs, containerd, runc, целую экосистему. Jail — это просто `jail(8)`.
- ZFS-snapshot клонирует jail за миллисекунды, Docker image слои требует пересборки.

## 5. bhyve — гипервизор

**bhyve** (от «BSD hypervisor») — нативный гипервизор FreeBSD, в ядре с 10.0:
- Поддерживает **только amd64** (и x86 с VT-x/AMD-V). На arm64 не работает.
- Полная эмуляция оборудования: можно запускать Linux, Windows, другие BSD.
- Управляется через `vm-bhyve` (обёртка на bash) или руками через `bhyvectl`.
- Производительность близка к KVM/QEMU.

**Когда что:**
- **Jail** — для изоляции сервисов, деплоя, dev-сред. Лёгкие, быстрые.
- **bhyve** — для полноценных гостевых ОС (нужны Linux-приложения, Windows, другая FreeBSD-версия).

## 6. ZFS — файловая система и менеджер томов

**ZFS** — комбайн «всё в одном»:
- Файловая система (CoW, snapshots, clones).
- Менеджер томов (vdev, zpool — без LVM).
- Менеджер RAID (mirror, raidz1/2/3 — без mdadm).
- Менеджер снапшотов и репликации.
- ARC/L2ARC — свой кэш в RAM и на диске.

**Пример. Создание пула и снапшотов:**

```bash
# Создать зеркальный пул из двух дисков
zpool create tank mirror /dev/da0 /dev/da1

# Создать датасет
zfs create tank/data

# Снапшот
zfs snapshot tank/data@before-update

# Откат
zfs rollback tank/data@before-update

# Репликация на удалённую ноду
zfs send tank/data@before-update | ssh backup zfs receive tank/remote-data
```

**Сильные стороны:**
- `zfs snapshot` — мгновенный, занимает минимум места до удаления дельт.
- `zfs send | zfs receive` — потоковая репликация, в т.ч. через ssh.
- `zfs clone` — writable копия снапшота, мгновенная.
- Шифрование на уровне датасета: `zfs create -o encryption=on tank/secure`.
- Самовосстановление: `scrub` читает всё, находит и чинит повреждённые блоки (если есть redundancy).

**Слабые стороны:**
- Жрёт RAM (ARC ест всё, что можно отдать).
- На Linux — через ZFS-on-Linux, формально работает, но не нативно.

## 7. PF — Packet Filter

**PF** (из OpenBSD, перенесён во FreeBSD) — стейтфул-файрвол:
- Конфиг в `/etc/pf.conf`, синтаксис читабельный, иерархия через `anchors`.
- Таблицы для блокировки IP (sshguard использует их).
- NAT, rdr (port forwarding), scrub (нормализация пакетов) — всё в одном файле.

**Пример. Минимальный `/etc/pf.conf`:**

```
# Переменные
ext_if = "vtnet0"
tcp_services = "{ ssh, http, https }"

# Таблица для заблокированных IP (использует sshguard)
table <sshguard> persist

# Базовые правила
block in all
pass out all keep state

# Разрешить входящие на типовые сервисы
pass in proto tcp to port $tcp_services

# Заблокировать IP из таблицы sshguard
block in quick from <sshguard> to any
```

**Сравнение с iptables/nftables:**
- Синтаксис PF проще: правила читаются сверху вниз, последнее совпавшее выигрывает.
- В Linux — порядок правил критичен, длинные цепочки, легко запутаться.
- nftables упростили жизнь, но PF всё равно читается лучше.

## 8. netgraph

**netgraph** — фреймворк для построения сетевых пайплайнов из нод:
- Каждая нода — отдельный сетевой модуль (фильтр, шейпер, балансировщик, VPN).
- Ноды соединяются в граф через `ngctl`.
- Используется для сложных сетевых топологий: мост между jail-ами, кастомные VPN, traffic shaping.
- В Linux аналогов нет в таком виде. Ближайшее — eBPF + XDP, но это совсем другая парадигма.

## 9. Сравнение с Linux (RHEL/Debian)

| Подсистема | FreeBSD | RHEL/Debian |
|---|---|---|
| Менеджер пакетов | `pkg` (бинарные), `ports` (из исходников) | `dnf`/`apt` (бинарные), из исходников вручную |
| Где конфиги сервисов | `/etc/rc.conf` + `/etc/rc.d/<service>` | `/etc/<service>/<service>.conf`, юниты systemd в `/lib/systemd/` |
| Файрвол | PF | iptables / nftables / firewalld |
| Изоляция | jail | namespaces + cgroups (Docker/LXC) |
| Виртуализация | bhyve | KVM/QEMU |
| Логи | `/var/log/`, syslog | то же + journald (бинарный лог) |
| Сервисы | rc.d (POSIX sh) | systemd (свой бинарь + D-Bus) |
| Сетевой фильтр | IPFilter, PF, ipfw | nftables, iptables, eBPF |
| Сеть | ifconfig + `/etc/rc.conf` | `ip`, NetworkManager / systemd-networkd |
| Группы пользователей | традиционные | + SELinux/AppArmor роли |

**Главное отличие в философии:** FreeBSD — **всё в ОС**, многое из коробки, без демонов-посредников. Linux — **модульная экосистема**, где разные компоненты от разных вендоров (systemd от Red Hat, snap от Canonical, docker от dotCloud, k8s от Google).

## 10. arm64 vs amd64 — что доступно, что нет

| Подсистема | amd64 | arm64 |
|---|---|---|
| Базовое ядро | ✅ | ✅ |
| ZFS | ✅ | ✅ |
| Jail | ✅ | ✅ |
| PF | ✅ | ✅ |
| CARP | ✅ | ✅ (с оговорками) |
| **bhyve** | ✅ | ❌ (только amd64) |
| **Netgraph с аппаратной поддержкой** | ✅ | ⚠️ частично |
| Проприетарные модули (NVIDIA, ZFS-Enterprise) | ✅ | ❌ |

**Для практики это значит:**
- Локально на M4 (arm64) — всё кроме bhyve.
- В Selectel (amd64) — всё, включая bhyve.
- bhyve практикуется только в Selectel.

## Что почитать

- FreeBSD Handbook, Chapter 3 (Fundamental Concepts): https://docs.freebsd.org/en/books/handbook/basics/
- «Absolute FreeBSD» (Lucas) — главы 6–9.
- FreeBSD Architecture Handbook (для глубокого погружения).
- Capsicum: https://www.cl.cam.ac.uk/research/security/capsicum/
