# День 3 Фазы 2 — runbook: первый jail с VNET

**Цель:** поднять на `fbsd-3-sel` (172.16.0.5) первый jail с VNET, с выходом в
интернет через NAT хоста и пробросом 80/tcp снаружи.

**Схема сети** (разбор — в [`03-vnet-and-network.md`](./03-vnet-and-network.md)):

| Что | Значение |
|---|---|
| Подсеть jail'ов | `10.10.10.0/24` |
| Мост | `bridge0`, **без** физического интерфейса внутри |
| Шлюз jail'ов | `10.10.10.1/24` — адрес на самом мосте |
| IP jail'а `web` | `10.10.10.10/24` |
| Выход в интернет | `nat on vtnet0 from 10.10.10.0/24 to any -> (vtnet0:0)` → `172.16.0.5` |
| Форвардинг | `net.inet.ip.forwarding=1` (`gateway_enable=YES`) |

> **Порядок шагов важен.** Мост поднимаем **до** применения PF: ruleset v3.1
> ссылается на `bridge0`, и PF не грузит ruleset с несуществующим интерфейсом.

---

## Шаг 0. Снять фактическое состояние (только чтение)

Ничего не меняем — просто смотрим, что на ноде уже есть. Отдельно важно
посмотреть **загруженные** правила PF: `pfctl -sr` показывает то, что реально
работает сейчас, а не то, что лежит в файле.

```sh
sudo pfctl -si                       # статус: загружен ли ruleset, счётчики
sudo pfctl -sr                       # фильтрующие правила, которые работают
sudo pfctl -sn                       # NAT-правила
sudo pfctl -s Tables                 # таблицы (<sshguard>, <jails>)
sudo cat /etc/pf.conf                # файл ruleset на ноде
bastille version
bastille list releases
bastille list
cat /usr/local/etc/bastille/bastille.conf
cat /etc/rc.conf
cat /etc/sysctl.conf
ifconfig -a
netstat -rn
```

**Что смотрим:**

1. Где в выводе `pfctl -sr` стоит правило разрешения SSH относительно
   `block in all`. Правило SSH должно быть **НИЖЕ** `block in all`: в PF
   последнее совпавшее правило выигрывает, и catch-all, стоящий ниже,
   перебил бы разрешение (SSH-правило стало бы мёртвым).
   Если SSH-правило оказалось **выше** `block in all` — оно мёртвое, и SSH
   держится не на PF (например, ruleset не перезагружался или PF вовсе не
   включён). Это надо понять до того, как мы начнём менять PF.
2. `pfctl -si` — в поле `Loaded Rulesets` должно быть `pf` (и, возможно,
  anchors). Если ruleset не загружен вовсе, `pfctl -sr` будет пустым.
3. В `rc.conf` — `cloned_interfaces` (после `setup loopback` там есть `lo1`).

Пришлите вывод — дальше идём по фактическому состоянию.

---

## Шаг 1. Подготовить VNET

```sh
sudo bastille setup vnet
```

Что делает (по исходникам 1.4.4, `configure_vnet`): кладёт `jib` из
`/usr/share/examples/jails/jib` в `/usr/local/bin/jib` и создаёт в
`/etc/devfs.rules` ruleset `bastille_vnet=13`. **PF не трогает** — это единственный
безопасный `setup`.

Проверка:

```sh
ls -l /usr/local/bin/jib
cat /etc/devfs.rules
```

---

## Шаг 2. Мост, шлюз jail'ов и форвардинг

```sh
# persistent: мост и его адрес
sudo sysrc cloned_interfaces+=bridge0
sudo sysrc ifconfig_bridge0="inet 10.10.10.1/24 up"

# форвардинг: хост маршрутизирует трафик jail'ов
sudo sysrc gateway_enable=YES

# применить в текущей сессии
sudo ifconfig bridge0 create
sudo ifconfig bridge0 inet 10.10.10.1/24 up
sudo sysctl net.inet.ip.forwarding=1
```

Проверка:

```sh
ifconfig bridge0                  # адрес 10.10.10.1, up
sysctl net.inet.ip.forwarding     # 1
netstat -rn | head                # 10.10.10.0/24 на bridge0
```

