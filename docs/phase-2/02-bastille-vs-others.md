# Bastille: менеджер jail'ов поверх ZFS

**Цель:** понять модель Bastille — что он делает поверх примитива jail, чем отличается
от iocage и pot, и почему для FreeBSD 15 нужен другой bootstrap.

**Ключевой тезис.** Bastille — **не** реализация изоляции. Он ничего не знает про
`jail(2)`. Bastille — это менеджер, который превращает jail'ы в **ZFS-датасеты** и
управляет ими декларативно. Вся изоляция — в ядре FreeBSD, всё удобство и
шаблонизация — в Bastille.

## Модель: release → jail

```
bastille bootstrap 15.1-RELEASE
        │
        └──▶ zroot/tank/jails/releases/15.1-RELEASE/   ← «релиз», эталон
                    │
                    ├──▶ zroot/tank/jails/web/            ← jail (thin)
                    ├──▶ zroot/tank/jails/db/             ← jail (thin)
                    └──▶ zroot/tank/jails/api/            ← jail (thin)
```

Jail'ы — **потомки** датасета релиза. Отсюда бесплатные снапшоты и клоны: это
обычные операции ZFS над датасетами.

### Три типа jail'ов

| Тип | Флаг | Что внутри | Когда брать |
|---|---|---|---|
| **Thin** | по умолчанию | симлинки на файлы релиза | большинство сервисов: быстро, мало места, общий базовый слой |
| **Thick** | `-T` / `--thick` | полная копия релиза | сервис, который ставит пакеты поверх базовой системы и не должен зависеть от общего релиза |
| **Clone** | `-C` / `--clone` | `zfs clone` релиза | эксперименты: клон уничтожается без следа |

**Важное следствие для FreeBSD 15.** В 15.x базовая система управляется через
`pkgbase` — то есть сама FreeBSD теперь «пакетируется». Тонкие jail'ы, которые
симлинками ссылаются на общий релиз, с этой моделью плохо совмещаются: обновление
релиза меняет их всех разом. Поэтому:

```sh
# для FreeBSD 15.x — pkgbase-вариант
bastille bootstrap --pkgbase 15.1-RELEASE

# для FreeBSD 14.x — классический вариант
bastille bootstrap 15.1-RELEASE update
```

