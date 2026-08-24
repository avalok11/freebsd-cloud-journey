# Фаза 0 — Подготовка стенда

**Статус:** ✅ завершена
**Период:** август 2026
**Цель фазы:** развёрнутый стенд (локально + Selectel), согласованная архитектурная схема, базовая безопасность.

## Что сделано

### Локальный стенд (UTM на Mac M4)

- [x] Установлен UTM на Mac M4
- [x] Создана ВМ `fbsd-arm` с FreeBSD 15.1 arm64 (IP `192.168.64.2`)
- [x] Установлена система, базовая настройка (ZFS root, hostname, timezone)
- [x] Настроен SSH по ключу (`~/.ssh/freebsd_lab`)
- [x] Харденинг sshd_config (отключён вход по паролю, root)
- [x] Установлен sshguard + интеграция с PF (тестировано — бан IP работает)
- [x] Настроен TOTP через Yandex Key (вход по ключу + 6-значный код)
- [x] ntpd для синхронизации времени (без этого TOTP не работал)
- [x] Переход с tcsh на sh как login shell
- [x] Создана ВМ `deb-arm` с Debian 13.6 arm64 (IP `192.168.64.4`) для сравнения с Linux
- [x] SSH по ключу + харденинг sshd на deb-arm
- [x] Создан GitHub-репозиторий `freebsd-cloud-journey` (avalok11)
- [x] Схема архитектуры в Mermaid (обновляется)

### Удалённый стенд (Selectel)

- [x] Создан VPS `fbsd-1-sel` в Selectel (FreeBSD 15.1 amd64, публичный IP `178.72.xxx.xxx`)
- [x] Создан пользователь `white` с группой `wheel` + sudo
- [x] Настроен SSH по ключу + TOTP через Yandex Key
- [x] Настроен ntpd
- [x] Активирован sshguard + PF (как на fbsd-arm, тест блокировки пройден)

### Репозитории

- [x] GitHub `freebsd-cloud-journey` (публичный) — кейс, roadmap, теория, отчёты
- [ ] Gitea `infra-configs` (приватный) — будет в Фазе 4

## Ключевые решения

### Стек выбран
- **FreeBSD 15.1** (актуальная версия на момент 2026) — богатая база, ZFS из коробки, jails.
- **Debian 13.6** для сравнения с Linux (современный, стабильный).
- **UTM на Mac M4** для локальных ВМ (VirtualBox не подходит на M4).
- **Selectel** для production-like стенда (до 10к ₽/мес).

### Безопасность
- Вход только по ключу + TOTP (двухфакторка).
- sshguard + PF как защита от брутфорса (BSD-native, не fail2ban).
- `PasswordAuthentication no` везде.
- `PermitRootLogin no` везде.
- Логин-шелл — sh (POSIX-совместимо, никаких сюрпризов).

### Хостинг
- Ноутбук = рабочая станция, не часть кластера.
- Динамический домашний IP — не проблема, все подключения инициируются к Selectel.
- GitHub публичный — для портфолио.
- Gitea (планируется) — приватный для конфигов.

## Грабли и открытия

### 1. VirtualBox на Mac M4 не работает
- Решение: UTM (нативная поддержка arm64).

### 2. TOTP не работал из-за рассинхронизации времени
- Симптом: код из Яндекс Ключ не принимался.
- Причина: системные часы FreeBSD отставали от UTC.
- Решение: `service ntpd start` + `ntpdate -s time.cloudflare.com`.

### 3. sshguard не реагирует на неудачные SSH-ключи
- Причина: sshguard парсит только события неудачного ввода пароля, а у нас `PasswordAuthentication no`.
- Решение: для теста временно включить `PasswordAuthentication yes`, проверить, что IP попадает в таблицу. В проде — защита от брутфорса обеспечивается отключением пароля.

### 4. sshd ругался на `AuthenticationMethods`
- Симптом: `Disabled method "keyboard-interactive"`.
- Решение: добавить `ChallengeResponseAuthentication yes` и `KbdInteractiveAuthentication yes` в `sshd_config`.

### 5. PAM запрашивал пароль после успешного TOTP
- Причина: `pam_unix.so` стоял как `required` в PAM-стеке, выполнялся после TOTP.
- Решение: сделать `pam_google_authenticator.so` как `sufficient` и поставить ПЕРВЫМ в `/etc/pam.d/sshd`.

### 6. sshguard на fbsd-1-sel
- Настроен по образцу fbsd-arm: `pkg install sshguard`, таблица `<sshguard>` в `/etc/pf.conf`, сервис через `sysrc sshguard_enable=YES`.
- Тест блокировки пройден.
- **Особенность**: на публичном IP брутфорс начинается в первые минуты после создания. За первый час — десятки `Failed password` в `/var/log/auth.log` от ботов.