> **В мост не добавляем `vtnet0`.** `bastille setup bridge vtnet0` это делает, но
> так делать не надо: на FreeBSD 15 адрес интерфейсу-члену моста назначать нельзя
> (Handbook, «VNET Jails» — адрес должен быть на самом мосте), а у `vtnet0`
> единственный адрес ноды. Плюс `pfil_bridge=0` отключил бы инспекцию PF.

---

## Шаг 3. Применить PF (ruleset v3.1)

Файл: [`pf-ruleset-jails.conf`](./pf-ruleset-jails.conf).

**Подстраховка:** откройте **вторую** SSH-сессию и не закрывайте её, пока не
убедитесь, что SSH работает. Если правила вдруг обрубят доступ, нода
восстанавливается из второй сессии или с консоли провайдера.

```sh
# 1. бэкап текущего ruleset
sudo cp /etc/pf.conf /etc/pf.conf.bak-$(date +%Y%m%d-%H%M)

# 2. положить новый (путь — свой, файл нужно заранее скопировать на ноду)
sudo cp ~/pf-ruleset-jails.conf /etc/pf.conf

# 3. проверить синтаксис — ruleset при этом НЕ грузится
sudo pfctl -nf /etc/pf.conf

# 4. применить
sudo pfctl -f /etc/pf.conf

# 5. убедиться, что правила загрузились и SSH-правило живое
sudo pfctl -sr
```

Ожидаемый вывод `pfctl -sr` — порядок **сверху вниз**:

```
block drop in quick on vtnet0 from <sshguard> to any
block drop in quick on ! vtnet0 inet from 172.16.0.0/16 to any
block drop in quick inet from 172.16.0.5 to any
block in all
pass in on bridge0 from 10.10.10.0/24 to 10.10.10.1 keep state
pass in on bridge0 from 10.10.10.0/24 to ! 10.10.10.0/24 keep state
pass in inet proto tcp to port { ssh } keep state
pass in on vtnet0 proto tcp from any to 10.10.10.10 port 80 keep state
pass proto icmp all
pass out all keep state
anchor "bastille/*"
```

**Проверьте именно порядок, а не только наличие строк.** В PF последнее
совпавшее правило выигрывает («For `block` and `pass`, the last matching rule
decides what action is taken», `pf.conf(5)`), поэтому `block in all` обязан
стоять **выше** всех `pass in`. Если поменять их местами — catch-all совпадёт
позже и перебьёт разрешение: SSH перестанет пускать, а ICMP — тоже.

Правило `block drop in quick on ! vtnet0 ...` в выводе `pfctl -sr` может
отличаться по написанию от написанного в файле: `antispoof quick for $ext_if`
раскрывается в два правила, и `quick` переносится в раскрытие
(`parse.y`, `p_antispoof`: `r.quick = $2.quick`).

Если `pfctl -nf` ругается на порядок секций — файл не применён, ничего не сломалось:
PF требует `tables → options → normalization → translation → filtering`.

### Откат

```sh
sudo pfctl -f /etc/pf.conf.bak-<дата>     # вернуть прежний ruleset
sudo pfctl -f /dev/null                    # аварийный вариант: пустой ruleset
```

> **Откат без консоли.** У `fbsd-3-sel` нет доступа к консоли провайдера, поэтому
> «откат по ssh» может не получиться: если правила оборвали доступ, второй
> SSH-клиент тоже не подключится. Надёжный способ — автооткат по таймеру,
> который снимется сам, как только вы убедитесь, что доступ жив:

```sh
# 1. перед применением — отложить автооткат на 3 минуты
sudo cp /etc/pf.conf /etc/pf.conf.bak-$(date +%Y%m%d-%H%M)
BAK=/etc/pf.conf.bak-$(date +%Y%m%d-%H%M)
sudo sh -c "(sleep 180; pfctl -f $BAK) >/dev/null 2>&1 &"

# 2. применить новый ruleset
sudo pfctl -nf /etc/pf.conf && sudo pfctl -f /etc/pf.conf

# 3. открыть НОВУЮ ssh-сессию и убедиться, что вход проходит

# 4. если всё хорошо — отменить автооткат
sudo pkill -f "sleep 180; pfctl -f $BAK"
```

