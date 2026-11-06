# Phase 2 — Jail Report

Отчёт по работе с jails, Bastille и bhyve на FreeBSD 15.1 в Фазе 2. Заполняется
по дням Недели 1, 2 и 3.

> **Что здесь и что не здесь.** Этот файл — **механизмы и детали**: команды, реальный
> вывод терминала, параметры, схемы, технические грабли. Решения уровня фазы (что
> строим, какие ноды трогаем, почему так) и чеклисты живут в
> [`README.md`](./README.md). Чтобы не было двух источников правды, решения не
> дублируются: здесь они лежат рядом с соответствующими командами.

> **Нумерация дней** — по плану фазы ([`README.md`](./README.md)). Дни 0–2 выпали
> из плана: они появились, когда `fbsd-1-sel` выбыла из-за нехватки ресурсов в
> Selectel и на стенд пришлось ставить новую ноду. День 0 — развёртывание ноды,
> День 1 — восстановление данных, День 2 — установка Bastille.

---

## День 0 — Развёртывание `fbsd-3-sel` (2026-10-27)

**Нода:** fbsd-3-sel (Selectel, FreeBSD 15.1 amd64, 4 ГБ RAM, 40 ГБ SSD, приватный IP `172.16.0.5`)

### Почему этот день вообще появился

Миграция компаний в ДЦ Selectel исчерпала свободные ресурсы: `fbsd-1-sel` —
бывший master и единственный jump-host к реплике — **не запускается**. `fbsd-ca-sel`
и `fbsd-2-sel` работают: они на другом физическом сервере, который не затронут.

Что было потеряно: доступ к `fbsd-2-sel` (её единственный путь — через
`fbsd-1-sel`), master-датасет и источник репликации.

### Ключевое решение: дополнение, а не замена

Адреса не переиспользуются. `172.16.0.2` остаётся за выбывшей нодой,
`fbsd-3-sel` получила `172.16.0.5`. Данные не теряются, а дублируются: master
поднимаем заново и восстанавливаем **с собственной реплики** — это готовый
DR-сценарий, проверенный в Фазе 1 на failover.

### Параметры VPS

| Параметр | Значение | Комментарий |
|---|---|---|
| RAM | 4 ГБ | снимает риск bhyve (гость 512 МБ) и даёт запас под CARP/HAProxy Фазы 3 |
| Диск | 40 ГБ | |
| IP | `172.16.0.5` | приватный, внутри сети Selectel |
| vCPU | 2 по плану | фактическое значение отдельно не подтверждалось |

### ZFS-структура: пул пришёл с образом

```
$ zpool status zroot
  pool: zroot
 state: ONLINE
config:

	NAME        STATE     READ WRITE CKSUM
	zroot       ONLINE       0     0     0
	  da0p3     ONLINE       0     0     0

errors: No known data errors
```

Команда `zpool create zroot /dev/da0` из первоначального плана на этой ноде
**не выполнялась** — пул уже пришёл с образом Selectel, и повторный `zpool create`
его бы сломал. На `fbsd-1-sel` пул создавался руками, потому что там был другой
путь установки; здесь — нет.

```
$ zfs list zroot/tank
NAME         USED  AVAIL  REFER  MOUNTPOINT
zroot/tank   688K  35.4G    96K  /zroot/tank
```

### Hardening и сертификаты

Применены PF, sshguard, TOTP, host-сертификат через CA, баннер. Конфиги сохранены
в репозитории **как применены** — [`config/fbsd-3-sel/`](../../config/fbsd-3-sel/),
расхождения с целевым состоянием зафиксированы в README ноды.

### Подводные камни Дня 0

**`nullok` вырождает второй фактор.** В `/etc/pam.d/sshd`:

```
auth sufficient /usr/local/lib/pam_google_authenticator.so nullok
auth required   pam_unix.so no_warn try_first_pass
```

