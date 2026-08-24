# Фаза 0.1 — SSH Certificate Authority (мини-CA)

**Статус:** в работе
**Период:** август 2026
**Цель фазы:** поднять мини-CA на `fbsd-ca-sel` со структурированным хранением ключей, подписать пользовательские и хостовые ключи, настроить доверие на всех нодах, написать скрипты подписи и отзыва.

## Зачем это сейчас

SSH CA в плане стояла в Фазе 8 (продуктовый пакет для заказчика). Поднимаем раньше, потому что:

1. **ZFS-репликация в Фазе 1** требует сервисный ключ `zfs-repl` с `forced-command` и ограничениями. С CA можно подписать ключ с TTL 8 часов — если утечёт, через 8 часов автоматически перестанет работать.
2. **Ansible в Фазе 4** — управляющая нода будет ходить на все ноды кластера. CA-сертификат управляющей ноды = одна точка отзыва.
3. **Учиться проще на 2 нодах**, чем на 5+ в продакшене.

## Структура каталогов CA на `fbsd-ca-sel`

```
/usr/local/sshca/
├── user_ca                  # приватный ключ User CA
├── user_ca.pub              # публичный ключ User CA (раскопируется на ноды)
├── host_ca                  # приватный ключ Host CA
├── host_ca.pub              # публичный ключ Host CA (раскопируется на ноды)
├── users/                   # подписанные пользовательские сертификаты
│   ├── white/
│   │   ├── freebsd_lab.pub          # оригинальный публичный ключ
│   │   ├── freebsd_lab-cert.pub     # подписанный сертификат
│   │   └── history.log              # история подписей (кто, когда, TTL)
│   └── ...
├── hosts/                   # подписанные host-сертификаты
│   ├── fbsd-1-sel/
│   │   ├── sshd_host_ed25519_key.pub
│   │   ├── sshd_host_ed25519_key-cert.pub
│   │   └── history.log
│   ├── fbsd-arm/
│   │   └── ...
│   └── ...
├── revoked/                 # отозванные ключи
│   ├── users/
│   └── hosts/
└── scripts/
    ├── sign-user-cert.sh
    ├── sign-host-cert.sh
    └── revoke-ssh.sh
```

**Права доступа:**
- `/usr/local/sshca/` — `chmod 700` (только root).
- `user_ca`, `host_ca` — `chmod 600` (только root читает).
- `*.pub`, `*-cert.pub` — `chmod 644` (читаются всеми для копирования).
- `users/<user>/` и `hosts/<host>/` — `chmod 700` (только root, чтобы не светить чужие ключи).

## Что сделано

- [ ] Создать `fbsd-ca-sel` в Selectel (1 vCPU, 1 ГБ RAM, 10 ГБ SSD, FreeBSD 15.1 amd64)
- [ ] Базовый харденинг `fbsd-ca-sel`: sshd_config, sshguard + PF, NTP, TOTP
- [ ] Создать структуру каталогов `/usr/local/sshca/`
- [ ] Сгенерировать User CA и Host CA
- [ ] Приватные ключи CA защищены (chmod 600)
- [ ] Бэкап CA в 1Password + зашифрованный архив на `fbsd-1-sel`
- [ ] Скрипты `sign-user-cert.sh`, `sign-host-cert.sh`, `revoke-ssh.sh`
- [ ] Подписан твой `~/.ssh/freebsd_lab.pub` (TTL 8 часов)
- [ ] Host-ключи `fbsd-1-sel` и `fbsd-arm` подписаны (TTL 52 недели)
- [ ] Публичные ключи CA раскопированы на все FreeBSD-ноды
- [ ] sshd настроен на доверие CA: `TrustedUserCAKeys`, `HostCertificate`
- [ ] Тест: вход по сертификату с Mac M4 без указания ключа
- [ ] Тест: TTL истекает — вход отклоняется
- [ ] CRL (список отзыва) настроен вручную, проверен
- [ ] **Автоматизация CRL — в Фазе 4** (Ansible-роль)

## Теория

