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

> **Кто что создаёт** (проверено по исходникам Bastille 1.4.4):
>
> | Команда | Что делает |
> |---|---|
> | `bastille setup storage` | **только** пишет в `bastille.conf` `bastille_zfs_enable=YES` и `bastille_zfs_zpool`. Датасеты **не создаёт** |
> | `bastille setup loopback` | клонирует `lo1`, переименовывает в `bastille0`, пишет в `rc.conf` `cloned_interfaces+=lo1` и `ifconfig_lo1_name="bastille0"` |
> | `bastille setup vnet` | **безопасен**: кладёт `jib` из `/usr/share/examples/jails/jib` в `/usr/local/bin/jib` и пишет `/etc/devfs.rules` с `bastille_vnet=13`. PF не трогает |
> | `bastille setup bridge <if>` | создаёт мост `<if>bridge` и **добавляет в него физический интерфейс `<if>`** (`ifconfig <if>bridge addm <if> up`), ставит `net.inet.ip.forwarding=1` и `net.link.bridge.pfil_{bridge,onlyip,member}=0`, пишет в `rc.conf` `cloned_interfaces+=bridge0`, `ifconfig_bridge0_name="<if>bridge"`, `ifconfig_<if>bridge="addm <if> up"`. Адрес на мост **не** вешает |
> | `bastille bootstrap` | **создаёт всё дерево датасетов**: `${zpool}/${prefix}` (монтируется в `/usr/local/bastille`), `.../jails`, `.../releases`, `.../logs`, `.../templates`, `.../backups`, `.../cache` |
> | `bastille create` | создаёт датасет конкретного jail'а: `${zpool}/${prefix}/jails/<имя>` и `.../root` |
>
> Отсюда важное следствие: `bastille_zfs_enable` и `bastille_zfs_zpool` должны быть
> выставлены **до** `bootstrap` — иначе он создаст дерево датасетов по умолчанию
> (`zroot/bastille/...`), а не там, где мы решили.
>
> **А вот `setup bridge` мы не запускаем** — и это не каприте, а следствие трёх
> вещей: (1) он добавляет физический интерфейс в мост, а на FreeBSD 15 адрес
> интерфейсу-члену моста назначать уже нельзя — Handbook, «VNET Jails»: адрес
> должен быть на самом мосте; (2) у нашего `vtnet0` — единственный адрес ноды,
> и потерять связь с Selectel-сетью нельзя; (3) `pfil_bridge=0` отключает
> инспекцию bridged-трафика, и трафик jail'а, идущий через мост, ушёл бы мимо PF.
> Мост мы создаём сами — см. [VNET](./03-vnet-and-network.md).

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
    address: 10.10.10.10/24,
    gateway: 10.10.10.1,
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
| `bastille_network_pf_table` | `jails` | имя PF-таблицы с адресами jail'ов | оставляем — но для VNET-jail'ов она всё равно пуста, см. ниже |
| `bastille_network_gateway` | пусто | шлюз для VNET-jail'ов. Без него Bastille берёт шлюз маршрута по умолчанию хоста (`172.16.0.1`) — это не наш шлюз | **`10.10.10.1`** — адрес на мосте `bridge0` |
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
bastille setup              # всё сразу — НЕЛЬЗЯ
bastille setup storage      # только хранилище — безопасно
bastille setup loopback     # только loopback-интерфейс — безопасно
bastille setup vnet         # только jib и devfs.rules — безопасно
bastille setup firewall     # только PF — НЕЛЬЗЯ
bastille setup bridge <if>  # мост — см. ниже, у нас не используется
```

Безопасны ровно три: `storage`, `loopback`, `vnet`. Остальные либо переписывают
наш `pf.conf` (`firewall`), либо кладут физический интерфейс в мост (`bridge`).

#### Опасность: `bastille setup firewall` переписывает наш `pf.conf`

> **Проверено по исходникам Bastille 1.4.4** (`usr/local/share/bastille/setup.sh`,
> функция `configure_pf`). Раньше здесь было написано, что Bastille трогает
> `/etc/pf.conf` только если его ещё нет. **Это неверно**, и ошибка опасная.

Поведение `configure_pf` на **существующем** `/etc/pf.conf`, который не создан
Bastille:

```sh
sed -i '' "1i\
## Bastille firewall configuration - start\
ext_if="$ext_if"\
\
set block-policy return\
scrub in on \$ext_if all fragment reassemble\
set skip on lo\
\
table <jails> persist\
nat on \$ext_if from <jails> to any -> (\$ext_if:0)\
rdr-anchor "rdr/*"\
\
block in all\
pass out quick keep state\
antispoof for \$ext_if\
\
anchor "bastille/*"\
pass in proto tcp from any to any port ssh flags S/SA keep state\
## Bastille firewall configuration - end
"
```

То есть Bastille **вставляет свой блок в начало** файла. А в нём — `block in all`.

**Что это значит на самом деле.** Раньше здесь было написано, что блок Bastille
со своим `block in all` «обрубает SSH». Это верно только при неверной семантике
«первое совпадение решает». Настоящая семантика PF — **последнее совпавшее
правило выигрывает** («For `block` and `pass`, the last matching rule decides
what action is taken», `pf.conf(5)`, раздел PACKET FILTERING; OpenBSD PF FAQ:
«The last matching rule wins»). С нашим порядком правил (`block in all` выше
разрешений) получается:

- `block in all` из блока Bastille окажется **выше** наших правил, и наши
  разрешения (стоящие ниже) его перебьют — SSH продолжит работать;
- но `pass out quick keep state` из блока Bastille окажется **выше** всего
  нашего ruleset'а и, будучи `quick`, станет терминальным для исходящего
  трафика: наши правила ниже для исходящих пакетов разбираться не будут;
- `set block-policy return` из блока Bastille — это **опция**, а не правило:
  она действует на весь ruleset, и наше значение её не переопределяет;
- `scrub`, NAT, `table <jails>`, `rdr-anchor` и `anchor "bastille/*"`
  продублируются. Для трансляции действует «первое совпадение»
  (`pf.conf(5)`, раздел TRANSLATION), поэтому при двух NAT-правилах на одну
  подсеть решает то, что стоит выше;
- `set skip on lo` из блока Bastille и наш `set skip on lo` конфликтом **не**
  являются: флаги skip накапливаются, а не перезатираются (pfctl сбрасывает их
  целиком перед каждой загрузкой ruleset'а и применяет заново из файла).

Итог: `bastille setup firewall` не «обрубает SSH», но **молча превращает наш
ruleset в гибрид**: часть политики дублируется, часть выключается, а файл в
репозитории перестаёт соответствовать ноде — а у нас инвариант «`config/` —
как применено». Поэтому не запускаем.

Отдельно: голый `bastille setup` (без опций) вызывает `configure_pf` наравне с
`configure_storage` и `configure_loopback_interface`, поэтому **и он запускать
нельзя**.

**Что делаем вместо.** Нужен `bastille setup storage` и `bastille setup loopback`
(безопасны), а PF сводим **вручную** — в Фазе 2, День 3, в тот же
`pf-ruleset.conf`. Блок Bastille показывает, что именно он ожидает увидеть:

```pf
table <jails> persist
nat on $ext_if from <jails> to any -> ($ext_if:0)
rdr-anchor "rdr/*"
anchor "bastille/*"
```

и `set skip on lo` вместо `set skip on $lo_if` — клонированный loopback
`bastille0` принадлежит группе `lo`, и без этого трафик jail'ов попадёт под
наши правила. Заметь: в блоке Bastille `set skip on lo` уже есть — то есть
наша правка совпадает с тем, что Bastille считает правильным.

**Порядок применения:** `bastille setup storage` → `bastille setup loopback` →
`bastille setup vnet` → наш ruleset через `pfctl -f`. Команду `bastille setup firewall`
на `fbsd-3-sel` не запускаем никогда.

**Осторожно: таблица `<jails>` для VNET-jail'ов остаётся пустой.** В `start.sh`
(исходники 1.4.4) добавление адреса jail'а в таблицу обёрнуто в проверку
`if [ "$(bastille config ${jail} get vnet)" != 'enabled' ]` — то есть только для
jail'ов **без** VNET. Поэтому `nat on $ext_if from <jails> to any -> ($ext_if:0)`
из блока Bastille для нашего VNET-jail'а **не сработает**: NAT у нас сделан по
подсети `10.10.10.0/24`. Таблицу `<jails>` мы в ruleset оставляем — Bastille
проверяет её наличие, — но наполняться она будет только для jail'ов без VNET.

## Сетевой слой: скрипт jib

Bastille не реализует VNET сам — этим занимается **jib** (Jail Isolate Bridge).
Он создаёт `epair`-пару, поднимает интерфейсы и добавляет хост-сторону в мост.

Но `jib` работает **только в режиме `-V` (стандартный VNET)**: там он сам создаёт
мост `<if>bridge` и добавляет в него физический интерфейс — ровно то, чего мы
решили избегать. В режиме `-B` (мост) `jib` не вызывается вовсе: хост-сторона
`epair` добавляется в готовый мост напрямую (`ifconfig <bridge> addm <epair>`),
а параметры сети попадают в jail через шаблон `default/vnet` — он пишет в
`/etc/rc.conf` jail'а `ifconfig_vnet0="inet <ip>"` и `defaultrouter="<шлюз>"`.

Мы идём по второму пути: мост `bridge0` создаём сами, без физического интерфейса
внутри. Подробности — в [VNET](./03-vnet-and-network.md).

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
bastille setup vnet                  # подготовить jib и devfs.rules
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
