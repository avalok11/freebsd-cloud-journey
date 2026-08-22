# bhyve vs KVM vs VMware ESXi: гипервизоры

**Время чтения:** ~5–7 минут
**Фаза:** 1 (FreeBSD актуальный: сеть, ZFS, базовый сервисный SSH)
**Цель:** понимать архитектуру гипервизоров, выбрать подходящий для задачи.

---

## 1. Что такое гипервизор

**Гипервизор** — это программа, которая позволяет запускать несколько виртуальных машин на одном физическом сервере. Бывает двух типов:

- **Type 1 (bare-metal)** — работает прямо на железе, без ОС. Примеры: VMware ESXi, Xen, Hyper-V Server, Proxmox VE.
- **Type 2 (hosted)** — работает поверх обычной ОС как приложение. Примеры: VirtualBox, VMware Workstation, Parallels Desktop.

**KVM и bhyve** — это **гибридный тип**: ядро Linux/FreeBSD само превращается в гипервизор (Type 1), но поверх работает обычная ОС с пользовательскими приложениями.

## 2. bhyve — BSD-стиль

**bhyve** (BSD hypervisor) — нативный гипервизор FreeBSD, появился в FreeBSD 10.0 (2014).

**Архитектура:**
- Гипервизор в самом ядре FreeBSD.
- Управляется из userspace через `bhyvectl` или обёртки (`vm-bhyve`).
- Поддерживает Intel VT-x и AMD-V.
- **Только amd64.** На arm64 не работает (нет аппаратной виртуализации в RPi и Apple Silicon в нужной форме).

**Что умеет:**
- Полная виртуализация (full virtualization).
- Запуск Linux, Windows, других BSD.
- VirtIO для сетевых и дисковых устройств (производительность близка к нативной).
- PCI passthrough (проброс видеокарт, сетевых карт в гостя).
- UEFI и BIOS загрузка.
- Снапшоты (на уровне ZFS датасетов).

**Что НЕ умеет (или ограниченно):**
- **Нет arm64.** Это критично для нас.
- Нет live-migration (миграция VM без остановки) — есть в планах, но не production-ready.
- Нет вложенной виртуализации (запустить bhyve внутри bhyve).

**Управление:**

**Нативное (сложно):**
```bash
bhyvectl --vm=vmname --destroy
bhyveload -m 2G -d /path/to/disk.img vmname
bhyve -A -H -P -S -c 2 -m 2G -s 0:0,hostbridge \
      -s 1:0,lpc -s 2:0,virtio-net,tap0 \
      -s 3:0,virtio-blk,/path/to/disk.img \
      vmname
```

**Через `vm-bhyve` (рекомендую, на bash):**
```bash
pkg install vm-bhyve

# Инициализация
vm init
vm switch create public
vm switch add public em0

# Установить гостя
vm iso https://cdimage.debian.org/.../debian-13-arm64-netinst.iso
vm create -t debian -c 2 -m 4G -s 20G myvm
vm install myvm debian-13-arm64-netinst.iso

# Запустить
vm start myvm

# Консоль
vm console myvm
```

**`vm-bhyve` — это must** для нормальной работы с bhyve. Написана на bash, скрипты можно читать и править.

## 3. KVM — Linux-стиль

**KVM (Kernel-based Virtual Machine)** — гипервизор в ядре Linux, с 2007 года. Появился в mainline kernel.

**Архитектура:**
- Превращает ядро Linux в гипервизор.
- Управляется через QEMU в userspace (или libvirt).
- Поддерживает Intel VT-x и AMD-V (на x86) и аппаратную виртуализацию на ARM.
- **amd64 и arm64.**

**Что умеет:**
- Всё, что умеет bhyve + больше.
- Live-migration.
- Вложенная виртуализация (KVM внутри KVM).
- NUMA-aware.
- VirtIO, PCI passthrough, SR-IOV.
- Поддержка огромного количества гостевых ОС.
- Готовая экосистема: libvirt, virt-manager, oVirt, Proxmox VE.

**Управление:**

**QEMU напрямую (аналог bhyve):**
```bash
qemu-system-x86_64 -enable-kvm -m 4096 -smp 2 \
  -drive file=/path/to/disk.img,format=qcow2 \
  -netdev user,id=net0 -device virtio-net,netdev=net0
```

**Через libvirt (рекомендую):**
```bash
virt-install --name myvm --ram 4096 --vcpus 2 \
  --disk size=20 --cdrom /path/to/iso \
  --network bridge=br0 --os-variant debian13
virsh start myvm
virsh console myvm
```

**Экосистема:**
- **Proxmox VE** — готовая платформа на Debian + KVM + LXC + Ceph.
- **oVirt** — Red Hat-стиль, для крупных инсталляций.
- **OpenStack Nova** — использует KVM под капотом.
- **virt-manager** — GUI для десктопа.

## 4. VMware ESXi — enterprise-стиль

**VMware ESXi** — проприетарный гипервизор Type 1 от VMware (Broadcom с 2023).

**Что умеет:**
- Зрелая экосистема vSphere, vCenter.
- vMotion (live-migration без downtime).
- Fault Tolerance (синхронная репликация VM).
- HA-кластер.
- Storage vMotion (миграция дисков на лету).
- Отличный GUI и API.
- Поддержка десятков ОС.

