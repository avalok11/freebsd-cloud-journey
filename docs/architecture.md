# Архитектура FreeBSD Private Cloud

Целевая архитектура продуктового кластера. Диаграмма в формате Mermaid — GitHub рисует её автоматически.

## Целевая топология (v1, по состоянию на Фазу 0)

```mermaid
graph TB
    subgraph Laptop[Mac M4 — рабочая станция админа]
        Console[Ansible-консоль<br/>ssh-keys + playbook'и]
        GH[freebsd-cloud-journey<br/>GitHub, публичный]
    end

    subgraph Selectel["Selectel VPS (≤10 000 ₽/мес)"]
        F1[fbsd-1-sel<br/>gateway<br/>PF + CARP master]
        F2[fbsd-2-sel<br/>app node<br/>Bastille jails]
        F3[fbsd-3-sel<br/>storage<br/>ZFS + replication]
        L1[deb-1-sel<br/>linux<br/>k3s + monitoring]
        Gitea[fbsd-4-sel<br/>gitea<br/>приватный git]
    end

    subgraph LocalLab[UTM локально на M4]
        FARM[fbsd-arm<br/>FreeBSD 15.1 arm64<br/>эксперименты]
        DARM[deb-arm<br/>Debian 12 arm64<br/>сравнение]
    end

    Console -->|ssh по ключу + TOTP| F1
    Console -->|ssh| F2
    Console -->|ssh| F3
    Console -->|ssh| L1
    Console -->|ssh| Gitea
    Console -->|git push| GH
    Console -->|git push| Gitea
    Gitea -.хранит.-> InfraCfg[infra-configs<br/>приватный репо]
    F1 <-->|CARP VIP| F2
    F2 -->|ZFS send/receive| F3
    F1 -->|PF NAT| L1
    F2 -.эксперименты.-> FARM
    L1 -.сравнение.-> DARM
```

## Принципы

1. **Ноутбук — не часть кластера.** Это рабочая станция админа, через которую идёт управление.
2. **Динамический домашний IP — не проблема.** Все подключения инициируются от ноутбука к Selectel, обратного трафика нет.
3. **Два репозитория:**
   - `freebsd-cloud-journey` (GitHub, публичный) — кейс, отчёты, схемы, портфолио.
   - `infra-configs` (Gitea, приватный) — Ansible, конфиги, secrets. **Никаких реальных IP, доменов, сертификатов в публичном репо.**
4. **Локально — для экспериментов.** На M4 в UTM поднимаем FreeBSD arm64 для отладки, можно ломать без боли.
5. **Удалённо — production-like.** В Selectel FreeBSD amd64, как у реального заказчика.

## Сеть (что планируется)

| Сеть | Назначение | CIDR (пример) |
|---|---|---|
| Публичная | Доступ из интернета, ssh, http | Выдаётся Selectel |
| Приватная (CARP) | Связь между FreeBSD-нодами | 10.10.0.0/24 |
| Storage | ZFS-репликация | 10.10.1.0/24 |
| Bastille VNET | Сеть для jail-ов | 10.10.10.0/24 |

Конкретные адреса выбираем в Фазе 3.

## Хранилище (ZFS-пулы)

| Нода | Пул | Назначение | RAID |
|---|---|---|---|
| fbsd-1-sel | zroot | Система | stripe (для теста), mirror в проде |
| fbsd-2-sel | zroot + tank | Система + данные jail-ов | mirror |
| fbsd-3-sel | tank | Бэкапы, реплики | mirror |

## Сервисы в Bastille-jails

| Jail | Сервис | Порт |
|---|---|---|
| nginx | Reverse proxy | 80, 443 |
| app | PHP-FPM / приложение | 9000 (internal) |
| db | PostgreSQL | 5432 (internal) |
| mail | Postfix + Dovecot | 25, 143, 587 |
| monitor | Prometheus + Grafana | 9090, 3000 |

Точные конфигурации — в Фазе 2.

## История изменений

- **2026-08-06 (v1)** — стартовая схема, добавлены два репозитория (GitHub + Gitea), гибридный стенд.
- ...будут уточнения по мере прохождения фаз.