### 7. fbsd-arm завис на `mountroot>` после ребута в UTM
- **Симптом:** загрузка FreeBSD прерывалась в `mountroot>`, сообщение `Mounting from zfs:zroot/ROOT/default failed with error 2: unknown file system`. `boot -s` (single user) тоже упирался в `mountroot>` — не успевал импортировать пул.
- **Причина:** UTM после рестарта пересоздаёт виртуальный USB-стек, и ядро FreeBSD зависало на `Root mount waiting for: usbus0`, не доходя до импорта ZFS-пула. Пул `zroot` оставался не активирован.
- **Восстановление через loader prompt (`Escape to loader prompt`, опция `3` в boot-меню):**
  1. `lsdev` — посмотреть доступные диски.
  2. `set currdev="zfs:zroot/ROOT/default:"` — задать текущее устройство.
  3. `load /boot/kernel/kernel` — загрузить ядро вручную.
  4. `load /boot/kernel/zfs.ko` — загрузить модуль ZFS.
  5. `set hint.uhub.0.port.1.disabled="1"` — отключить первый порт USB-хаба (именно он блокировал загрузку). **Не весь `uhub.0.disabled=1`, иначе клавиатура в UTM перестаёт работать.**
  6. `boot` — продолжить загрузку.
- **Постоянное решение** — закрепить в `/boot/loader.conf`:
  ```ini
  zfs_load="YES"
  hint.uhub.0.port.1.disabled="1"
  pf_load="YES"
  ```
  И в случае повторения — добавить `vfs.root.mountfrom="zfs:zroot/ROOT/default"`.
- **Урок:** в UTM `hint.uhub.0.disabled="1"` (полное отключение USB) отрубает клавиатуру, и ты теряешь контроль над ВМ. Отключать нужно только проблемный порт: `hint.uhub.0.port.N.disabled="1"`. Номер порта определяется через `lsdev` в loader prompt.

## Метрики

| Что | Значение |
|---|---|
| Время установки FreeBSD 15.1 arm64 в UTM | ~30 мин |
| Время на базовую настройку + SSH-ключи | ~20 мин |
| Время на настройку sshguard + PF | ~30 мин (с тестом блокировки) |
| Время на настройку TOTP (с решением граблей со временем) | ~40 мин |
| Время на установку deb-arm (Debian 13) | ~15 мин |
| Стоимость fbsd-1-sel в Selectel | ~1200 ₽/мес (2 vCPU, 4 ГБ, 30 ГБ SSD) |

## Артефакты

- [architecture.md](../architecture.md) — обновлённая схема с фактическими IP
- [roadmap.md](../roadmap.md) — план
- Теоретические заметки (Phase 0):
  - [01-bsd-vs-linux.md](./01-bsd-vs-linux.md)
  - [02-freebsd-architecture.md](./02-freebsd-architecture.md)
  - [03-stack-choice.md](./03-stack-choice.md)
  - [04-scaling.md](./04-scaling.md)
  - [05-shells.md](./05-shells.md)
  - [06-hybrid-stand.md](./06-hybrid-stand.md)

## Скриншоты / вывод команд

### fbsd-arm (локально)

```
uname -a:
FreeBSD fbsd-arm 15.1-RELEASE FreeBSD 15.1-RELEASE releng/15.1-n283562-96841ea08dcf GENERIC arm64

freebsd-version:
15.1-RELEASE
```

### deb-arm (локально)

```
uname -a:
Linux deb-arm 6.12.101+deb13-arm64 #1 SMP Debian 6.12.101-1 (2026-08-05) aarch64 GNU/Linux

cat /etc/debian_version:
13.6
```

### fbsd-1-sel (Selectel)

```
uname -a:
FreeBSD fbsd-1-sel.lab.sel 15.1-RELEASE FreeBSD 15.1-RELEASE releng/15.1-n283562-96841ea08dcf GENERIC amd64

freebsd-version:
15.1-RELEASE

ifconfig vtnet0:
inet 172.16.0.2 netmask 0xffff0000 broadcast 172.16.255.255
```

## Что дальше

Фаза 0 завершена. Переходим к **Фазе 1** — сеть + ZFS + сервисный SSH (3 недели).

## Итог Фазы 0

**Готовая инфраструктура:**
- Локальный стенд: FreeBSD 15.1 arm64 + Debian 13.6 arm64 на UTM.
- Удалённый стенд: FreeBSD 15.1 amd64 в Selectel с публичным IP.
- Безопасность: ssh по ключу + TOTP через Yandex Key на всех FreeBSD-нодах.
- sshguard + PF активированы на обеих FreeBSD-нодах.
- Документация: 6 теоретических брифов + roadmap + архитектурная схема.
- Репозиторий: github.com/avalok11/freebsd-cloud-journey (публичный).

**Ключевые навыки, восстановленные/полученные:**
- Установка и настройка FreeBSD 14/15 на UTM и в облаке.
- Харденинг sshd_config.
- Настройка TOTP (двухфакторка для SSH).
- Интеграция sshguard + PF для защиты от брутфорса.
- Базовая работа с ZFS root, pf, rc.conf.
- Работа с Debian/Ubuntu (харденинг, ssh по ключу).
- Работа с Mermaid-схемами в GitHub.
- Работа с tcsh → sh миграцией.
