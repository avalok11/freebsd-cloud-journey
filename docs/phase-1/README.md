# Фаза 1 — FreeBSD актуальный: сеть, ZFS, базовый сервисный SSH

**Статус:** в работе
**Период:** август 2026
**Цель фазы:** уверенная работа с сетью и ZFS на актуальной FreeBSD, понимание отличий от Linux, настроенная сервисная SSH-учётка для ZFS-репликации.

## Что сделано

- [ ] Настройка сети на fbsd-1-sel (статический IP, gateway, DNS)
- [ ] Базовая настройка PF на fbsd-1-sel
- [ ] ZFS: создание zpool, датасетов
- [ ] ZFS: эксперименты со снапшотами, rollback, clone
- [ ] ZFS send/receive на fbsd-arm
- [ ] Шифрованный dataset
- [ ] Сервисный SSH-пользователь `zfs-repl` с `forced-command`
- [ ] Тест failover репликации
- [ ] Сравнение с Linux (ext4+LVM, btrfs) на deb-arm

## Теоретические заметки

- [01-network-stack.md](./01-network-stack.md) — сетевой стек FreeBSD vs Linux: ifconfig vs ip, netstat vs ss, rc.conf
- [02-pf-vs-iptables.md](./02-pf-vs-iptables.md) — PF (Packet Filter) vs iptables/nftables, история, синтаксис
- [03-zfs-advanced.md](./03-zfs-advanced.md) — ZFS продвинутый: ARC, zpool, dataset, snapshot, send/receive, encryption, dedup
- [04-bhyve-vs-kvm.md](./04-bhyve-vs-kvm.md) — bhyve vs KVM vs VMware ESXi, нюанс arm64

## Практика

- [ ] Полная настройка сети на FreeBSD
- [ ] Установка и базовая настройка PF
- [ ] Создание zpool, датасетов
- [ ] Снапшоты, clone, rollback
- [ ] Репликация на удалённую ноду
- [ ] Сервисный ssh для ZFS replication

## Тестирование

- [ ] Сетевое: PF правила работают, nmap снаружи показывает только ssh
- [ ] ZFS: snapshot, rollback, scrub
- [ ] ZFS replication: на вторую ноду отправить dataset, на второй ноде смонтировать
- [ ] Failover-тест: симулировать падение основной ноды
- [ ] Сервисный SSH-тест: зайти под `zfs-repl` интерактивно отказать, с другого IP ключ не принимается, с правильного IP работает только `zfs receive`

## Ключевые решения

(заполнять по ходу)

## Грабли и открытия

(заполнять по ходу)

## Метрики

(заполнять по ходу)

## Артефакты

- [phase-1-zfs-report.md](./phase-1-zfs-report.md) — отчёт о результатах ZFS-тестов
- [pf-ruleset.conf](./pf-ruleset.conf) — базовый набор правил PF с комментариями
- [zfs-replication.sh](./zfs-replication.sh) — скрипт репликации
- [service-ssh-setup.md](./service-ssh-setup.md) — документация по сервисной SSH-учётке

## Что дальше

После завершения Фазы 1:
- **Фаза 2** — jails + Bastille + bhyve (3 недели)
- **Фаза 3** — HA: CARP, lagg, HAProxy (3 недели)
- И далее по roadmap.
