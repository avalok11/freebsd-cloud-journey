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
│   ├── avalok11/
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
- **Principals (`-n avalok11,root`)** — какие логины разрешены для этого сертификата. Защита: подписанный ключ от `avalok11` не пустит как `root`, даже если подписан CA.
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
   ssh fbsd-ca-sel "/usr/local/sshca/scripts/sign-user-cert.sh /tmp/freebsd_lab.pub avalok11,root +8h:00"
   scp fbsd-ca-sel:/usr/local/sshca/users/avalok11/freebsd_lab-cert.pub ~/.ssh/
   ```
8. **Скрипт подписи host-ключей** и подписать `fbsd-1-sel`, `fbsd-arm`.
9. **Раскопировать публичные ключи CA** на все ноды.
10. **Настроить sshd** на доверие CA на всех нодах.
11. **Перезапустить sshd**, проверить вход по сертификату.
12. **Настроить CRL** через `revoke-ssh.sh`.

## Скрипты

Готовые файлы скриптов лежат в `docs/phase-0.1/scripts/`:

- [`scripts/sign-user-cert.sh`](./scripts/sign-user-cert.sh) — подпись пользовательских ключей.
- [`scripts/sign-host-cert.sh`](./scripts/sign-host-cert.sh) — подпись host-ключей.
- [`scripts/revoke-ssh.sh`](./scripts/revoke-ssh.sh) — отзыв ключей.

Ниже — содержимое каждого скрипта для справки.

### `sign-user-cert.sh`

```bash
#!/bin/sh
# Подписать пользовательский публичный ключ.
# Использование: sign-user-cert.sh <pubkey> <principals> [ttl]
# Пример: sign-user-cert.sh /tmp/key.pub avalok11,root +8h:00

set -e

PUBKEY=$1
PRINCIPALS=$2
TTL=${3:-"+8h:00"}
CA_DIR="/usr/local/sshca"

if [ -z "$PUBKEY" ] || [ -z "$PRINCIPALS" ]; then
    echo "Использование: $0 <pubkey> <principals> [ttl]"
    echo "Пример: $0 /tmp/key.pub avalok11,root +8h:00"
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
#   revoke-ssh.sh user avalok11 freebsd_lab
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

## Дополнительные шаги (host-ключи, ca_known_hosts, revoke-ssh.sh)

### Шаг 8. Подписать host-ключи `fbsd-1-sel` и `fbsd-arm`

**8.1. Скопировать host-ключ с `fbsd-1-sel` на `fbsd-ca-sel` через Mac M4:**

```bash
# На Mac M4
scp -i ~/.ssh/freebsd_lab avalok11@<PUBLIC_IP_FBSD_1_SEL>:/etc/ssh/sshd_host_ed25519_key.pub /tmp/
```

**8.2. Подписать на CA:**

```bash
# Скопировать ключ на fbsd-ca-sel
scp -i ~/.ssh/freebsd_lab /tmp/sshd_host_ed25519_key.pub avalok11@<PUBLIC_IP_FBSD_CA_SEL>:/tmp/

# На fbsd-ca-sel
sudo /usr/local/sshca/scripts/sign-host-cert.sh /tmp/sshd_host_ed25519_key.pub fbsd-1-sel +52w
# Ввести passphrase Host CA
```

**8.3. Скопировать подписанный сертификат на `fbsd-1-sel`:**

```bash
# На Mac M4
scp -i ~/.ssh/freebsd_lab avalok11@<PUBLIC_IP_FBSD_CA_SEL>:/usr/local/sshca/hosts/fbsd-1-sel/sshd_host_ed25519_key-cert.pub /tmp/

# Отправить на fbsd-1-sel
scp -i ~/.ssh/freebsd_lab /tmp/sshd_host_ed25519_key-cert.pub avalok11@<PUBLIC_IP_FBSD_1_SEL>:/tmp/
```

**Повторить для `fbsd-arm`** (заменив `fbsd-1-sel` на `fbsd-arm`).

### Шаг 9. Установить host-сертификаты на нодах

**На каждой ноде (`fbsd-1-sel`, `fbsd-arm`):**

```bash
sudo cp /tmp/sshd_host_ed25519_key-cert.pub /etc/ssh/
sudo chown root:wheel /etc/ssh/sshd_host_ed25519_key-cert.pub
sudo chmod 600 /etc/ssh/sshd_host_ed25519_key-cert.pub
```

### Шаг 10. Настроить `sshd_config` на нодах

**На каждой ноде:**

```bash
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup-ca
sudo ee /etc/ssh/sshd_config
```

**Добавить в КОНЕЦ файла:**

```
# SSH Certificate Authority
TrustedUserCAKeys /etc/ssh/ca/user_ca.pub
HostCertificate /etc/ssh/sshd_host_ed25519_key-cert.pub
RevokedKeys /etc/ssh/ca/revoked_keys
```

**Важно:** `TrustedUserCAKeys` нужен **обязательно** — без него sshd не будет проверять сертификаты. Убедиться, что `user_ca.pub` уже лежит в `/etc/ssh/ca/`.

### Шаг 11. Перезапустить sshd на нодах

