# Сетевой стек FreeBSD vs Linux

**Время чтения:** ~6–8 минут
**Фаза:** 1 (FreeBSD актуальный: сеть, ZFS, базовый сервисный SSH)
**Цель:** понимать отличия сетевого стека FreeBSD от Linux, корректно настраивать сеть без NetworkManager.

---

## 1. Главное отличие в философии

**Linux:** сетевая подсистема управляется **демонами верхнего уровня** (NetworkManager, systemd-networkd, Netplan). Они читают конфиги, дёргают низкоуровневые утилиты (`ip`, `iw`), общаются с ядром через netlink.

**FreeBSD:** всё управляется **через `rc.conf`** — единый конфиг. Сеть поднимается в `/etc/rc.d/netif` и `/etc/rc.d/routing`, без отдельного демона. Конфиг декларативный: написал — применилось.

## 2. Конфигурация сети

### FreeBSD — через `/etc/rc.conf`

```
# Имя хоста
hostname="fbsd-1-sel.lab.sel"

# IP-адреса и маска
ifconfig_vtnet0="inet 172.16.0.2 netmask 255.255.0.0"

# Шлюз по умолчанию
defaultrouter="172.16.0.1"

# Включение IPv6 (опционально)
ipv6_network_interfaces="vtnet0"

# Аггрегация (lagg)
ifconfig_vtnet0="up"
ifconfig_vtnet1="up"
cloned_interfaces="lagg0"
ifconfig_lagg0="laggproto lacp laggport vtnet0 laggport vtnet1 10.0.0.1/24"
```

**Особенности:**
- Имя интерфейса в формате `ifconfig_<имя>`.
- Префикс `cloned_interfaces` для виртуальных интерфейсов (lagg, vlan, bridge).
- `defaultrouter` — один шлюз. Для нескольких — статические маршруты в `/etc/rc.conf` через `static_routes` + `route_<name>`.
- После правки — `service netif restart && service routing restart`.

### Linux (Debian/Ubuntu) — несколько способов

**Способ 1: `/etc/network/interfaces` (классика, по умолчанию в Debian):**
```
auto enp0s3
iface enp0s3 inet static
    address 192.168.1.10
    netmask 255.255.255.0
    gateway 192.168.1.1
```

**Способ 2: Netplan (Ubuntu 18+, Debian 11+):**
```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    enp0s3:
      addresses: [192.168.1.10/24]
      gateway4: 192.168.1.1
```

**Способ 3: NetworkManager (CentOS, Fedora, десктопный Ubuntu):**
```bash
nmcli con add con-name static-eth0 ifname enp0s3 type ethernet \
    ip4 192.168.1.10/24 gw4 192.168.1.1
nmcli con up static-eth0
```

**Проблема Linux:** три конфликтующих способа. В дистрибутиве — обычно один, но при миграции между дистрибутивами или смене подхода (NetworkManager → Netplan) — головная боль.

## 3. Утилиты: ifconfig vs ip

### `ifconfig` — есть в обеих ОС, но по-разному

**FreeBSD (нативный):**
```bash
# Показать все интерфейсы
ifconfig
# vtnet0: flags=1008843<UP,BROADCAST,RUNNING,SIMPLEX,MULTICAST,LOWER_UP> metric 0 mtu 1500
#         inet 172.16.0.2 netmask 0xffff0000 broadcast 172.16.255.255
#         ether fa:16:3e:31:fe:bd
#         status: active

# Поднять интерфейс
ifconfig vtnet0 up

# Назначить IP
ifconfig vtnet0 inet 10.0.0.1/24

# Добавить alias
ifconfig vtnet0 alias 10.0.0.2/24
```

**Linux (deprecated, но работает):**
```bash
ifconfig eth0 192.168.1.10/24 up
```

**На FreeBSD `ifconfig` — основной инструмент.** На Linux он deprecated в пользу `ip`, но в дистрибутивах с NetworkManager или systemd-networkd `ifconfig` может вообще не работать корректно.

### `ip` — рекомендуемый в Linux, есть в пакете на FreeBSD

**Linux (нативный):**
```bash
# Показать адреса
ip addr show
ip a

# Маршруты
ip route show
ip r

# Поднять интерфейс
ip link set eth0 up

# Назначить IP
ip addr add 192.168.1.10/24 dev eth0
ip route add default via 192.168.1.1
```

**FreeBSD (через пакет `iproute2`):**
```bash
pkg install iproute2
ip addr show
ip route show
```

На FreeBSD `ip` работает, но `ifconfig` — основной. Синтаксис немного отличается.

## 4. Утилиты: netstat vs ss

### `netstat` — есть в обеих ОС, классика

**FreeBSD:**
```bash
# Открытые порты
netstat -an
# Active Internet connections (including servers)
# Proto Recv-Q Send-Q Local Address     Foreign Address    State
# tcp4       0      0 *.22              *.*                LISTEN
# tcp4       0      0 172.16.0.2.22     195.x.x.x.51234    ESTABLISHED

# Только слушающие
netstat -ln

# С процессом
netstat -lnp
# (на FreeBSD нужны права root)

# Статистика по интерфейсам
netstat -I vtnet0
```

