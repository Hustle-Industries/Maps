#!/bin/bash
set -euo pipefail

MODE="${MODE:-diff}"
MSG_FILE="${MSG_FILE:-/tmp/tg-msg.html}"

UPLOAD=()
DELETE=()

if [ "$MODE" = "full" ]; then
    while IFS= read -r p; do [ -n "$p" ] && UPLOAD+=("$p"); done < <(git ls-files '*.map')
else
    BEFORE="${BEFORE:-}"
    AFTER="${AFTER:-HEAD}"
    EMPTY=$(git hash-object -t tree /dev/null)
    if [ -z "$BEFORE" ] || [ "$BEFORE" = "0000000000000000000000000000000000000000" ] \
       || ! git cat-file -e "${BEFORE}^{commit}" 2>/dev/null; then
        BEFORE="$EMPTY"
    fi
    while IFS=$'\t' read -r st path _; do
        [ -n "$st" ] || continue
        case "$st" in
            A|M) UPLOAD+=("$path") ;;
            D)   DELETE+=("$path") ;;
            *)   if [ -f "$path" ]; then UPLOAD+=("$path"); else DELETE+=("$path"); fi ;;
        esac
    done < <(git diff --name-status --no-renames "$BEFORE" "$AFTER" -- '*.map')
fi

CHANGED=$(( ${#UPLOAD[@]} + ${#DELETE[@]} ))
echo "MODE=$MODE  к загрузке: ${#UPLOAD[@]}, к удалению: ${#DELETE[@]}"
if [ -n "${GITHUB_OUTPUT:-}" ]; then echo "changed=$CHANGED" >> "$GITHUB_OUTPUT"; fi

apply_yandex() {
    local ak="$1" sk="$2" bucket="$3" prefix="$4"
    if [ -z "$ak" ] || [ -z "$sk" ] || [ -z "$bucket" ]; then
        echo "[Yandex] пропуск — не сконфигурировано"
        return 0
    fi
    export AWS_ACCESS_KEY_ID="$ak" AWS_SECRET_ACCESS_KEY="$sk" AWS_DEFAULT_REGION="ru-central1"
    local ep="https://storage.yandexcloud.net"
    local p key
    if [ ${#UPLOAD[@]} -gt 0 ]; then
        for p in "${UPLOAD[@]}"; do
            key="${prefix}${p}"
            echo "[Yandex] up $key"
            aws s3 cp "$p" "s3://${bucket}/${key}" --endpoint-url "$ep" --only-show-errors
        done
    fi
    if [ ${#DELETE[@]} -gt 0 ]; then
        for p in "${DELETE[@]}"; do
            key="${prefix}${p}"
            echo "[Yandex] rm $key"
            aws s3 rm "s3://${bucket}/${key}" --endpoint-url "$ep" --only-show-errors || true
        done
    fi
}

apply_bunny() {
    local host="$1" zone="$2" pass="$3" prefix="$4"
    if [ -z "$host" ] || [ -z "$zone" ] || [ -z "$pass" ]; then
        echo "[Bunny] пропуск — не сконфигурировано"
        return 0
    fi
    host="${host#http://}"; host="${host#https://}"; host="${host%%/*}"
    local p key url
    if [ ${#UPLOAD[@]} -gt 0 ]; then
        for p in "${UPLOAD[@]}"; do
            key="${prefix}${p}"
            url="https://${host}/${zone}/${key}"
            echo "[Bunny] up $key"
            if ! curl -sfS --retry 2 -X PUT "$url" \
                    -H "AccessKey: ${pass}" \
                    -H "Content-Type: application/octet-stream" \
                    --data-binary @"$p" >/dev/null; then
                echo "[Bunny] ОШИБКА загрузки. Проверь BUNNY_HOSTNAME (storage-хост, напр. storage.bunnycdn.com, без https:// и без .b-cdn.net) и BUNNY_STORAGE_ZONE/BUNNY_PASSWORD." >&2
                exit 1
            fi
        done
    fi
    if [ ${#DELETE[@]} -gt 0 ]; then
        for p in "${DELETE[@]}"; do
            key="${prefix}${p}"
            url="https://${host}/${zone}/${key}"
            echo "[Bunny] rm $key"
            curl -s -X DELETE "$url" -H "AccessKey: ${pass}" >/dev/null || true
        done
    fi
}

if [ "$CHANGED" -gt 0 ]; then
    apply_yandex "${YC_ACCESS_KEY_ID:-}" "${YC_SECRET_ACCESS_KEY:-}" "${YC_BUCKET:-}" "${YC_PREFIX:-}"
    apply_bunny "${BUNNY_HOSTNAME:-storage.bunnycdn.com}" "${BUNNY_STORAGE_ZONE:-}" "${BUNNY_PASSWORD:-}" "${BUNNY_PREFIX:-}"
fi

{
    echo "🗺 <b>Карты синхронизированы</b>"
    if [ ${#UPLOAD[@]} -gt 0 ]; then
        echo ""
        echo "⬆️ <b>Загружено (${#UPLOAD[@]}):</b>"
        for p in "${UPLOAD[@]}"; do echo "• <code>${p}</code>"; done
    fi
    if [ ${#DELETE[@]} -gt 0 ]; then
        echo ""
        echo "🗑 <b>Удалено (${#DELETE[@]}):</b>"
        for p in "${DELETE[@]}"; do echo "• <code>${p}</code>"; done
    fi
    if [ "$CHANGED" -eq 0 ]; then echo ""; echo "<i>Изменений .map нет.</i>"; fi
} > "$MSG_FILE"

echo "=== Готово ($CHANGED изменений) ==="
