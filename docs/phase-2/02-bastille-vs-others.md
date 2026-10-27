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

Глобальные настройки лежат в `/usr/local/etc/bastille/bastille.conf`:

| Параметр | Значение по умолчанию | Что делает |
|---|---|---|
| `bastille_jails_path` | `zroot/jails` | **где живут jail'ы** — нам нужен свой, `zroot/tank/jails` |
| `bastille_jails_base` | `zroot` | базовый путь для ZFS-операций |
| `bastille_jails_network` | `bridge0` | имя моста для VNET |
| `bastille_jails_nat` | `bridge0` | интерфейс, на котором работает NAT |
| `bastille_jails_dns` | `1.1.1.1 9.9.9.9` | DNS для jail'ов |

**Первое, что мы поменяем — `bastille_jails_path`.** Иначе jail'ы уедут в
`zroot/jails`, минуя нашу иерархию `zroot/tank/*`, где все датасеты наследуют
`compression=lz4` и `atime=off`. Плюс датасет `zroot/tank/jails` был запланирован
ещё в Фазе 1.

### `bastille setup`

Отдельная команда, готовит хост под работу Bastille:

```sh
bastille setup
```

Она настраивает loopback-интерфейс, хранилище (ZFS, если включён) и **pf**.
Ключевой момент: `bastille setup` правит PF сам — значит, наши правки в
`pf-ruleset.conf` могут быть перезаписаны. Порядок важен: сначала `bastille setup`,
затем применить наш ruleset поверх.

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
bastille setup                      # подготовить хост (loopback, ZFS, pf)
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