Ключевые понятия (кратко, для понимания что делаем):

- **User CA** — подписывает пользовательские публичные ключи. Результат — сертификат `id_ed25519-cert.pub` с TTL и principals.
- **Host CA** — подписывает хостовые ключи серверов. Результат — сертификат `sshd_host_ed25519_key-cert.pub`. Клиенты автоматически доверяют хосту, подписанному CA.
- **TTL (`-V +8h:00`)** — срок действия. По истечении — сертификат невалиден.
- **Principals (`-n white,root`)** — какие логины разрешены для этого сертификата. Защита: подписанный ключ от `white` не пустит как `root`, даже если подписан CA.
- **CRL (`RevokedKeys`)** — файл с отозванными публичными ключами. Хоть срок действия истёк, в CRL добавляют для раннего отзыва.

## Практика (план)

1. **Создать `fbsd-ca-sel` в Selectel** (1 vCPU, 1 ГБ RAM, 10 ГБ SSD, FreeBSD 15.1 amd64, публичный IP).
2. **Базовый харденинг** `fbsd-ca-sel`: sshd_config, sshguard + PF, NTP, TOTP.
3. **Создать структуру каталогов** `/usr/local/sshca/`:
   ```bash
   sudo mkdir -p /usr/local/sshca/{users,hosts,revoked/{users,hosts},scripts}
   sudo chmod -R 700 /usr/local/sshca
   ```
4. **Генерация User CA и Host CA** в `/usr/local/sshca/`:
   ```bash
   sudo ssh-keygen -t ed25519 -f /usr/local/sshca/user_ca -C "User CA"
   sudo ssh-keygen -t ed25519 -f /usr/local/sshca/host_ca -C "Host CA"
   sudo chmod 600 /usr/local/sshca/user_ca /usr/local/sshca/host_ca
   sudo chmod 644 /usr/local/sshca/user_ca.pub /usr/local/sshca/host_ca.pub
   ```
5. **Бэкап приватных ключей CA** в 1Password + зашифрованный архив на `fbsd-1-sel`.
6. **Скрипт подписи** `sign-user-cert.sh` (см. ниже).
7. **Подписать твой ключ** (с Mac M4):
   ```bash
   scp ~/.ssh/freebsd_lab.pub fbsd-ca-sel:/tmp/
   ssh fbsd-ca-sel "/usr/local/sshca/scripts/sign-user-cert.sh /tmp/freebsd_lab.pub white,root +8h:00"
   scp fbsd-ca-sel:/usr/local/sshca/users/white/freebsd_lab-cert.pub ~/.ssh/
   ```
8. **Скрипт подписи host-ключей** и подписать `fbsd-1-sel`, `fbsd-arm`.
9. **Раскопировать публичные ключи CA** на все ноды.
10. **Настроить sshd** на доверие CA на всех нодах.
11. **Перезапустить sshd**, проверить вход по сертификату.
12. **Настроить CRL** через `revoke-ssh.sh`.

## Скрипты

### `sign-user-cert.sh`

