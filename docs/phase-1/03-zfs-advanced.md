# ZFS: продвинутый уровень

**Время чтения:** ~10–12 минут
**Фаза:** 1 (FreeBSD актуальный: сеть, ZFS, базовый сервисный SSH)
**Цель:** уверенно работать с ZFS — пулы, датасеты, снапшоты, репликация, шифрование, dedup. Понимать отличия от LVM/btrfs.

---

## 1. Что такое ZFS

**ZFS** — файловая система и менеджер томов в одном, разработана в Sun Microsystems (2001–2005), открыта под CDDL, сейчас живёт в OpenZFS (illumos, FreeBSD, Linux).

**Главная идея:** объединить ФС + менеджер томов + RAID + менеджер снапшотов в одном инструменте, с акцентом на **целостность данных** и **простоту управления**.

## 2. Архитектура ZFS

```
┌─────────────────────────────────────┐
│         ZFS Datasets (FS)           │  ← файловые системы
├─────────────────────────────────────┤
│             Zpool                   │  ← менеджер томов + RAID
│  ┌───────┐ ┌───────┐ ┌─────────┐    │
│  │ vdev1 │ │ vdev2 │ │ vdev3   │    │  ← виртуальные устройства
│  └───┬───┘ └───┬───┘ └────┬────┘    │
│      │         │          │         │
│  ┌───┴───┐ ┌───┴───┐ ┌────┴────┐    │
│  │ disk1 │ │disk2+3│ │ disk4   │    │  ← физические диски
│  └───────┘ └───────┘ └─────────┘    │
└─────────────────────────────────────┘
```

**Иерархия:**
- **Physical disk** — `/dev/da0`, `/dev/sda`.
- **vdev (virtual device)** — логическое устройство, может быть одним диском, mirror (2+ диска), raidz1/2/3 (4+ дисков).
- **Zpool** — набор vdev, общий объём, общая производительность.
- **Dataset** — файловая система внутри пула. Можно создавать сколько угодно.
- **Zvol** — блочное устройство внутри пула (для VM, например).

## 3. Создание пула

### Простой пул (stripe — без избыточности, для теста)

```bash
# Один диск
zpool create tank /dev/da0

# Создан пул 'tank', смонтирован в /tank
zpool list
# NAME   SIZE  ALLOC   FREE  CKPOINT  EXPANDSZ   FRAG    CAP  DEDUP    HEALTH  ALTROOT
# tank  39.8G   108K  39.7G        -         -     0%     0%  1.00x    ONLINE  -
```

### Mirror (зеркало, для прода)

```bash
# Зеркало из двух дисков
zpool create tank mirror /dev/da0 /dev/da1

# Можно добавить ещё одно зеркало (raid10-подобная схема)
zpool add tank mirror /dev/da2 /dev/da3
```

### Raidz1/2/3 (RAID-5/6/7 аналог)

```bash
# raidz1 — один диск на восстановление (как RAID-5)
zpool create tank raidz1 /dev/da0 /dev/da1 /dev/da2 /dev/da3

# raidz2 — два диска (как RAID-6)
zpool create tank raidz2 /dev/da0 /dev/da1 /dev/da2 /dev/da3 /dev/da4

# raidz3 — три диска
zpool create tank raidz3 /dev/da0 /dev/da1 /dev/da2 /dev/da3 /dev/da4 /dev/da5
```

**Правила:**
- **stripe** — без защиты, для тестов и неважных данных.
- **mirror** — высокая производительность, дорого (1:1 по дискам).
- **raidz1** — экономично, но **scrub после сбоя может убить пул** (ещё один диск сбойнет во время восстановления).
- **raidz2** — золотая середина для прода.
- **raidz3** — для больших пулов 12+ дисков.

## 4. Датасеты — основная единица в ZFS

**Датасет** — это файловая система внутри пула. Можно создавать сколько угодно:

```bash
# Создать датасет
zfs create tank/data

# Создать вложенные датасеты
zfs create tank/data/jails
zfs create tank/data/jails/web
zfs create tank/data/backups
zfs create tank/data/postgres

# Установить quota (лимит места)
zfs set quota=10G tank/data/postgres

# Установить recordsize (размер блока)
zfs set recordsize=16K tank/data/postgres  # для баз данных
zfs set recordsize=1M tank/data/backups   # для больших файлов

# Сжатие (zstd, lz4, gzip)
zfs set compression=lz4 tank/data          # быстрое
zfs set compression=zstd tank/data/backups # лучше для архивов
```

**Каждый датасет монтируется автоматически** в `/tank/data/jails/web` (если включено `mountpoint`).

## 5. Свойства датасетов

ZFS имеет **сотни свойств**, управляемых через `zfs set`/`zfs get`:

```bash
# Сжатие
zfs set compression=lz4 tank/data
zfs get compression tank/data
# NAME       PROPERTY     VALUE     SOURCE
# tank/data  compression  lz4      local

# Режим кэширования
zfs set primarycache=all tank/data       # ARC (в RAM)
zfs set secondarycache=all tank/data     # L2ARC (на диске)

# Deduplication (ОСТОРОЖНО!)
zfs set dedup=on tank/data               # СЖИРАЕТ ОЧЕНЬ МНОГО RAM

# Точка монтирования
zfs set mountpoint=/usr/local/jails tank/jails

# Отключить автомонтирование
zfs set mountpoint=none tank/jails

# Зарезервированное место
zfs set reservation=10G tank/postgres
```

## 6. Снапшоты — мгновенно, ничего не занимают

**Снапшот — это зафиксированное состояние датасета.** Создаётся мгновенно, занимает место только при изменениях.

```bash
# Создать снапшот
zfs snapshot tank/data@before-update

# Список снапшотов
zfs list -t snapshot
# NAME                       USED  AVAIL  REFER  MOUNTPOINT
# tank/data@before-update      0B      -  1.2G  -

# Создать ещё
zfs snapshot tank/data@2026-08-15
zfs snapshot tank/data@before-nginx-upgrade

# Откатить (ОСТОРОЖНО: текущие изменения теряются)
zfs rollback tank/data@before-update

# Удалить снапшот
zfs destroy tank/data@2026-08-15

# Удалить все старые снапшоты, оставить последние N
zfs list -t snapshot -H -o name | head -n -7 | xargs -r -n1 zfs destroy
```

**Пример с числами:**
```bash
# Допустим, dataset занимает 100 ГБ
# Создаём снапшот
zfs snapshot tank/data@snap1
# USED у снапшота: 0 (dataset не менялся)
# Создаём в нём 5 ГБ новых файлов
# USED у снапшота: 5 ГБ (хранит только дельту)
```

## 7. Clone — writable копия снапшота

```bash
# Создать clone (writable копия снапшота)
zfs clone tank/data@snap1 tank/data-clone

# Mount
zfs set mountpoint=/mnt/clone tank/data-clone

# Этот clone существует, пока существует его origin снапшот
# Чтобы отвязать: promote
zfs promote tank/data-clone
# Теперь tank/data-clone — самостоятельный dataset, оригинал можно удалить
```

**Где применяется:**
- Создание jail-а из шаблона (миллисекунды).
- Тестовое окружение на основе production.
- Rollback после неудачного деплоя.

## 8. Send/Receive — потоковая репликация

**Это killer feature ZFS.** Можно слать снапшот на удалённую ноду по ssh:

```bash
# Создать снапшот
zfs snapshot tank/data@for-replication

# Отправить на удалённую ноду
zfs send tank/data@for-replication | ssh root@backup "zfs receive tank/remote-data"

# Инкрементальная репликация (только дельты)
zfs snapshot tank/data@incremental
zfs send -i tank/data@for-replication tank/data@incremental | ssh root@backup "zfs receive tank/remote-data"
```

**Автоматизация через cron:**
```bash
#!/bin/sh
# Ежедневная репликация
zfs snapshot tank/data@$(date +%Y-%m-%d)
LATEST=$(zfs list -t snapshot -H -o name | grep "tank/data" | tail -1)
zfs send -i tank/data@previous $LATEST | ssh -i /root/.ssh/zfs-repl zfs-repl@backup "zfs receive tank/remote-data"
```

**Сжатие при передаче:**
```bash
zfs send tank/data@snap1 | gzip | ssh backup "gunzip | zfs receive tank/remote"
```

**В нашем проекте** это будет ключевой механизм для бэкапов в Фазе 6.

## 9. ARC и L2ARC — кэширование

**ARC (Adaptive Replacement Cache):**
- Кэш ZFS в оперативной памяти.
- По умолчанию ест **всё, что можно**.
- Для нашей ноды с 4 ГБ RAM — ARC будет 2–3 ГБ.

```bash
# Посмотреть размер ARC
arc_summary
# Или
sysctl kstat.zfs.misc.arcstats.size

# Ограничить ARC (например, оставить 1 ГБ для приложений)
echo "vfs.zfs.arc_max=1073741824" >> /boot/loader.conf
# 1 ГБ = 1024*1024*1024 = 1073741824 байт
```

**L2ARC:**
- Кэш на отдельном быстром диске (NVMe, SSD).
- Ускоряет чтение холодных данных.
- Не обязателен, для нашего стенда — избыточен.

**ZIL (ZFS Intent Log):**
- Лог синхронных операций записи.
- На дефолте — в RAM, но сбрасывается на диск.
- Для ускорения синхронной записи — отдельный SLOG на NVMe.

## 10. Шифрование

ZFS поддерживает нативное шифрование на уровне датасета (с OpenZFS 0.8+, FreeBSD 13+):

```bash
# Создать зашифрованный датасет
zfs create -o encryption=on -o keylocation=prompt -o keyformat=passphrase tank/secret

# Запросит пароль для разблокировки

# Mount
zfs mount tank/secret

# При загрузке нужно ввести пароль (или сохранить ключ)
```

