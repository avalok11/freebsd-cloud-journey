# PF (Packet Filter) vs iptables/nftables

**Время чтения:** ~7–9 минут
**Фаза:** 1 (FreeBSD актуальный: сеть, ZFS, базовый сервисный SSH)
**Цель:** понимать архитектуру PF, уметь читать и писать правила, сравнивать с Linux-аналогами.

---

## 1. История PF

**Packet Filter (PF)** — это файрвол, изначально разработанный для **OpenBSD** в 2001 году автором **Daniel Hartmeier**. До этого в OpenBSD использовался IPFilter, но он был проприетарным (имел закрытые расширения), и OpenBSD-сообщество решило написать свой.

**2001:** PF появился в OpenBSD 3.0.

**2002:** PF перенесён во **FreeBSD 4.7** через проект KAME (японский проект по сетевым технологиям). С тех пор PF живёт в обеих ОС.

**2003:** PF стал **дефолтным файрволом FreeBSD** (на смену IPFilter, у которого были лицензионные проблемы).

**Сейчас:** PF — стандарт для FreeBSD, OpenBSD, NetBSD (с вариациями), macOS (через `pfctl`), DragonFlyBSD.

## 2. Почему PF дефолт во FreeBSD

**Причины:**

1. **Открытая лицензия BSD** — нет юридических проблем, в отличие от IPFilter.
2. **Простота синтаксиса** — правила читаются естественно, не как у iptables.
3. **Stateful по умолчанию** — `keep state` подразумевается, не нужно писать явно.
4. **Интеграция с ALTQ** (в 14.x) и netgraph — шейпинг трафика.
5. **Anchors** — иерархия правил, удобно для многосервисных систем.
6. **Таблицы** — динамические списки IP, интеграция с sshguard/spamd.

**ipfw** — старейший файрвол FreeBSD (с FreeBSD 2.x), до сих пор жив, но **legacy**. Используется в основном для rate-limiting и сложной логики в стиле rule-sets с номерами.

## 3. Сравнение синтаксиса

### Простое правило: разрешить SSH из мира

**FreeBSD (PF):**
```
# В /etc/pf.conf
ext_if = "vtnet0"

# Базовый набор
set skip on lo
block in all
pass out all keep state

# SSH
pass in inet proto tcp to port 22
```

**Linux (iptables, legacy):**
```bash
# iptables требует явного stateful
iptables -A INPUT -i eth0 -p tcp --dport 22 -m state --state NEW,ESTABLISHED -j ACCEPT
iptables -A OUTPUT -o eth0 -m state --state ESTABLISHED -j ACCEPT
```

**Linux (nftables, modern):**
```nft
table inet filter {
    chain input {
        type filter hook input priority 0; policy drop;
        iif "lo" accept
        tcp dport 22 accept
        ct state established,related accept
    }
}
```

### Сравнение по сложности

| Задача | PF | iptables | nftables |
|---|---|---|---|
| Разрешить SSH | 1 строка | 2 строки | 3–4 строки |
| NAT | `nat pass on $ext_if from $int_net to any -> ($ext_if)` | 2 строки + модули | `snat to` / `dnat to` |
| Блокировка по списку IP | `table <badguys> persist` + `block from <badguys>` | `-m set --match-set badguys src -j DROP` + ipset | `set badguys type ipv4_addr; drop from badguys` |
| Шейпинг | ALTQ/queues | tc (отдельная утилита) | tc + qdisc |
| Логирование | `log (all)` | `-j LOG` | `log prefix "..."` |

## 4. Структура правил PF

### Базовый набор `/etc/pf.conf`

```
# === Переменные ===
ext_if = "vtnet0"        # внешний интерфейс
int_if = "vtnet1"        # внутренний интерфейс
tcp_services = "{ ssh, http, https }"

# === Таблицы ===
table <sshguard> persist file "/var/db/sshguard/blacklist.pf"
table <blocked> persist

# === Нормализация ===
scrub in on $ext_if all fragment reassemble

# === Loopback ===
set skip on lo0

# === Перенаправления (rdr) ===
# rdr pass on $ext_if proto tcp to port 80 -> 192.168.1.10 port 80

# === NAT ===
# nat on $ext_if from 192.168.1.0/24 to any -> ($ext_if)

# === Блокировки ===
block in quick from <sshguard>
block in quick from <blocked>

# === Базовые правила ===
block in all
pass out all keep state

# === Разрешённые сервисы ===
pass in inet proto tcp to port $tcp_services
```

### Порядок обработки

PF обрабатывает правила **сверху вниз**, **последнее совпавшее выигрывает** (last match wins). Исключение — `quick` (при совпадении дальше не идёт).

```
pass in proto tcp to port 22        # совпало
pass in proto tcp to port 80        # совпало
block in all                        # совпало — правило, последнее совпадение
# Итог: BLOCK (последнее выигрывает)
```

Чтобы изменить логику, используют `quick`:
```
block in all
pass in quick proto tcp to port 22   # если совпало — СТОП, дальше не идёт
pass in proto tcp to port 80
# Итог: pass для :22, pass для :80, block для остального
```

## 5. Таблицы — динамические списки

