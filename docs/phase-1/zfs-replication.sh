#!/bin/sh
# ZFS replication: master -> fbsd-2-sel (replica)
#
# Устанавливается на master'е в /usr/local/sbin/zfs-replication.sh.
# Запускается от root вручную или из cron (автоматизация — Фаза 4, Ansible).
#
# Master менялся: fbsd-1-sel (172.16.0.2) → fbsd-3-sel (172.16.0.5).
# Реплика осталась прежней: fbsd-2-sel (172.16.0.4).
#
# Схема доступа:
#   - приватный ключ zfs-repl лежит на master (/root/.ssh/zfs_repl), НЕ на ноутбуке:
#     from="172.16.0.5" в auth_principals/zfs-repl разрешает вход только с master,
#     и попытка запустить репликацию с Mac M4 будет отклонена на replica
#   - на replica работает сервисная учётка zfs-repl с force-command, который
#     ПОДМЕНЯЕТ любую команду клиента на `zfs receive -F zroot/tank/repl`
#   - sudo на replica не используется: права выданы через `zfs allow`
#   - TOTP на replica нет, вход по сертификату CA (principal=zfs-repl, TTL 52w)
#   - сертификат обязан лежать РЯДОМ с ключом: /root/.ssh/zfs_repl-cert.pub
#     (ssh ищет сертификат по шаблону <имя_ключа>-cert.pub; иначе предъявит
#     «голый» публичный ключ, и zfs-repl его не примет)

set -eu

# FreeBSD /bin/sh поддерживает pipefail (расширение, не POSIX). Нужен, чтобы
# ошибка в `zfs send` не осталась незамеченной: в конвейере без pipefail
# проверяется только код возврата последней команды (ssh).
set -o pipefail

DATASET="zroot/tank/data"
REPLICA="zfs-repl@172.16.0.4"
KEY="/root/.ssh/zfs_repl"
SNAP_TAG="repl"
STATE="/var/db/zfs-replication/last-snapshot"

umask 077

# --- 1. Последний снапшот на master -----------------------------------------
# Сортировка средствами ZFS (-s creation), а не через sort: в BSD sort нет
# sort -V, а обычная сортировка ставит repl-10 раньше repl-2.
LATEST=$(zfs list -t snapshot -H -s creation -o name -d 1 -r "$DATASET" \
    | grep "^${DATASET}@${SNAP_TAG}" \
    | tail -n 1)

if [ -z "$LATEST" ]; then
    echo "Ошибка: нет ни одного снапшота ${DATASET}@${SNAP_TAG}*" >&2
    exit 1
fi

echo "Последний локальный снапшот: $LATEST"

# --- 2. Выбор режима: полная отправка или инкремент -------------------------
# Источник истины для маркера — master. Спросить replica нельзя: force-command
# превращает любой запрос в `zfs receive`, вернуть список снапшотов не получится.
if [ -f "$STATE" ]; then
    PREV=$(cat "$STATE")
    if zfs list -t snapshot -H -o name "$PREV" >/dev/null 2>&1; then
        echo "Инкрементальная отправка: $PREV -> $LATEST"
        zfs send -i "$PREV" "$LATEST" \
            | ssh -i "$KEY" -o BatchMode=yes "$REPLICA"
    else
        # PREV удалён на master (например, чистили старые снапшоты руками) —
        # инкремент невозможен, отправляем полный поток.
        echo "Прежний снапшот $PREV не найден, отправляю полностью"
        zfs send "$LATEST" \
            | ssh -i "$KEY" -o BatchMode=yes "$REPLICA"
    fi
else
    echo "Первая отправка, полный поток: $LATEST"
    zfs send "$LATEST" \
        | ssh -i "$KEY" -o BatchMode=yes "$REPLICA"
fi

# ВАЖНО: после ssh НИЧЕГО не передаётся. Команда вида
#   `... | ssh zfs-repl@172.16.0.4 sudo zfs receive ...` НЕ РАБОТАЕТ —
# force-command подменяет команду целиком, и ssh отвечает «permission denied»
# на попытку zfs receive. Правильная форма — оставить только адрес узла.

# --- 3. Обновление маркера --------------------------------------------------
# Пишется только после успешной отправки: при ошибке ssh или zfs receive
# `set -e` прерывает скрипт, маркер остаётся прежним, и следующий запуск
# повторит ту же отправку.
install -d -m 700 "$(dirname "$STATE")"
echo "$LATEST" > "$STATE"

echo "Готово: $LATEST отправлен на $REPLICA"