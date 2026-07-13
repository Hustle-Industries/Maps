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

apply_target() {
    local name="$1" ak="$2" sk="$3" region="$4" endpoint="$5" bucket="$6" prefix="$7"
    if [ -z "$ak" ] || [ -z "$sk" ] || [ -z "$bucket" ] || [ -z "$endpoint" ]; then
        echo "[$name] пропуск — цель не сконфигурирована"
        return 0
    fi
    local p key
    if [ ${#UPLOAD[@]} -gt 0 ]; then
        for p in "${UPLOAD[@]}"; do
            key="${prefix}${p}"
            echo "[$name] up $key"
            AWS_ACCESS_KEY_ID="$ak" AWS_SECRET_ACCESS_KEY="$sk" AWS_DEFAULT_REGION="$region" \
                aws s3 cp "$p" "s3://${bucket}/${key}" --endpoint-url "$endpoint" --only-show-errors
        done
    fi
    if [ ${#DELETE[@]} -gt 0 ]; then
        for p in "${DELETE[@]}"; do
            key="${prefix}${p}"
            echo "[$name] rm $key"
            AWS_ACCESS_KEY_ID="$ak" AWS_SECRET_ACCESS_KEY="$sk" AWS_DEFAULT_REGION="$region" \
                aws s3 rm "s3://${bucket}/${key}" --endpoint-url "$endpoint" --only-show-errors || true
        done
    fi
}

if [ "$CHANGED" -gt 0 ]; then
    apply_target "Yandex" "${YC_ACCESS_KEY_ID:-}" "${YC_SECRET_ACCESS_KEY:-}" \
        "ru-central1" "https://storage.yandexcloud.net" "${YC_BUCKET:-}" "${YC_PREFIX:-}"
    apply_target "Bunny" "${BUNNY_STORAGE_ZONE:-}" "${BUNNY_PASSWORD:-}" \
        "${BUNNY_REGION:-de}" "${BUNNY_ENDPOINT:-}" "${BUNNY_STORAGE_ZONE:-}" "${BUNNY_PREFIX:-}"
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
