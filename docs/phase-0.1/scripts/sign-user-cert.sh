#!/bin/sh
# Подписать пользовательский публичный ключ.
# Использование: sign-user-cert.sh <pubkey> <principals> [ttl] [storage-user]
# Пример: sign-user-cert.sh /tmp/key.pub avalok11,root +8h:00
#
# <principals>     — список логинов в самом сертификате (ssh-keygen -n)
# [storage-user]   — имя каталога в /usr/local/sshca/users/, по умолчанию
#                    basename публичного ключа без .pub
#
# Скрипт НЕинтерактивный: раньше здесь был `read` с вопросом «Для какого
# пользователя подписываем?». На EOF (cron, Ansible, CI) `read` возвращает
# не-nonzero, и `set -e` ронял скрипт. Имя каталога и передаётся аргументом.

set -e

PUBKEY=$1
PRINCIPALS=$2
TTL=${3:-"+8h"}
CA_DIR="/usr/local/sshca"

if [ -z "$PUBKEY" ] || [ -z "$PRINCIPALS" ]; then
    echo "Использование: $0 <pubkey> <principals> [ttl] [storage-user]"
    echo "Пример: $0 /tmp/key.pub avalok11,root +8h:00"
    exit 1
fi

if [ ! -f "$PUBKEY" ]; then
    echo "Ошибка: файл $PUBKEY не найден"
    exit 1
fi

# Имя ключа из пути (последний компонент без .pub)
KEYNAME=$(basename "$PUBKEY" .pub)
USERNAME=${4:-"$KEYNAME"}

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