при `AuthenticationMethods publickey,keyboard-interactive:pam` в
`00-hardening.conf`. `nullok` для пользователя **без** TOTP-секрета возвращает
**успех**, ничего не спрашивая; `sufficient` немедленно завершает стек PAM, и
`pam_unix` не выполняется вовсе. Итог: для такого пользователя второй фактор —
формальность, фактически остаётся один. Исправление — убрать `nullok`.

Здесь же была ошибка в моей же документации: «исправление» предлагалось сделать
через `auth required`. В PAM `required` не прерывает стек при успехе — после него
продолжают выполняться остальные `required`-модули. С `required` на обоих
получилось бы требование TOTP **и** пароля одновременно. Правильно — снять
`nullok` и оставить `sufficient`: успешный TOTP немедленно завершает стек, пароль
не спрашивается.

**Баннер CA-ноды на обычной ноде.** `issue.net` был скопирован с `fbsd-ca-sel`
вместе с текстом «This is a SECURITY-SENSITIVE node (SSH CA)». Нода не CA, и по
логин-экрану нельзя понять, где ты находишься. Плюс опечатка в адресе поддержки:
`a.@gmail.com` вместо `a@gmail.com`. Общее правило: **при копировании конфигов
с ноды на ноду проверяй, что идентичность ноды в них изменилась** — баннер,
hostname, ключи CA.

**Раскладка файлов CA различалась между нодами.** `ca.conf` на `fbsd-3-sel`
указывал `TrustedUserCAKeys /etc/ssh/user_ca.pub` и
`RevokedKeys /etc/ssh/revoked_keys`, на `fbsd-2-sel` — `/etc/ssh/ca/...`.
Для обеих директив это **путь**, а не указание «использовать CRL»: файл, положенный
не по указанному пути, sshd просто не прочитает, и **отзыв сертификата не
сработает молча** — при полностью успешном виде процедуры. Выровнено на
`/etc/ssh/ca/` для всего стенда.

**Ошибочное утверждение про host-сертификат.** Я утверждал, что сертификат обязан
лежать рядом с приватным host-ключом. Это **клиентское** правило (для
*пользовательских* ключей клиент `ssh` ищет `<имя_ключа>-cert.pub` рядом с
приватным ключом). Для host-сертификата директива `HostCertificate` принимает
явный путь, а требование одно — публичный ключ в сертификате должен совпадать с
host-ключом из `HostKey`:

> Specifies a file containing a public host certificate. The certificate's public
> key must match a private host key already specified by HostKey.
> — `sshd_config(5)`

**PF на ноде упрощённый относительно единого ruleset.** Нет `antispoof quick for
$ext_if`, переменная SSH-порта называется `tcp_service` вместо `tcp_services`, а
`set skip on lo0` вместо `set skip on lo` — последнее важно для Bastille. Сведение
с `docs/phase-1/pf-ruleset.conf` отложено на День 3.

## День 1 — Восстановление данных и смена ключа (2026-10-30)

**Цель:** вернуть стенду рабочее состояние — доступ к реплике, данные master'а и
рабочий цикл репликации.

### Шаг 1. `fbsd-3-sel` становится jump-host'ом

Прямого маршрута с Mac M4 к `fbsd-2-sel` нет — у реплики только приватный IP и
единственный путь был через выбывшую `fbsd-1-sel`. Новая нода с публичным IP
стала этим путём. В `~/.ssh/config` на Mac:

```
Host fbsd-2-sel
    HostName 172.16.0.4
    User avalok11
    IdentityFile ~/.ssh/freebsd_lab
    IdentitiesOnly yes
    ProxyJump fbsd-3-sel
```

```
$ ssh fbsd-2-sel 'hostname; zfs list -t snapshot -o name -r zroot/tank/repl'
fbsd-2-sel.lab.sel
NAME
zroot/tank/repl@repl-1
zroot/tank/repl@repl-2
zroot/tank/repl@repl-3
zroot/tank/repl@repl-4
zroot/tank/repl@repl-5
```