```bash
#!/bin/sh
# Подписать пользовательский публичный ключ.
# Использование: sign-user-cert.sh <pubkey> <principals> [ttl]
# Пример: sign-user-cert.sh /tmp/key.pub white,root +8h:00

set -e

PUBKEY=$1
PRINCIPALS=$2
TTL=${3:-"+8h:00"}
CA_DIR="/usr/local/sshca"

if [ -z "$PUBKEY" ] || [ -z "$PRINCIPALS" ]; then
    echo "Использование: $0 <pubkey> <principals> [ttl]"
    echo "Пример: $0 /tmp/key.pub white,root +8h:00"
    exit 1
fi

if [ ! -f "$PUBKEY" ]; then
    echo "Ошибка: файл $PUBKEY не найден"
    exit 1
fi

# Извлечь имя пользователя из пути (последний компонент без .pub)
KEYNAME=$(basename "$PUBKEY" .pub)
# Спросить у пользователя, для кого подписываем
echo "Для какого пользователя подписываем? (по умолчанию: $KEYNAME)"
read -r USERNAME
USERNAME=${USERNAME:-$KEYNAME}

USER_DIR="$CA_DIR/users/$USERNAME"
mkdir -p "$USER_DIR"
chmod 700 "$USER_DIR"

# Скопировать оригинальный ключ, если ещё не там
if [ ! -f "$USER_DIR/$KEYNAME.pub" ]; then
    cp "$PUBKEY" "$USER_DIR/$KEYNAME.pub"
    chmod 644 "$USER_DIR/$KEYNAME.pub"
fi

# Подписать
ssh-keygen -s "$CA_DIR/user_ca" \
    -I "$(whoami)@$(hostname -s)" \
    -n "$PRINCIPALS" \
    -V "$TTL" \
    -f "$USER_DIR/$KEYNAME-cert.pub" \
    "$USER_DIR/$KEYNAME.pub"

# Логировать
echo "$(date -Iseconds) | $USERNAME | $PRINCIPALS | $TTL | $KEYNAME" >> "$USER_DIR/history.log"

echo ""
echo "Сертификат подписан: $USER_DIR/$KEYNAME-cert.pub"
echo "Скопируйте его на ноду клиента рядом с приватным ключом."
```

### `sign-host-cert.sh`

```bash
#!/bin/sh
# Подписать host-ключ сервера.
# Использование: sign-host-cert.sh <host-pubkey> <hostname> [ttl]
# Пример: sign-host-cert.sh /etc/ssh/sshd_host_ed25519_key.pub fbsd-1-sel +52w

set -e

PUBKEY=$1
HOSTNAME=$2
TTL=${3:-"+52w"}
CA_DIR="/usr/local/sshca"

if [ -z "$PUBKEY" ] || [ -z "$HOSTNAME" ]; then
    echo "Использование: $0 <host-pubkey> <hostname> [ttl]"
    exit 1
fi

if [ ! -f "$PUBKEY" ]; then
    echo "Ошибка: файл $PUBKEY не найден"
    exit 1
fi

HOST_DIR="$CA_DIR/hosts/$HOSTNAME"
mkdir -p "$HOST_DIR"
chmod 700 "$HOST_DIR"

KEYNAME=$(basename "$PUBKEY")

# Скопировать оригинальный ключ
cp "$PUBKEY" "$HOST_DIR/$KEYNAME"
chmod 644 "$HOST_DIR/$KEYNAME"

# Подписать
ssh-keygen -s "$CA_DIR/host_ca" \
    -h \
    -I "$HOSTNAME" \
    -n "$HOSTNAME" \
    -V "$TTL" \
    -f "$HOST_DIR/${KEYNAME}-cert.pub" \
    "$HOST_DIR/$KEYNAME"

# Логировать
echo "$(date -Iseconds) | $HOSTNAME | $TTL | $KEYNAME" >> "$HOST_DIR/history.log"

echo ""
echo "Host-сертификат подписан: $HOST_DIR/${KEYNAME}-cert.pub"
echo "Скопируйте его на ноду $HOSTNAME в /etc/ssh/ и добавьте в sshd_config:"
echo "  HostCertificate $PUBKEY-cert.pub"
```

### `revoke-ssh.sh`