**Для автоматической разблокировки** (менее безопасно):
```bash
# Сгенерировать ключ
dd if=/dev/urandom of=/etc/zfs/secret.key bs=32 count=1
chmod 600 /etc/zfs/secret.key

# Создать датасет с ключом
zfs create -o encryption=on -o keylocation=file:///etc/zfs/secret.key -o keyformat=raw tank/secret

# При загрузке — загрузить ключ
zfs load-key tank/secret
zfs mount tank/secret
```

## 11. Dedup — дедупликация

**Dedup** убирает дубликаты блоков. Мощно, но **требует много RAM** (5 ГБ RAM на 1 ТБ данных для dedup-таблицы).

```bash
# Включить dedup (ТОЛЬКО если у тебя много RAM)
zfs set dedup=on tank/data

# Статус dedup
zpool get dedupratio tank
# NAME PROPERTY    VALUE          SOURCE
# tank  dedupratio 1.05x          local
```

**Правило:** dedup оправдан **только** на специализированных стораджах с большим RAM. На 4 ГБ VPS — **не включать**.

## 12. Scrub — проверка целостности

ZFS умеет **самовосстанавливаться** при наличии избыточности. `scrub` читает все блоки, проверяет контрольные суммы, пересчитывает повреждённые:

```bash
# Запустить scrub
zpool scrub tank

# Статус
zpool status
# ...
# scan: scrub repaired 0 in 1h23m with 0 errors on Sun Aug 10 12:00:00 2026
```

**Рекомендация:** запускать scrub раз в неделю по cron. Ночью, когда нагрузка минимальна.

```bash
# В /etc/crontab
0 3 * * 0 root /sbin/zpool scrub tank
```

## 13. Сравнение с LVM+ext4 и btrfs

| Фича | ZFS | LVM + ext4 | btrfs |
|---|---|---|---|
| Менеджер томов + ФС | ✅ вместе | ❌ раздельно (LVM) | ✅ вместе |
| Copy-on-write | ✅ | ❌ | ✅ |
| Снапшоты | ✅ мгновенные | ⚠️ через LVM (медленнее) | ✅ мгновенные |
| RAID | ✅ mirror, raidz1/2/3 | через mdadm | ✅ встроенный |
| Самовосстановление | ✅ scrub | ❌ нет | ✅ scrub |
| Шифрование | ✅ на уровне датасета | ✅ LUKS | ❌ нет нативно (через LUKS) |
| Сжатие | ✅ lz4, zstd, gzip | ❌ нет (отдельно) | ✅ zlib, lzo, zstd |
| Send/Receive | ✅ нативно | ❌ нет | ✅ send/receive |
| Зрелость | ✅ 20+ лет | ✅ LVM 30+ лет, ext4 15+ лет | ⚠️ стабилизируется |
| Лицензия | CDDL | GPL | GPL |
| Документация | ✅ отличная | ✅ отличная | ⚠️ средняя |

**Когда что:**

- **ZFS** — для NAS, бэкапов, виртуализации, продакшена где нужна целостность данных.
- **LVM+ext4** — для обычных Linux-серверов, где не нужны снапшоты.
- **btrfs** — для OpenSUSE/SUSE, на Fedora, где-то на десктопе. Для серьёзного прода **всё ещё осторожно**.

## 14. ZFS на Linux (ZOL)

**Да, ZFS работает на Linux** через OpenZFS. Но:

- **Лицензионный конфликт:** CDDL vs GPL, поэтому ZFS не может быть в mainline Linux kernel. Поставляется как модуль через DKMS.
- **Работает стабильно**, но не нативно.
- **В продакшене** — лучше FreeBSD или illumos (Solaris-форки).
- **На нашем `deb-arm`** — можно поставить через `apt install zfsutils-linux`, но это для эксперимента, не для прода.

## 15. Команды для нашего проекта

**На FreeBSD-нодах (Faza 1+):**

```bash
# Создать пул для jail-ов и данных
zpool create tank /dev/vtnet1    # (если есть отдельный диск)

# Создать датасеты
zfs create tank/jails
zfs create tank/data
zfs create tank/backups

# Сжатие
zfs set compression=lz4 tank

# Снапшоты по cron
zfs snapshot tank/jails@$(date +%Y-%m-%d)

# Репликация на fbsd-arm (для теста)
zfs send tank/jails@snap1 | ssh avalok11@192.168.64.2 "zfs receive tank/replicated"
```

## Что почитать

- FreeBSD Handbook, Chapter 19 (ZFS): https://docs.freebsd.org/en/books/handbook/zfs/
- «FreeBSD Mastery: ZFS» и «FreeBSD Mastery: Advanced ZFS» (Michael W. Lucas) — ты их уже читаешь.
- OpenZFS docs: https://openzfs.github.io/openzfs-docs/
- «ZFS on Linux» ( сайт проекта): https://zfsonlinux.org/