Чтобы jump-host работал, на `fbsd-3-sel` пришлось разрешить TCP-forwarding с
ограничением по адресам — иначе `ssh -J` давал
`channel 0: open failed: administratively prohibited`:

```
DisableForwarding no
AllowTcpForwarding yes
PermitOpen 172.16.0.4:22
PermitOpen 172.16.0.3:22
```

`PermitOpen` ограничивает и SOCKS-прокси (`-D`), то есть «открыть» здесь
означает ровно два адреса — реплику и CA.

### Шаг 2. Восстановление данных с реплики

Это и есть DR-сценарий: master поднимается с собственной реплики. Поток —
`zfs send -R` со всеми снапшотами, приём — `zfs receive` в новый датасет.

Предусловие: `zroot/tank` на новом master'е должен существовать, иначе `zfs receive`
не сможет создать в нём `zroot/tank/data`.

```sh
ssh fbsd-3-sel 'zfs list zroot/tank' || \
  ssh fbsd-3-sel 'sudo zfs create zroot/tank && sudo zfs set compression=lz4 atime=off zroot/tank'

ssh fbsd-2-sel 'sudo zfs send -R zroot/tank/repl@repl-5' \
  | ssh fbsd-3-sel 'sudo -n zfs receive zroot/tank/data'
```

`sudo` на реплике требует пароля, поэтому в конвейере пароль ввести нельзя —
поток перекачивался через файл:

```sh
ssh fbsd-2-sel 'sudo zfs send -R zroot/tank/repl@repl-5 > /tmp/restore.zfs'
scp fbsd-2-sel:/tmp/restore.zfs /tmp/
scp /tmp/restore.zfs fbsd-3-sel:/tmp/
ssh fbsd-3-sel 'sudo zfs receive zroot/tank/data < /tmp/restore.zfs'
```

Результат на новом master'е:

```
$ zfs list -t snapshot -o name -r zroot/tank/data
NAME
zroot/tank/data@repl-1
zroot/tank/data@repl-2
zroot/tank/data@repl-3
zroot/tank/data@repl-4
zroot/tank/data@repl-5
```

Файлы на месте, но лежат не в корне датасета, а в двух подкаталогах — так было
на `fbsd-1-sel`, и `zfs send -R` переносит структуру как есть:

```
$ find /zroot/tank/data/test -type f | wc -l        # 100
$ find /zroot/tank/data/repl-test -type f | wc -l   # 14
```

### Шаг 3. Ключ репликации: ротация не потребовалась

План предполагал, что приватный ключ `zfs_repl` потерян вместе с нодой, и
предписывал выпустить новый, подписать его на CA **в отдельном каталоге**
(`zfs_repl_3`) и отозвать старый через CRL — первый реальный отзыв сертификата в
курсе.

Фактически ключ **уцелел**: он был в бэкапе (KeePassXC), поэтому на новый master'е
просто переиспользован — тот же приватный ключ, тот же сертификат, тот же
principal `zfs-repl`. Отзывать нечего, CRL не пересобирался, каталог
`zfs_repl_3` на CA не создавался.

Побочный эффект: **первая задуманная ротация ключа и первый отзыв сертификата в
курсе не состоялись.** Процедура осталась в плане как регламент на случай реальной
утечки.

Ловушку в CA мы нашли и закрыли заранее, при разборе скрипта: `sign-user-cert.sh`
копирует публичный ключ в каталог CA только если там ещё нет файла с таким
именем, а `ssh-keygen -s` подписывает **файл из каталога**, а не переданный.
Повторная подпись в тот же каталог выпустила бы сертификат **на старый ключ** —
новый приватный ему не соответствует, и вход на реплику упал бы с невнятной
ошибкой, при которой виноватой выглядела бы реплика, а не CA. Скрипт теперь
сверяет ключи и отказывается с объяснением.

### Шаг 4. `from=` на реплике

```
$ cat /etc/ssh/auth_principals/zfs-repl
from="172.16.0.2,172.16.0.5",command="/usr/bin/env /sbin/zfs receive -F zroot/tank/repl",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty zfs-repl
```