```bash
#!/bin/sh
# Отозвать пользовательский или хост-ключ.
# Использование:
#   revoke-ssh.sh user <username> <keyname>
#   revoke-ssh.sh host <hostname> <keyname>
# Пример:
#   revoke-ssh.sh user white freebsd_lab
#   revoke-ssh.sh host fbsd-1-sel sshd_host_ed25519_key

set -e

TYPE=$1
NAME=$2
KEYNAME=$3
CA_DIR="/usr/local/sshca"

if [ -z "$TYPE" ] || [ -z "$NAME" ] || [ -z "$KEYNAME" ]; then
    echo "Использование: $0 {user|host} <name> <keyname>"
    exit 1
fi

case "$TYPE" in
    user)
        KEY="$CA_DIR/users/$NAME/$KEYNAME.pub"
        REVOKE_DIR="$CA_DIR/revoked/users/$NAME"
        ;;
    host)
        KEY="$CA_DIR/hosts/$NAME/$KEYNAME.pub"
        REVOKE_DIR="$CA_DIR/revoked/hosts/$NAME"
        ;;
    *)
        echo "Ошибка: тип должен быть 'user' или 'host'"
        exit 1
        ;;
esac

if [ ! -f "$KEY" ]; then
    echo "Ошибка: ключ $KEY не найден"
    exit 1
fi

mkdir -p "$REVOKE_DIR"
chmod 700 "$REVOKE_DIR"

# Скопировать ключ в revoked
cp "$KEY" "$REVOKE_DIR/$KEYNAME.pub"
chmod 644 "$REVOKE_DIR/$KEYNAME.pub"

# Добавить в общий CRL файл
CRL="$CA_DIR/revoked/revoked_keys"
touch "$CRL"
chmod 644 "$CRL"
cat "$KEY" >> "$CRL"

# Логировать
LOG_FILE="$CA_DIR/revoked/revocation.log"
echo "$(date -Iseconds) | $TYPE | $NAME | $KEYNAME" >> "$LOG_FILE"

echo ""
echo "Ключ отозван."
echo "Скопируйте $CRL на ноды как /etc/ssh/ca/revoked_keys"
echo "И добавьте в sshd_config: RevokedKeys /etc/ssh/ca/revoked_keys"
echo "Перезапустите sshd на всех нодах."
```

## Тестирование

| Сценарий | Ожидаемый результат |
|---|---|
| `ssh fbsd-1-sel` с подписанным ключом | Вход без `-i`, ssh сам выберет сертификат |
| Подписать с TTL 1 минута, подождать | Через 2 минуты вход отклоняется |
| `ssh` на новую ноду с подписанным host-ключом | `Host key verification failed` НЕ появляется |
| Добавить ключ в CRL через `revoke-ssh.sh` | Вход отклоняется даже при валидном сертификате |
| Войти под `root` ключом, подписанным только для `white` | Должно отказать (principal mismatch) |
| Проверить `history.log` | Все подписи зафиксированы с датой, principals, TTL |

## Артефакты (после завершения фазы)

- `/usr/local/sshca/user_ca`, `user_ca.pub` — User CA.
- `/usr/local/sshca/host_ca`, `host_ca.pub` — Host CA.
- `/usr/local/sshca/scripts/sign-user-cert.sh` — скрипт подписи пользовательских ключей.
- `/usr/local/sshca/scripts/sign-host-cert.sh` — скрипт подписи host-ключей.
- `/usr/local/sshca/scripts/revoke-ssh.sh` — скрипт отзыва.
- `/usr/local/sshca/users/<user>/history.log` — журнал подписей.
- `/usr/local/sshca/hosts/<host>/history.log` — журнал подписей.
- `ssh-ca-setup.md` — документация по настройке и использованию.
- В Фазе 4: `infra-configs/roles/ssh-ca/` — Ansible-роль для раскладки CA на ноды.

## Что дальше

После завершения Фазы 0.1:
- **Фаза 1** — сеть + ZFS + сервисный SSH (с использованием CA для подписи сервисных ключей).
- **Фаза 4 (Ansible)** — Ansible-роль `ssh-ca` для автоматической раскладки CA на новые ноды.
- **Фаза 8 (продуктовый пакет)** — финальная документация для заказчика по работе с CA.

## Безопасность

- **Приватные ключи CA** — самое ценное, что у нас есть. Хранятся только на `fbsd-ca-sel`, в `/usr/local/sshca/`, права 600.
- **Структура каталогов** — `users/<username>/` и `hosts/<hostname>/` изолированы, чтобы не светить чужие ключи.
- **Бэкап CA** — зашифрованный архив, в 1Password и на отдельной защищённой ноде.
- **Отзыв** — если утекли приватные ключи CA, нужно генерировать новые и **сразу** обновлять `TrustedUserCAKeys` на всех нодах. Считай, что всё, что было подписано старым CA, скомпрометировано.