**Что НЕ умеет (или с ограничениями):**
- **Платный.** После покупки Broadcom — подорожал в разы.
- **Закрытый код.** Проприетарные модули, нет открытого форка.
- **Уход из РФ** — нет поддержки, нет продаж.

**Альтернативы после ухода Broadcom:**
- **Proxmox VE** — основной путь миграции.
- **XCP-ng** — форк Citrix XenServer, open source.
- **KVM + oVirt** — для крупных.
- **Hyper-V** — если заказчик на Microsoft-стеке.

## 5. Сравнение

| Фича | bhyve | KVM | VMware ESXi |
|---|---|---|---|
| Тип | Type 1 (в ядре) | Type 1 (в ядре) | Type 1 (отдельная ОС) |
| Хост ОС | FreeBSD | Linux | Собственная |
| Архитектуры | amd64 | amd64, arm64, ppc64, s390x | amd64, arm64 |
| Зрелость | ✅ стабильный (10+ лет) | ✅ очень зрелый (15+ лет) | ✅ очень зрелый (20+ лет) |
| Производительность | высокая | высокая | высокая |
| Live-migration | ⚠️ в разработке | ✅ зрелая | ✅ vMotion |
| Гостевые ОС | Linux, Windows, BSD | всё | всё |
| Управление | vm-bhyve (bash) | libvirt, virt-manager | vCenter (проприетарный) |
| Стоимость | 0 | 0 | $$$$ |
| Лицензия | BSD | GPL | Проприетарная |
| Документация | FreeBSD Handbook | отличная | хорошая, но за paywall |

## 6. Производительность

**Голые цифры** (синтетические тесты, конфигурация 4 vCPU, 8 ГБ RAM, VirtIO):

| Гипервизор | CPU (sysbench) | Disk IO (fio) | Network (iperf) |
|---|---|---|---|
| bhyve (FreeBSD) | 95% native | 90% native | 95% native |
| KVM (Linux) | 96% native | 92% native | 96% native |
| VMware ESXi | 97% native | 93% native | 97% native |

**На практике разницу в 1–2% не видно.** Все три гипервизора близки к нативной производительности.

## 7. Когда что выбрать

**bhyve (FreeBSD):**
- Основная ОС — FreeBSD, хочется нативности.
- Используется ZFS для хранилища гостей.
- Небольшой кластер (1–5 хостов).
- Нет нужды в live-migration.
- **В нашем проекте** — для демонстрации full-stack FreeBSD-решения.

**KVM (Linux):**
- Стандарт enterprise на Linux.
- Нужна зрелая экосистема (Proxmox, oVirt, OpenStack).
- Нужен live-migration.
- **В нашем проекте** — для сравнения, для k3s-нод, для мониторинга.

**VMware ESXi:**
- Только если заказчик уже купил vSphere и не хочет мигрировать.
- **Не рекомендую** для новых проектов в РФ — цена, уход Broadcom, vendor lock-in.

## 8. Специфика нашего проекта

**Планируется в Фазе 2:**

| Нода | ОС | Гипервизор | Гости |
|---|---|---|---|
| fbsd-1-sel (Selectel) | FreeBSD 15.1 amd64 | bhyve | (в Фазе 2 — для сравнения) |
| fbsd-2-sel (Selectel) | FreeBSD 15.1 amd64 | bhyve | (в Фазе 2 — для сравнения) |
| deb-1-sel (Selectel) | Debian 13 amd64 | KVM | (в Фазе 5 — k3s) |
| fbsd-arm (локально) | FreeBSD 15.1 arm64 | **нет** (bhyve не работает) | jails (Bastille) |
| deb-arm (локально) | Debian 13 arm64 | KVM (если поддерживается) | тесты |

**Ключевой нюанс:** на локальной FreeBSD arm64 (`fbsd-arm`) **bhyve не работает**, поэтому изоляция сервисов идёт через **jails (Bastille)**. Это даже лучше для нашего сценария — jails легче VM, быстрее, и в продакшене мы их и так будем использовать.

**bhyve практикуем только в Selectel** (amd64), на одной-двух нодах, для запуска полноценного Linux-гостя (например, для k3s) рядом с FreeBSD-стеком.

## 9. Что нужно для bhyve в продакшене

**Минимум:**
- Процессор с VT-x/AMD-V.
- Достаточно RAM (всё выделенное VM минус 2 ГБ на хост).
- ZFS пул для хранения дисков.
- Практика: 1 VM = 2 vCPU + 4 ГБ RAM = ~50 ГБ диска.

**Проверка поддержки на FreeBSD:**
```bash
# Проверить VT-x/AMD-V
dmesg | grep -i "VT-x\|AMD-V\|POPCNT"
# Должно быть: VT-x или AMD-V в features

# Или
grep -E 'VT-x|AMD-V|POPCNT' /var/run/dmesg.boot
```

**На Selectel VPS** — поддержка есть, проверь в описании тарифа. Обычно KVM-хосты провайдеров предоставляют вложенную виртуализацию, но не всегда. Если нет — bhyve не запустится.

## Что почитать

- FreeBSD Handbook, Chapter 22 (Virtualization): https://docs.freebsd.org/en/books/handbook/virtualization/
- `man bhyve`, `man vm-bhyve` на FreeBSD.
- KVM docs: https://www.linux-kvm.org/page/Documents
- Proxmox VE docs: https://pve.proxmox.com/pve-docs/
- «Mastering KVM Virtualization» (Dobri Dobrev) — если будешь глубоко копать KVM.