### Шаг 5. Маркер и скрипт репликации

Скрипт `zfs-replication.sh` жил только на `fbsd-1-sel`; на новой ноде его не
было, а шаг проверки цикла его вызывает. Установлен в
`/usr/local/sbin/zfs-replication.sh` с константами:

```
DATASET="zroot/tank/data"
REPLICA="zfs-repl@172.16.0.4"
KEY="/root/.ssh/zfs_repl"
STATE="/var/db/zfs-replication/last-snapshot"
```

`DATASET` и `REPLICA` менять не пришлось: нода стала master'ом с тем же набором
датасетов, реплика осталась прежней.

### Шаг 6. Сквозной цикл

```sh
ssh fbsd-3-sel 'sudo zfs snapshot zroot/tank/data@repl-6 && sudo /usr/local/sbin/zfs-replication.sh'
```

```
$ ssh fbsd-2-sel 'zfs list -t snapshot -o name -r zroot/tank/repl'
NAME
zroot/tank/repl@repl-1
zroot/tank/repl@repl-2
zroot/tank/repl@repl-3
zroot/tank/repl@repl-4
zroot/tank/repl@repl-5
zroot/tank/repl@repl-6
```

Стенд снова живой: `fbsd-3-sel` — источник данных, `fbsd-2-sel` — реплика,
доступ к реплике идёт через новый jump-host.

### Подводные камни Дня 1

**Опечатка в `from=` закрывает доступ молча.** Сначала получилось
`from="172.16.0.2,172.6.0.5"` — потерянная цифра `1` в адресе нового master'а.
sshd сравнивает адрес источника посимвольно и просто отказывает в
аутентификации; скрипт репликации падает на `Permission denied (publickey)`, а
снапшот `@repl-6` при этом **создаётся** — и снапшот на master'е выглядит как
успех. Проверять надо **реплику**, а не master.

**Маркер надёжнее списка снапшотов.** `/var/db/zfs-replication/last-snapshot`
пишется **только после** успешной отправки: при ошибке `set -e` прерывает
скрипт, маркер остаётся прежним. Поэтому `repl-6` в маркере доказывает
доставку, а `@repl-6` в `zfs list` на master'е — нет.

**`ls -l` показал два каталога, а не файлы.** Данные лежат в подкаталогах
`test/` и `repl-test/`; считать надо рекурсивно через `find`.

**Сертификат обязан лежать рядом с приватным ключом.** На master'е это
`/root/.ssh/zfs_repl-cert.pub` рядом с `/root/.ssh/zfs_repl` — иначе клиент
предъявит голый публичный ключ, а у `zfs-repl` намеренно нет
`authorized_keys`, и вход откажет. Это клиентское правило, в отличие от
host-сертификата (см. День 0).

**`ssh-keygen` без `-N ""` спрашивает passphrase и зависает.** У сервисного
ключа пароля быть не должно: скрипт репликации работает без участия человека
(в Фазе 4 — из cron).

**Два master'а на одну реплику.** В `from=` оставлены оба адреса, а сервисный
ключ теперь лежит на новом master'е. Пока `fbsd-1-sel` не запускается — безопасно.
Но если она вернётся и запустит свою репликацию, на реплике окажется **два
источника с одним ключом**: инкременты перестанут быть линейной цепочкой, и
`zfs receive` начнёт отвергать потоки. Убрать `172.16.0.2` из списка, когда роль
`fbsd-1-sel` определится.

## День 2 — Bastille: установка и bootstrap (2026-11-05)