**Linux (deprecated, но работает):**
```bash
netstat -tlnp
# -t tcp, -l listening, -n numeric, -p process
```

### `ss` — рекомендуемый в Linux, нет на FreeBSD

**Linux:**
```bash
# Слушающие TCP-порты с процессом
ss -tlnp

# Установленные соединения
ss -tnp

# Статистика
ss -s
```

**На FreeBSD `ss` нет.** Используют `netstat` или `sockstat` (BSD-специфичный, показывает сокеты по процессам):
```bash
sockstat -l
# USER COMMAND    PID   FD PROTO  LOCAL ADDRESS         FOREIGN ADDRESS
# root sshd       1234  4  tcp4   *:22                  *:*
```

## 5. Маршрутизация

**FreeBSD:**
```bash
# Показать таблицу маршрутизации
netstat -rn
route -n show
# Destination    Gateway         Flags    Netif
# default        172.16.0.1      UGS      vtnet0
# 127.0.0.1      link#1          UH       lo0
# 172.16.0.0/16  link#1          U        vtnet0

# Добавить статический маршрут
route add -net 10.0.0.0/24 172.16.0.1
# Или в /etc/rc.conf:
# static_routes="net1"
# route_net1="-net 10.0.0.0/24 172.16.0.1"
```

**Linux:**
```bash
ip route show
ip route add 10.0.0.0/24 via 192.168.1.1
# Или в /etc/network/interfaces:
# up ip route add 10.0.0.0/24 via 192.168.1.1
```

## 6. DNS

**FreeBSD — `/etc/resolv.conf`** (такой же, как в Linux):
```
nameserver 1.1.1.1
nameserver 8.8.8.8
search lab.local
```

**Linux — то же самое**, плюс systemd-resolved в Ubuntu 18+:
```bash
# Через systemd-resolved
resolvectl status
```

**Особенность FreeBSD:** `resolvconf` не используется по умолчанию (только если стоит пакет). Файл `/etc/resolv.conf` пишется напрямую или DHCP-клиентом `dhclient`.

## 7. Файрвол (обзор, детали в следующем брифе)

| ОС | Инструмент | Конфиг |
|---|---|---|
| FreeBSD | PF (Packet Filter) | `/etc/pf.conf` |
| FreeBSD (legacy) | ipfw | `/etc/ipfw.rules` |
| Linux | iptables / nftables | `/etc/iptables/rules.v4` или `/etc/nftables.conf` |
| Linux (CentOS/RHEL) | firewalld | `firewall-cmd` |

## 8. Управление сервисами

**FreeBSD — `service` и `sysrc`:**
```bash
# Включить
sysrc sshd_enable="YES"

# Запустить
service sshd start

# Перезапустить
service sshd restart

# Статус
service sshd status
```

**Linux — `systemctl` (systemd):**
```bash
# Включить
systemctl enable sshd

# Запустить
systemctl start sshd

# Статус
systemctl status sshd
```

**Разница философии:** `sysrc` редактирует `/etc/rc.conf` (декларативно), `service` — runtime. В Linux `systemctl enable` создаёт symlink в `/etc/systemd/system/`.

## 9. Что выбрать для нашего стенда

**На FreeBSD-нодах:**
- `ifconfig`, `netstat`, `route` — нативные, в базе.
- `service` + `sysrc` — для управления сервисами.
- PF — для файрвола.
- `/etc/rc.conf` — единый конфиг.

**На Linux-нодах (для сравнения):**
- `ip`, `ss` — современные утилиты.
- `systemctl` — для сервисов.
- `nftables` — файрвол (учим в Фазе 1+).
- Netplan или `/etc/network/interfaces` — для конфигурации.

## 10. Сводная таблица отличий

| Аспект | FreeBSD | Linux |
|---|---|---|
| Конфиг сети | `/etc/rc.conf` (один файл) | Разный: `/etc/network/interfaces`, Netplan, NetworkManager |
| Утилита настройки | `ifconfig` (нативно) | `ip` (рекомендуется) |
| Просмотр портов | `netstat`, `sockstat` | `ss`, `netstat` (deprecated) |
| Маршруты | `route`, `netstat -rn` | `ip route` |
| DNS | `/etc/resolv.conf` (напрямую) | `/etc/resolv.conf` или systemd-resolved |
| Сервисы | `service`, `sysrc` | `systemctl` |
| Файрвол | PF, ipfw (legacy) | iptables, nftables, firewalld |
| Сетевой менеджер | Нет (через rc.conf) | NetworkManager / systemd-networkd / Netplan |

## Что почитать

- FreeBSD Handbook, Chapter 30 (Network Communication): https://docs.freebsd.org/en/books/handbook/network-communications/
- `man ifconfig`, `man rc.conf`, `man pf` на FreeBSD.
- `man ip`, `man ss` на Linux.
- «TCP/IP Illustrated» (Stevens) — фундаментальная книга по сетевому стеку вообще.
