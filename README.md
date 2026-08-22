# FreeBSD Private Cloud — от рук к продукту

**Проект:** восстановление hands-on экспертизы FreeBSD и построение продуктового решения «Private Cloud для среднего бизнеса».

**Автор:** Алексей — ИТ-директор, 15 лет управления, hands-on практика с FreeBSD 4.x/Postfix/Apache в 2002–2011, перерыв 2011–2026, восстановление экспертизы в 2026. С 2011 по 2026 — приоритетно управленческая работа (ИТ-директор), при этом всегда в прямом подчинении команды инфраструктуры и DevOps, личное участие в архитектурных решениях и сложных инцидентах.

**Горизонт:** 4–6 месяцев, ~10 ч/неделю, параллельно с курсом «DevOps-инженер с нуля» на netology.ru.

**Финальная цель:** production-ready кластер FreeBSD с горизонтальным масштабированием, резервированием и восстановлением, плюс сравнительная теоретическая база с Linux-миром. Целевой сегмент — SMB с собственной инфраструктурой и болями по безопасности/надёжности/производительности.

---

## Что в этом репозитории

Публичный портфолио-проект. Внутри:

- [`roadmap.md`](./docs/roadmap.md) — детальный план обучения по 8 фазам, 22 недели, с теорией, практикой, тестированием и артефактами.
- [`architecture.md`](./docs/architecture.md) — целевая архитектура кластера (Mermaid-диаграмма).
- `docs/phase-N/` — папки по фазам. Внутри каждой:
  - **`NN-тема.md`** — короткие теоретические заметки (3–15 минут чтения) по темам данной фазы. Без воды, с привязкой к нашему стеку и сравнением с Linux.
  - **`README.md`** — отчёт по фазе: что сделано, что получилось, грабли, графики, выводы.

**Чего здесь НЕТ:** реальных конфигов инфраструктуры, IP-адресов, доменов, сертификатов. Всё это живёт в приватном репозитории `infra-configs` в Gitea внутри кластера.

## Стек

| Слой | Технология | Зачем |
|---|---|---|
| ОС | FreeBSD 14.3 / 15.1 (amd64, arm64) | Базовое знание, проверенная стабильность, ZFS из коробки |
| Изоляция | Bastille (jails) | Лёгкие контейнеры BSD, мгновенный snapshot/clone |
| Хранилище | ZFS | Снапшоты, репликация, шифрование |
| Сеть | PF, lagg (LACP), CARP | Файрвол, агрегация каналов, отказоустойчивость IP |
| Виртуализация | bhyve (только amd64) | Полноценные гости Linux/Windows |
| Балансировка | HAProxy | L7 балансировка с health checks |
| Автоматизация | Ansible | Декларативный IaC, push-модель |
| Мониторинг | Prometheus + Grafana + Loki + Alertmanager | Метрики, логи, алерты |
| Бэкапы | ZFS snapshot + Restic | Стратегия 3-2-1 |
| Self-hosted git | Gitea | Приватные репозитории с конфигами |
| SSH | OpenSSH + sshguard + pam_google_authenticator | Ключи + TOTP, без fail2ban |

## Сравнение с Linux-стеком (для заказчика)

| Задача | FreeBSD-вариант | Linux-аналог | Почему выбираем BSD |
|---|---|---|---|
| Изоляция сервисов | Bastille/jails | Docker / LXC | Мгновенный snapshot/clone на уровне ZFS, без overlayfs |
| Хранилище | ZFS | LVM+ext4, btrfs, ZFS-on-Linux | ZFS нативно, проверено 15+ лет |
| Файрвол | PF | iptables / nftables | Проще синтаксис, anchors для иерархии |
| Отказоустойчивость IP | CARP | VRRP / keepalived | Встроен в ОС, без демонов |
| Виртуализация | bhyve | KVM/QEMU | Проще управление через vm-bhyve |
| Лицензия | BSD | GPL | Можно форкнуть и закрыть код |

## Документация

### План и архитектура

- [`docs/roadmap.md`](./docs/roadmap.md) — полный план по фазам
- [`docs/architecture.md`](./docs/architecture.md) — диаграмма целевой архитектуры

### Фаза 0.1 — SSH Certificate Authority (мини-CA) (в работе)

- [`docs/phase-0.1/README.md`](./docs/phase-0.1/README.md) — план и чек-листы по настройке мини-CA на `fbsd-ca-sel` (отдельная нода в Selectel)

### Фаза 0 — Подготовка стенда (завершена)

- [`docs/phase-0/01-bsd-vs-linux.md`](./docs/phase-0/01-bsd-vs-linux.md) — философия ядра BSD vs Linux, лицензии, что это значит для продакшена
- [`docs/phase-0/02-freebsd-architecture.md`](./docs/phase-0/02-freebsd-architecture.md) — что под капотом FreeBSD 14/15, сравнение с RHEL/Debian, нюанс arm64 vs amd64
- [`docs/phase-0/03-stack-choice.md`](./docs/phase-0/03-stack-choice.md) — почему Bastille + ZFS + PF + CARP, а не Docker + ext4 + iptables
- [`docs/phase-0/04-scaling.md`](./docs/phase-0/04-scaling.md) — вертикальное vs горизонтальное масштабирование
- [`docs/phase-0/05-shells.md`](./docs/phase-0/05-shells.md) — разделение ролей: tcsh для интерактива, bash+Python для скриптов
- [`docs/phase-0/06-hybrid-stand.md`](./docs/phase-0/06-hybrid-stand.md) — почему ноутбук не часть кластера, динамический IP не баг

### Фаза 1 — FreeBSD актуальный: сеть, ZFS, базовый сервисный SSH (в работе)

- [`docs/phase-1/01-network-stack.md`](./docs/phase-1/01-network-stack.md) — сетевой стек FreeBSD vs Linux: ifconfig vs ip, netstat vs ss, rc.conf
- [`docs/phase-1/02-pf-vs-iptables.md`](./docs/phase-1/02-pf-vs-iptables.md) — PF vs iptables/nftables, история, синтаксис
- [`docs/phase-1/03-zfs-advanced.md`](./docs/phase-1/03-zfs-advanced.md) — ZFS продвинутый: ARC, zpool, dataset, snapshot, send/receive, encryption, dedup
- [`docs/phase-1/04-bhyve-vs-kvm.md`](./docs/phase-1/04-bhyve-vs-kvm.md) — bhyve vs KVM vs VMware ESXi, нюанс arm64

## Контакты

- LinkedIn: [https://www.linkedin.com/in/alexeyyarkov/]
- Telegram: [@avalok]
- Email: [alexey.yarkov@gmail.com]
