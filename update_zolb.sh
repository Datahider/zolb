#!/bin/sh

DIR="$(cd "$(dirname "$0")" && pwd)"
FILE="$DIR/zolb.sh"
TMP_FILE="$DIR/zolb.sh.tmp"

# Скачиваем последнюю версию релиза во временный файл
fetch -o "$TMP_FILE" -q "https://github.com/Datahider/zolb/releases/latest/download/zolb.sh"

# Если старого файла нет, просто переименовываем
if [ ! -f "$FILE" ]; then
    mv "$TMP_FILE" "$FILE"
    chmod +x "$FILE"
    echo "zolb.sh установлен впервые."
    exit 0
fi

# Проверяем хэш, чтобы заменить только при изменении
if ! cmp -s "$FILE" "$TMP_FILE"; then
    mv "$TMP_FILE" "$FILE"
    chmod +x "$FILE"
    echo "zolb.sh обновлен."
else
    rm "$TMP_FILE"
    echo "zolb.sh не изменился, обновление не требуется."
fi