**Нода:** fbsd-3-sel (стала master'ом: ZFS, репликация, jails, Bastille, bhyve)

### Установка

```sh
sudo pkg install -y bastille
```

Актуальная на момент установки версия — **1.4.4**.

### `bastille.conf`

Файл создаётся автоматически: при первом запуске любой команды `bastille`
срабатывает `bastille_conf_check`, который копирует
`bastille.conf.sample` в `bastille.conf`. Дальше — три параметра:

```sh
sudo sysrc -f /usr/local/etc/bastille/bastille.conf \
  bastille_zfs_enable=YES \
  bastille_zfs_zpool=zroot \
  bastille_zfs_prefix=tank/jails
```

`bastille_zfs_enable` по умолчанию **`NO`** — без него jail'ы создавались бы
просто каталогами на UFS, и вся история со снапшотами ZFS не работала бы.

`bastille_zfs_prefix` — датасет **без имени пула**, пул задаётся отдельно. Плюс
Bastille добавляет к префиксу `/jails/<имя>` сам, поэтому при `tank/jails` jail'ы
лежат в `zroot/tank/jails/jails/<имя>`. Двойное «jails» — осознанный размен:
Bastille получает отдельный датасет вместо `zroot/tank`, где живёт наша
реплицируемая дата. Альтернатива `bastille_zfs_prefix="tank"` дала бы jail'ы
прямо в `zroot/tank/jails/`, но заставила бы Bastille работать с датасетом,
который несёт наши данные.

### `setup`: только два пункта

```sh
sudo bastille setup storage
sudo bastille setup loopback
```

**Кто что создаёт** (проверено по исходникам Bastille 1.4.4):

| Команда | Что делает |
|---|---|
| `bastille setup storage` | **только** пишет в `bastille.conf` `bastille_zfs_enable=YES` и `bastille_zfs_zpool`. Датасеты **не создаёт** |
| `bastille setup loopback` | клонирует `lo1`, переименовывает в `bastille0`, пишет в `rc.conf` `cloned_interfaces+=lo1` и `ifconfig_lo1_name="bastille0"` |
| `bastille bootstrap` | **создаёт всё дерево датасетов**: `${zpool}/${prefix}` (монтируется в `/usr/local/bastille`), `.../jails`, `.../releases`, `.../logs`, `.../templates`, `.../backups`, `.../cache` |
| `bastille create` | создаёт датасет конкретного jail'а: `${zpool}/${prefix}/jails/<имя>` и `.../root` |

Отсюда порядок: `bastille_zfs_enable` и `bastille_zfs_zpool` должны быть
выставлены **до** `bootstrap` — иначе дерево создастся по умолчанию
(`zroot/bastille/...`), а не там, где мы решили.

### Bootstrap через pkgbase

В FreeBSD 15 базовая система управляется через `pkgbase`, поэтому тонкие jail'ы
собираются так:

```sh
sudo bastille bootstrap --pkgbase 15.1-RELEASE
```

Bastille использует **собственный** repo-конфиг для pkgbase, так что ветка
(`latest`/`quarterly`) в системном `pkg` не важна; установка неинтерактивная
(`ASSUME_ALWAYS_YES`). Имя пакета в конфиге — `base-jail`, а префикс
`FreeBSD-set-` Bastille подставляет сама: реально ставится `FreeBSD-set-base-jail`.

### Дерево датасетов

```
$ sudo zfs list -r zroot/tank/jails
NAME                                     USED  AVAIL  REFER  MOUNTPOINT
zroot/tank/jails                         515M  34.9G   104K  /usr/local/bastille
zroot/tank/jails/backups                  96K  34.9G    96K  /usr/local/bastille/backups
zroot/tank/jails/cache                   192K  34.9G    96K  /usr/local/bastille/cache
zroot/tank/jails/cache/15.1-RELEASE       96K  34.9G    96K  /usr/local/bastille/cache/15.1-RELEASE
zroot/tank/jails/jails                    96K  34.9G    96K  /usr/local/bastille/jails
zroot/tank/jails/logs                     96K  34.9G    96K  /var/log/bastille
zroot/tank/jails/releases                514M  34.9G    96K  /usr/local/bastille/releases
zroot/tank/jails/releases/15.1-RELEASE   514M  34.9G   514M  /usr/local/bastille/releases/15.1-RELEASE
zroot/tank/jails/templates                96K  34.9G    96K  /usr/local/bastille/templates
```

Релиз — 514 МБ, это и есть установленный `FreeBSD-set-base-jail`.

```
$ sudo bastille list
 JID  Name        Boot  Prio  State  Type   IP Address  Published Ports  Release  Tags
```

Пусто — **так и должно быть**: `bastille list` показывает jail'ы, а их создание
(`bastille create`) запланировано на День 3. Релиз проверяется отдельно:

```sh
sudo bastille list releases
```

### Подводные камни Дня 2

**`bastille setup firewall` переписывает наш `pf.conf` — и это ломает доступ к
ноде.** Проверено по исходникам 1.4.4 (`setup.sh`, функция `configure_pf`): если
`/etc/pf.conf` существует и не создан Bastille, Bastille **вставляет свой блок
в начало файла**:

```
## Bastille firewall configuration - start
ext_if="vtnet0"

set block-policy return
scrub in on $ext_if all fragment reassemble
set skip on lo

table <jails> persist
nat on $ext_if from <jails> to any -> ($ext_if:0)
rdr-anchor "rdr/*"

block in all
pass out quick keep state
antispoof for $ext_if

anchor "bastille/*"
pass in proto tcp from any to any port ssh flags S/SA keep state
## Bastille firewall configuration - end
```

В PF выигрывает **последнее совпавшее** правило («For `block` and `pass`, the last
matching rule decides what action is taken», `pf.conf(5)`, раздел PACKET FILTERING;
OpenBSD PF FAQ: «The last matching rule wins»), поэтому блок Bastille сам по себе
не «обрубает» SSH — наши разрешения, стоящие ниже, его перебьют. Реальный вред
в другом: дублируются `scrub`, NAT и anchor'ы, `set block-policy return` меняет
политику блокировки для всего ruleset, а `pass out quick keep state` из блока
Bastille оказывается выше нашего ruleset'а и становится терминальным для
исходящего трафика. Плюс файл в репозитории перестаёт соответствовать ноде.
Голый `bastille setup` (без опций) вызывает `configure_pf` наравне с остальными
шагами, поэтому он опасен так же.

Поэтому запускались только `setup storage` и `setup loopback`, а anchor'ы Bastille
добавляются в наш `pf-ruleset.conf` вручную — на Дне 3. Блок Bastille заодно
показывает, что он ожидает увидеть: `table <jails>`, `nat from <jails>`,
`rdr-anchor "rdr/*"`, `anchor "bastille/*"` и `set skip on lo` — то есть ровно то,
что мы и собирались дописать.

**`setup storage` не создаёт датасеты.** Он только пишет два параметра в конфиг.
Дерево создаёт `bootstrap`. Кто-то, ожидая датасет сразу после `setup storage`,
не дождётся его — и решит, что ZFS-режим не включился.

**`setup loopback` изменил `/etc/rc.conf` на ноде** — добавил
`cloned_interfaces+=lo1` и `ifconfig_lo1_name="bastille0"`. Значит, копия
`config/fbsd-3-sel/etc/rc.conf` в репозитории устарела: инвариант папки `config/`
— «как применено», и её надо обновить под фактическое состояние.

**Клонированный `bastille0` принадлежит группе `lo`, а не `lo0`.** Значит,
`set skip on lo0` из текущего ruleset не покрывает трафик jail'ов, и в День 3
нужно менять на `set skip on lo`. В собственном блоке Bastille `set skip on lo`
уже есть — то есть наша правка совпадает с тем, что Bastille считает правильным.

## День 3 — Первый jail с VNET

*(заполняется)*

## День 4 — Bastillefile

*(заполняется)*

## День 5 — Переносимость arm64 ↔ amd64

*(заполняется)*

## День 6 — Изоляция, снапшоты и клоны

*(заполняется)*

## День 7 — bhyve с Debian

*(заполняется)*

## День 8 — Бенчмарк jail vs bhyve

*(заполняется)*

## День 9 — Финальный шаблон и автоматизация

*(заполняется)*
