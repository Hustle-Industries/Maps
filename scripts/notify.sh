#!/bin/bash
set -u

MSG_FILE="${1:?usage: notify.sh <msg-file>}"

if [ -z "${TG_TOKEN:-}" ] || [ -z "${TG_CHATS:-}" ]; then
    echo "[notify] TG_TOKEN/TG_CHATS не заданы — пропуск" >&2
    exit 0
fi
if [ ! -s "$MSG_FILE" ]; then
    echo "[notify] пустое сообщение — пропуск" >&2
    exit 0
fi

MSG=$(cat "$MSG_FILE")
IFS=', ' read -ra CHATS <<< "$TG_CHATS"
for chat in "${CHATS[@]}"; do
    [ -n "$chat" ] || continue
    curl -s --max-time 15 -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
        -d chat_id="$chat" \
        -d parse_mode=HTML \
        -d disable_web_page_preview=true \
        --data-urlencode text="$MSG" >/dev/null \
        || echo "[notify] не доставлено -> $chat" >&2
done
exit 0