Подробности — в [FreeBSD Handbook, Bastille updates](https://www.freebsdhandbook.com/bastille-updates/):
для тонких jail'ов обновляется общий bootstrapped-релиз, для толстых — сам jail.

## Bastillefile: декларативное описание сервиса

Обычный `bastille create` — это разовая команда. **Bastillefile** — TOML-файл,
описывающий сервис целиком, из которого jail создаётся воспроизводимо:

```toml
jail: web
release: 15.1-RELEASE
params:
  net: {
    vnet: true,
    newvnet: true,
    address: 10.10.1.10/24,
    gateway: 10.10.1.1,
  }
services:
  - nginx
packages:
  - bash
```

Запуск:

```sh
bastille create -f Bastillefile
```

Значение: **один и тот же файл работает на arm64 и amd64**, меняется только параметр
`arch` в секции `packages` (`FreeBSD:15:amd64` → `FreeBSD:15:aarch64`). Это ровно
то, что мы проверяем на Дне 4 Недели 2.

## Конфигурация: bastille.conf

Глобальные настройки лежат в `/usr/local/etc/bastille/bastille.conf`. Имена параметров
менялись между версиями, поэтому **точные дефолты смотрим на самой ноде**:

```sh
grep -E '^bastille_(zfs_|prefix|jailsdir|releasesdir|network_|pf_)' \
     /usr/local/etc/bastille/bastille.conf
```

Ключевые параметры, которые нам нужно поменять (актуальные имена, FreeBSD 15.1,
Bastille 1.4.x):

| Параметр | Значение по умолчанию | Что делает | Что ставим |
|---|---|---|---|
| `bastille_zfs_enable` | **`NO`** | включает ли ZFS-поддержку | **`YES`** — иначе jail'ы не будут датасетами и не получат снапшотов |
| `bastille_zfs_zpool` | пусто | имя пула | `zroot` |
| `bastille_zfs_prefix` | `bastille` | датасет **без имени пула** | `tank/jails` |
| `bastille_prefix` | `/usr/local/bastille` | префикс и точка монтирования датасета | оставляем |
| `bastille_network_loopback` | `bastille0` | имя клонированного loopback-интерфейса для jail'ов | оставляем |
| `bastille_network_pf_ext_if` | `ext_if` | имя **переменной** ext_if в pf.conf | `ext_if` — у нас уже есть такая переменная |
| `bastille_network_pf_table` | `jails` | имя PF-таблицы с адресами jail'ов | оставляем |
| `bastille_network_vnet_type` | `if_bridge` | тип VNET: мост или netgraph | `if_bridge` |
| `bastille_pkgbase_packages` | `base-jail` | набор pkgbase-пакетов для bootstrap | оставляем |
| `bastille_zfs_options` | `-o compress=on -o atime=off` | свойства создаваемых датасетов | оставляем — совпадает с нашими |

**Два важных следствия.**

Первое: `bastille_zfs_enable` по умолчанию **`NO`**. Если это не переключить,
Bastille создаст jail'ы как обычные каталоги на UFS, и вся история про ZFS-снапшоты
не работает. Это не «должно работать из коробки» — это настройка.

Второе: `bastille_zfs_prefix` — **датасет без имени пула**, пул задаётся отдельно
через `bastille_zfs_zpool`. Отсюда `zroot` + `tank/jails` = `zroot/tank/jails`.

При этом `bastille_prefix` — это **точка монтирования** датасета: Bastille смонтирует
`zroot/tank/jails` в `/usr/local/bastille`, а сами jail'ы будут жить в
`${bastille_prefix}/jails`. То есть в ZFS-дереве получится `zroot/tank/jails/jails/<имя>`.
Это некрасиво, но безвредно; главное — знать, куда смотреть. Если путь раздражает,
можно задать `bastille_zfs_prefix="tank"` и получить jail'ы прямо в `zroot/tank/jails/`,
но тогда Bastille начнёт работать с уже существующим датасетом `zroot/tank`, который
несёт наши данные и логи, — риск выше. **Решение: отдельный датасет `tank/jails`,
двойное «jails» в пути принимаем.**

### `bastille setup`

Отдельная команда, готовит хост под работу Bastille:

```sh
bastille setup              # всё сразу
bastille setup storage      # только хранилище
bastille setup loopback     # только loopback-интерфейс
bastille setup firewall     # только PF
```

Ключевой момент про PF: **Bastille копирует свой дефолтный `pf.conf` в `/etc/pf.conf`
только если того ещё не существует.** У нас он существует и написан руками — значит,
Bastille его не тронет. Но и anchor'ы, которые Bastille ожидает увидеть, в нашем
ruleset отсутствуют. Поэтому в Фазе 2 (День 2) в `pf-ruleset.conf` добавляются:

```pf
table <jails> persist
nat on $ext_if from <jails> to any -> ($ext_if:0)
rdr-anchor "rdr/*"
anchor "bastille/*"
```

и `set skip on lo` вместо `set skip on $lo_if` — клонированный loopback
`bastille0` принадлежит группе `lo`, и без этого трафик jail'ов попадёт под
наши правила.

**Порядок применения:** сначала `bastille setup storage` и `bastille setup loopback`,
затем наш `pf-ruleset.conf` через `pfctl -f`, и только потом `bastille setup firewall`
либо ручная правка — чтобы Bastille не затёр наши правила.

## Сетевой слой: скрипт jib

Bastille не реализует VNET сам — этим занимается **jib** (Jail Isolate Bridge).
Он создаёт мост, `epair`-пары и правила PF для каждого jail'а. Отсюда следствие:
`bastille create` с VNET требует, чтобы сетевые параметры были согласованы между
`bastille.conf` и фактическим состоянием хоста.

## Лимиты ресурсов: bastille limits

Для наших 1 ГБ RAM это важно:

```sh
bastille limits web 512M 1      # память и число процессов
```

Под капотом — `rctl(8)` (rlimit) и `cpuset(1)`. Это даёт jail'у жёсткий потолок
памяти: переборщивший процесс убьётся по `RLIMIT_AS`, а не утащит хост в OOM.
На стенде с 1 ГБ это не украшение, а необходимость.

## Bastille против iocage и pot

| | **Bastille** | **iocage** | **pot** |
|---|---|---|---|
| Язык | Bash | Python | shell + шаблоны |
| Модель | ZFS-датасеты, декларативный TOML | jail.conf + параметры | структура каталогов + шаблоны |
| Шаблоны | Bastillefile | `iocage import` | `pot` templates |
| Формат конфига | один TOML на сервис | плоский `jail.conf` | разрозненные каталоги |
| Сеть | VNET через `jib` | VNET через epair + bridge | VNET свой |
| Лимиты | `bastille limits` (rctl) | rctl | rctl |
| Слабое место | требует ZFS | слабая шаблонизация | слабая шаблонизация |

Выбор Bastille — за **шаблонизацию**: один TOML-файл на сервис, одинаково
применимый на arm64 и amd64, и нативная опора на ZFS. Для нашей цели «один
Bastillefile работает на обеих архитектурах» это ровно то, что нужно.

## Практика: полезные команды

```sh
bastille setup storage               # подготовить хранилище
bastille setup loopback              # подготовить loopback-интерфейс
bastille bootstrap --pkgbase 15.1-RELEASE
bastille list                       # что есть: jail'ы, релизы, шаблоны
bastille create -f Bastillefile    # создать jail из файла
bastille start web / stop web / restart web
bastille cmd web sh                # команда внутри jail'а
bastille snapshot web before-change
bastille clone web web-clone
bastille destroy web-clone
bastille zfs web snapshot          # ZFS-операции над датасетом jail'а
bastille limits web 512M 1          # лимиты памяти и процессов
```

Дальше: [VNET](./03-vnet-and-network.md) — как jail получает сеть, и
[ZFS + jails](./04-zfs-and-jails.md) — почему снапшоты бесплатны.
