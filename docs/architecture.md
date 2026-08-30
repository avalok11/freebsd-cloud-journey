# Архитектура FreeBSD Private Cloud

Целевая архитектура продуктового кластера. Диаграмма в формате Mermaid — GitHub рисует её автоматически.

## Текущая фактическая топология (после Фазы 0.1)

```mermaid
graph TB
    subgraph Laptop[Mac M4 — рабочая станция админа]
        Console[Ansible-консоль<br/>ssh-keys + сертификаты<br/>~/.ssh/freebsd_lab + zfs_repl]
        GH[freebsd-cloud-journey<br/>GitHub, публичный<br/>github.com/avalok11/...]
    end

    subgraph Selectel["Selectel VPS, регион Москва (≤10 000 ₽/мес)"]
        F1["<b>fbsd-1-sel</b><br/>FreeBSD 15.1 amd64<br/>публичный 178.72.xxx.xxx<br/>внутренний 172.16.0.2<br/>vtnet0<br/>sshguard + TOTP + CA ✓"]
        CA["<b>fbsd-ca-sel</b><br/>FreeBSD 15.1 amd64<br/>мини-CA<br/>только sshd<br/>User CA + Host CA ✓"]
        F2["<b>fbsd-2-sel</b><br/>FreeBSD 15.1 amd64<br/>только внутренний 172.16.0.4<br/>jump-host через F1<br/>ZFS-реплика ✓"]
        F3["fbsd-3-sel<br/>storage<br/>(планируется)"]
        L1["deb-1-sel<br/>linux<br/>(планируется)"]
        Gitea["fbsd-4-sel<br/>gitea<br/>(планируется)"]
    end

    subgraph LocalLab["UTM локально на M4"]
        FARM["<b>fbsd-arm</b><br/>FreeBSD 15.1 arm64<br/>192.168.64.2<br/>sshguard + TOTP ✓<br/>host-ключ подписан ✓"]
        DARM["<b>deb-arm</b><br/>Debian 13.6 arm64<br/>192.168.64.4<br/>сравнение"]
    end

    Console -->|ssh + TOTP<br/>+ сертификат CA| F1
    Console -->|ssh + сертификат| CA
    Console -->|ssh -J fbsd-1-sel<br/>+ сертификат| F2
    Console -->|ssh по ключу| FARM
    Console -->|ssh по ключу| DARM
    Console -->|git push| GH
    CA -.подписывает user-ключи.-> Console
    CA -.подписывает user-ключи<br/>zfs-repl TTL 52w.-> Console
    CA -.подписывает host-ключи.-> F1
    CA -.подписывает host-ключи.-> F2
    CA -.подписывает host-ключи.-> FARM
    F1 -.ZFS replication<br/>по 172.16.0.0/16.-> F2
    F1 -.будет CARP.-> F2
    F2 -.ZFS replication.-> F3
    Gitea -.хранит.-> InfraCfg[infra-configs<br/>приватный репо]
```

## Принципы

1. **Ноутбук — не часть кластера.** Это рабочая станция админа, через которую идёт управление.
2. **Динамический домашний IP — не проблема.** Все подключения инициируются от ноутбука к Selectel, обратного трафика нет.
3. **Два репозитория:**
   - `freebsd-cloud-journey` (GitHub, публичный) — кейс, отчёты, схемы, портфолио.
   - `infra-configs` (Gitea, приватный) — Ansible, конфиги, secrets. **Никаких реальных IP, доменов, сертификатов в публичном репо.**
4. **Локально — для экспериментов.** На M4 в UTM поднимаем FreeBSD arm64 для отладки, можно ломать без боли.
5. **Удалённо — production-like.** В Selectel FreeBSD amd64, как у реального заказчика.
6. **Межсервисный трафик — по приватной сети Selectel.** Репликация ZFS, сервисный SSH `zfs-repl`, будущий CARP/heartbeat — всё через `172.16.0.0/16`, не через интернет. Дешевле, быстрее, меньше поверхность атаки.

## Что развёрнуто на 2026-08-30

### Selectel

| Нода | Хостнейм | ОС | Внешний IP | Внутренний IP | Назначение | Статус |
|---|---|---|---|---|---|---|
| **fbsd-1-sel** | `fbsd-1-sel.lab.sel` | FreeBSD 15.1-RELEASE amd64 | `178.72.xxx.xxx` (замазан) | `172.16.0.2/16` (vtnet0) | Шлюз, тест-нода, jump-host | **активен**, sshguard + TOTP + CA-доверие |
| **fbsd-ca-sel** | `fbsd-ca-sel.lab.sel` | FreeBSD 15.1-RELEASE amd64 | (jump через F1) | `172.16.0.3/16` (vtnet0) | Мини-CA, только sshd | **активен**, User CA + Host CA, CRL |
| **fbsd-2-sel** | `fbsd-2-sel.lab.sel` | FreeBSD 15.1-RELEASE amd64 | **нет** (только приватный) | `172.16.0.4/16` (vtnet0) | ZFS-реплика, будущая CARP-пара | **активен**, sshguard + TOTP + CA-доверие, вход через `ssh -J fbsd-1-sel` |

### Локальный стенд (UTM на Mac M4)

