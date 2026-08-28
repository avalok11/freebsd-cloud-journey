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