PF умеет работать с таблицами IP, которые можно наполнять динамически:

```bash
# Добавить IP
pfctl -t blocked -T add 1.2.3.4

# Удалить
pfctl -t blocked -T delete 1.2.3.4

# Показать
pfctl -t blocked -T show

# Очистить
pfctl -t blocked -T flush
```

В конфиге:
```
table <blocked> persist
block in quick from <blocked>
```

**sshguard** использует именно таблицы — пишет IP брутфорсеров в таблицу, PF их блокирует.

## 6. Anchors — иерархия правил

Anchors позволяют загружать правила из отдельных файлов, **динамически**:

```
# Главный файл
anchor "ssh" in on $ext_if proto tcp to port 22
```

**Файл `/etc/pf.anchor.ssh`:**
```
# Правила для SSH — применяются только если трафик идёт на :22
block in quick from <sshguard>
pass in
```

**Применение без перезагрузки всего PF:**
```bash
pfctl -a ssh -f /etc/pf.anchor.ssh
```

Это позволяет загружать/выгружать наборы правил **без перезапуска основного файрвола**. Удобно для динамической конфигурации (например, скрипт добавляет правила для нового jail-а).

## 7. NAT и rdr (port forwarding)

### Source NAT (для выхода в интернет из приватной сети)

```
nat on $ext_if from 192.168.1.0/24 to any -> ($ext_if)
```

### Destination NAT (port forwarding)

```
# Проброс 80-го порта с внешнего IP на внутренний сервер
rdr pass on $ext_if proto tcp to port 80 -> 192.168.1.10 port 80
```

### Hairpin NAT (доступ к своему внешнему IP изнутри)

```
nat on $ext_if from 192.168.1.0/24 to $ext_if -> ($ext_if)
```

## 8. Логирование

```
# Логировать всё, что блокируется
block in log all

# Логировать конкретное правило
pass in log proto tcp to port 22
```

**Просмотр логов:**
```bash
# Через tcpdump
tcpdump -n -e -ttt -r /var/log/pflog

# Через pflog0
ifconfig pflog0
tcpdump -i pflog0
```

## 9. Сравнение с iptables и nftables

### iptables (legacy Linux)

**Структура:** таблицы → цепочки → правила.

```bash
# Очистить все цепочки
iptables -F

# Политика по умолчанию
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# Разрешить loopback
iptables -A INPUT -i lo -j ACCEPT

# Разрешить established
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Разрешить SSH
iptables -A INPUT -p tcp --dport 22 -m state --state NEW -j ACCEPT

# Сохранить
service iptables save
```

**Минусы iptables:**
- Каждое правило требует явного `-m state`.
- Списки IP — через ipset, отдельный инструмент.
- Шейпинг — через tc, отдельный синтаксис.
- Сложно читать при >50 правил.
- Дублирование: в iptables каждое правило на протокол, порт, состояние.

### nftables (modern Linux, замена iptables)

**Структура:** таблицы → цепочки → правила (но более чистый синтаксис).

```nft
table inet filter {
    chain input {
        type filter hook input priority 0; policy drop;
        iif "lo" accept
        ct state established,related accept
        tcp dport { 22, 80, 443 } accept
    }
    
    chain forward {
        type filter hook forward priority 0; policy drop;
    }
    
    chain output {
        type filter hook output priority 0; policy accept;
    }
}
```

**Плюсы nftables:**
- Компактнее iptables.
- Sets (множества) нативно.
- Единый синтаксис для IPv4, IPv6, ARP.
- Атомарные обновления (нет проблемы «полуприменённого правила»).

**Минусы nftables:**
- Всё ещё сложнее PF.
- Документация хуже.
- Нет аналога anchors.

## 10. Когда что выбрать

**PF:**
- FreeBSD (нативно, обязательно).
- macOS (через pfctl, для разработчиков).
- OpenBSD (нативно).
- pfSense / OPNsense (коммерческие продукты на FreeBSD).

**iptables:**
- Legacy Linux (RHEL 7, CentOS 7).
- Где нужен полный контроль над conntrack.

**nftables:**
- Современный Linux (RHEL 8+, Debian 10+, Ubuntu 20+).
- Новые проекты на Linux.

## 11. Что важно для нашего проекта

**На FreeBSD-нодах:**
- PF — основной файрвол.
- `pfctl` для управления.
- `/etc/pf.conf` — главный конфиг.
- `table <sshguard>` — для интеграции с sshguard.
- `anchors` — для динамических правил (для jail-ов в Фазе 2).

**На Linux-нодах (для сравнения):**
- nftables — современный стандарт.
- Изучим в Фазе 5+ (мониторинг) или раньше, если понадобится.

## Что почитать

- FreeBSD Handbook, Chapter 29 (Firewalls): https://docs.freebsd.org/en/books/handbook/firewalls/
- `man pf.conf`, `man pfctl` на FreeBSD.
- «PF: The OpenBSD Packet Filter» (Jeremy C. Reed) — короткий буклет по PF.
- «Firewalls Don't Stop Dragons» (Carey Parker) — для общего понимания.
- nftables wiki: https://wiki.nftables.org/