| ВМ | Хостнейм | ОС | IP | Назначение | Статус |
|---|---|---|---|---|---|
| **fbsd-arm** | `fbsd-arm` | FreeBSD 15.1 arm64 | `192.168.64.2` | Эксперименты | **активен**, sshguard + TOTP, host-ключ подписан |
| **deb-arm** | `deb-arm` | Debian 13.6 arm64 | `192.168.64.4` | Сравнение с Linux | **активен**, ssh по ключу |

## Сеть

| Сеть | Назначение | CIDR |
|---|---|---|
| **Публичная** (Selectel) | Доступ из интернета, ssh, http | Выдаётся Selectel |
| **Приватная Selectel** | Связь между нодами внутри дата-центра | `172.16.0.0/16` (по умолчанию) |
| **Host-Only UTM** (локально) | Связь Mac M4 ↔ локальные ВМ | `192.168.64.0/24` |
| **CARP / внутренняя** (планируется) | Связь между FreeBSD-нодами для HA | `10.10.0.0/24` |
| **Storage** (планируется) | ZFS-репликация | `10.10.1.0/24` |
| **Bastille VNET** (планируется) | Сеть для jail-ов | `10.10.10.0/24` |

## Безопасность на FreeBSD-нодах (fbsd-1-sel, fbsd-ca-sel, fbsd-2-sel, fbsd-arm)

- ✅ SSH по ключу (ed25519, `~/.ssh/freebsd_lab` на Mac M4).
- ✅ TOTP через Yandex Key (`pam_google_authenticator`).
- ✅ `PasswordAuthentication no`, `PermitRootLogin no`.
- ✅ AuthenticationMethods: `publickey,keyboard-interactive:pam`.
- ✅ sshguard + PF (активирован, таблица `<sshguard>`, тест блокировки пройден).
- ✅ ntpd для синхронизации времени.
- ✅ NTP-сервер time.cloudflare.com.
- ✅ **SSH CA (Фаза 0.1 закрыта):** User CA + Host CA на `fbsd-ca-sel`. Host-ключи `fbsd-1-sel`, `fbsd-2-sel`, `fbsd-arm` подписаны (TTL 52w). Пользовательский ключ `freebsd_lab` подписан (TTL 8h, переподпись). CRL настроен вручную, проверен. **Автоматизация CRL — Фаза 4** (Ansible).
- ⏳ Баннер на `fbsd-2-sel` (День 1 Фазы 1, не доделан).
- ⏳ User CA → TrustedUserCAKeys на `fbsd-2-sel` (День 1 Фазы 1, не доделан — без этого вход под `avalok11` по сертификату не работает, только host-верификация).

## Что нужно донастроить (задачи)

- [x] Активировать sshguard + PF на fbsd-1-sel (как на fbsd-arm).
- [x] Создать `fbsd-2-sel` (для реплики в Фазе 1 и HA-тестов в Фазе 3).
- [ ] Доделать User CA-доверие на fbsd-2-sel: `TrustedUserCAKeys /etc/ssh/ca/user_ca.pub` в `sshd_config` + рестарт sshd.
- [ ] Баннер на fbsd-2-sel.
- [ ] Скопировать `host_ca.pub` на Mac M4 (уже должен быть с Фазы 0.1, но перепроверить после подписи fbsd-2-sel).

## Хранилище (ZFS-пулы) — в работе

| Нода | Пул | Назначение | RAID |
|---|---|---|---|
| fbsd-1-sel | zroot + tank | Система + данные для реплики | stripe на Selectel (1 диск); mirror в проде |
| fbsd-2-sel | zroot + tank | Система + приёмник реплики (`tank/repl`) | stripe на Selectel |
| fbsd-3-sel | tank | Бэкапы, offsite-реплики | mirror (планируется) |

## Сервисы в Bastille-jails (планируется)

| Jail | Сервис | Порт |
|---|---|---|
| nginx | Reverse proxy | 80, 443 |
| app | PHP-FPM / приложение | 9000 (internal) |
| db | PostgreSQL | 5432 (internal) |
| mail | Postfix + Dovecot | 25, 143, 587 |
| monitor | Prometheus + Grafana | 9090, 3000 |

Точные конфигурации — в Фазе 2.

## История изменений

- **2026-08-30 (v3, День 1 Фазы 1)** — поднят `fbsd-2-sel` в Selectel (FreeBSD 15.1 amd64, только приватный IP `172.16.0.4`, jump-host через `fbsd-1-sel`). Базовый харденинг + sshguard + TOTP + ntpd выполнены. Host-ключ подписан через `fbsd-ca-sel` (TTL 52w). Баннер и User CA-доверие (`TrustedUserCAKeys`) — в работе. Решение: `fbsd-2-sel` остаётся без публичного IP, межсервисный трафик идёт по `172.16.0.0/16`.
- **2026-08-28 (v2.3, Фаза 0.1 закрыта)** — User CA + Host CA на `fbsd-ca-sel`, подписаны host-ключи `fbsd-1-sel` и `fbsd-arm`, CRL настроен, TTL-тест пройден.
- **2026-08-11 (v2.1)** — на fbsd-1-sel активирован sshguard + PF, статус синхронизирован с fbsd-arm.
- **2026-08-11 (v2)** — развёрнут `fbsd-1-sel` в Selectel (FreeBSD 15.1, публичный IP, ssh + TOTP), `deb-arm` в UTM (Debian 13.6). Фактические IP зафиксированы.
- **2026-08-06 (v1)** — стартовая схема, добавлены два репозитория (GitHub + Gitea), гибридный стенд.