```bash
sudo sshd -t
sudo service sshd restart
sudo service sshd status
```

### Шаг 12. Создать `~/.ssh/ca_known_hosts` на Mac M4

**Цель:** ssh-клиент будет доверять host-сертификатам без запроса `Are you sure you want to continue connecting`.

**12.1. Скопировать `host_ca.pub` на Mac M4:**

```bash
# На Mac M4
scp -i ~/.ssh/freebsd_lab avalok11@<PUBLIC_IP_FBSD_CA_SEL>:/usr/local/sshca/host_ca.pub ~/.ssh/host_ca.pub
```

**12.2. Создать `~/.ssh/ca_known_hosts`:**

```bash
touch ~/.ssh/ca_known_hosts
chmod 600 ~/.ssh/ca_known_hosts
```

**12.3. Внести запись `@cert-authority`:**

```bash
# Формат: @cert-authority <pattern> <keytype> <base64-key>
# pattern — каким хостам доверяем: *, *.example.com, fbsd-*, etc.

# Доверие всем хостам, подписанным нашим Host CA:
echo "@cert-authority * $(cat ~/.ssh/host_ca.pub)" >> ~/.ssh/ca_known_hosts
```

**12.4. Проверить:**

```bash
cat ~/.ssh/ca_known_hosts
# Должно быть: @cert-authority * ssh-ed25519 AAAAC3Nz...
```

**12.5. Удалить старые отпечатки из `known_hosts` (для теста):**

```bash
ssh-keygen -f ~/.ssh/known_hosts -R fbsd-1-sel
ssh-keygen -f ~/.ssh/known_hosts -R fbsd-arm
```

**12.6. Проверить вход — `Host key verification` НЕ должен появиться:**

```bash
ssh -v fbsd-1-sel whoami
# Ввести TOTP
# В выводе должно быть: "Server host key: ssh-ed25519 ... (cert valid)"
# Не должно быть: "Are you sure you want to continue connecting"
```

### Шаг 13. Создать `revoke-ssh.sh` (если ещё не создан)

Проверить наличие:

```bash
# На fbsd-ca-sel
ls -la /usr/local/sshca/scripts/revoke-ssh.sh
```

Если файла нет — создать по образцу из секции «Скрипты» выше. Содержимое:

```bash
#!/bin/sh
# Отозвать пользовательский или хост-ключ.
# Использование:
#   revoke-ssh.sh user <username> <keyname>
#   revoke-ssh.sh host <hostname> <keyname>

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

cp "$KEY" "$REVOKE_DIR/$KEYNAME.pub"
chmod 644 "$REVOKE_DIR/$KEYNAME.pub"

CRL="$CA_DIR/revoked/revoked_keys"
touch "$CRL"
chmod 644 "$CRL"
cat "$KEY" >> "$CRL"

LOG_FILE="$CA_DIR/revoked/revocation.log"
echo "$(date -Iseconds) | $TYPE | $NAME | $KEYNAME" >> "$LOG_FILE"

echo ""
echo "Ключ отозван."
echo "Скопируйте $CRL на ноды как /etc/ssh/ca/revoked_keys"
echo "И добавьте в sshd_config: RevokedKeys /etc/ssh/ca/revoked_keys"
echo "Перезапустите sshd на всех нодах."
```

Создать файл:

```bash
sudo tee /usr/local/sshca/scripts/revoke-ssh.sh > /dev/null << 'EOF'
# (содержимое выше)
EOF
sudo chmod +x /usr/local/sshca/scripts/revoke-ssh.sh
```

### Шаг 14. Тест отзыва (опционально)

```bash
# На fbsd-ca-sel
sudo /usr/local/sshca/scripts/revoke-ssh.sh user avalok11 freebsd_lab
# Ввести passphrase

# Скопировать CRL на ноды
scp -i ~/.ssh/freebsd_lab /usr/local/sshca/revoked/revoked_keys avalok11@<PUBLIC_IP_FBSD_1_SEL>:/tmp/
ssh -i ~/.ssh/freebsd_lab avalok11@<PUBLIC_IP_FBSD_1_SEL> \
    "sudo cp /tmp/revoked_keys /etc/ssh/ca/revoked_keys && \
     sudo chmod 644 /etc/ssh/ca/revoked_keys && \
     sudo service sshd restart"
```

Проверить на Mac M4:

```bash
ssh fbsd-1-sel whoami
# Должен отказать: certificate revoked
```

Откатить:

```bash
# На fbsd-1-sel
sudo cp /dev/null /etc/ssh/ca/revoked_keys
sudo service sshd restart
```

## Тестирование

| Сценарий | Ожидаемый результат |
|---|---|
| `ssh fbsd-1-sel` с подписанным ключом | Вход без `-i`, ssh сам выберет сертификат |
| Подписать с TTL 1 минута, подождать | Через 2 минуты вход отклоняется |
| `ssh` на новую ноду с подписанным host-ключом | `Host key verification failed` НЕ появляется |
| Добавить ключ в CRL через `revoke-ssh.sh` | Вход отклоняется даже при валидном сертификате |
| Войти под `root` ключом, подписанным только для `avalok11` | Должно отказать (principal mismatch) |
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
