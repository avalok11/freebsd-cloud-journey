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
