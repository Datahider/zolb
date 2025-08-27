#!/bin/sh

DIR="$(cd "$(dirname "$0")" && pwd)"
FILE="$DIR/zolb.sh"
TMP_FILE="$DIR/zolb.sh.tmp"

# Скачиваем новую версию во временный файл
fetch -o "$TMP_FILE" "https://raw.githubusercontent.com/Datahider/zolb/main/zolb.sh"

# Если старого файла нет, просто переименовываем
if [ ! -f "$FILE" ]; then
    mv "$TMP_FILE" "$FILE"
    chmod +x "$FILE"
    echo "zolb.sh установлен впервые."
    exit 0
fi

# Считаем sha256 для старого и нового файла
OLD_HASH=$(sha256 -q "$FILE")
NEW_HASH=$(sha256 -q "$TMP_FILE")

if [ "$OLD_HASH" != "$NEW_HASH" ]; then
    mv "$TMP_FILE" "$FILE"
    chmod +x "$FILE"
    echo "zolb.sh обновлен."
else
    rm "$TMP_FILE"
    echo "zolb.sh не изменился, обновление не требуется."
fi