Если нода всё-таки отвалилась — автооткат вернёт прежний ruleset через три
минуты, и нода поднимется сама.

---

## Шаг 4. Создать jail

```sh
sudo bastille create -B web 15.1-RELEASE 10.10.10.10/24 bridge0 --gateway 10.10.10.1
```

Что происходит (по исходникам 1.4.4):

- `-B` — режим «мост»: `INTERFACE` должен быть мостом. `jib` при этом **не**
  используется, хост-сторона `epair` добавляется в наш мост напрямую:
  `ifconfig bridge0 addm e0a_web`.
- Хост-сторона пары — `e0a_web`, jail-сторона — `e0b_web`, внутри jail'а
  интерфейс называется `vnet0`.
- `--gateway 10.10.10.1` — шлюз jail'а. Без этого флага Bastille взял бы шлюз
  маршрута по умолчанию хоста (`172.16.0.1`) — это не наш шлюз.
- Шаблон `default/vnet` пишет в `/etc/rc.conf` jail'а
  `ifconfig_vnet0="inet 10.10.10.10/24"` и `defaultrouter="10.10.10.1"`.

Проверка:

```sh
sudo bastille list
ifconfig e0a_web                  # хост-сторона пары, member bridge0
sudo bastille cmd web ifconfig    # внутри: vnet0 с 10.10.10.10/24
sudo bastille cmd web netstat -rn # defaultrouter 10.10.10.1
```

---

## Шаг 5. nginx внутри jail

```sh
sudo bastille pkg web install nginx
sudo bastille cmd web sysrc nginx_enable=YES
sudo bastille cmd web service nginx start
```

Проверка:

```sh
sudo bastille cmd web service nginx status
sudo bastille cmd web sockstat -4 -l | grep 80
```

> `bastille create web nginx --release 15.1-RELEASE` из плана — **нерабочий
> синтаксис**: в Bastille 1.4.4 у `create` нет флага `--release`, а сервисы
> описываются Bastillefile'ом (День 4). Пакеты ставятся отдельно, как выше.

---

## Шаг 6. Проверки

### Изнутри jail

```sh
sudo bastille cmd web ping -c2 10.10.10.1     # шлюз — должен отвечать
sudo bastille cmd web ping -c2 8.8.8.8        # интернет — через NAT хоста
sudo bastille cmd web cat /etc/resolv.conf    # DNS: 8.8.8.8 / 77.88.8.8
sudo bastille cmd web cat /etc/rc.conf | grep -E 'ifconfig_vnet0|defaultrouter'
```

### С хоста

```sh
ping -c2 10.10.10.10
curl -s http://10.10.10.10/ | head -5         # nginx отвечает
sudo pfctl -t jails -T show                  # пусто — так и должно быть (VNET)
sudo pfctl -sn | grep -A1 '^nat'             # правило NAT на месте
sudo pfctl -ss | head                        # соединения jail'а через state
```

### Снаружи (через rdr)

```sh
curl -s http://<публичный-IP-fbsd-3-sel>/ | head -5
```

Если снаружи 502/таймаут, а с хоста `curl http://10.10.10.10/` работает — значит
не сработал `rdr`. Проверить: `sudo pfctl -sr | grep rdr` (в выводе `pfctl -sr`
rdr-правила не видны — это нормально, они в nat-секции; смотреть надо
`sudo pfctl -sn`) и `sudo tcpdump -ni vtnet0 'tcp port 80'`.

---

## Что должно остаться в репозитории

| Файл | Изменение |
|---|---|
| `config/fbsd-3-sel/etc/pf.conf` | применить v3 — «как применено» |
| `config/fbsd-3-sel/etc/rc.conf` | добавить `cloned_interfaces+=bridge0`, `ifconfig_bridge0=...`, `gateway_enable=YES`, `bastille_enable=YES` |
| `config/fbsd-3-sel/etc/bastille.conf` | новый файл — выгрузка с ноды |
| `docs/phase-2/phase-2-report.md` | раздел «День 3» с выводом проверок |
