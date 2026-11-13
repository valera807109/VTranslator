#!/bin/bash
# Установка / обновление VTranslator одной командой:
#   curl -fsSL https://raw.githubusercontent.com/valera807109/VTranslator/main/scripts/install.sh | bash
# Файл, скачанный через curl, не получает пометку «из интернета», поэтому macOS не показывает предупреждение.
set -euo pipefail

APP_NAME="VTranslator"
APP="/Applications/${APP_NAME}.app"
URL="https://github.com/valera807109/VTranslator/releases/latest/download/${APP_NAME}.zip"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

echo "→ Скачиваю ${APP_NAME}…"
curl -fL --progress-bar "${URL}" -o "${TMP}/${APP_NAME}.zip"

echo "→ Распаковываю…"
ditto -x -k "${TMP}/${APP_NAME}.zip" "${TMP}"

# Закрываем запущенную копию перед обновлением.
pkill -x "${APP_NAME}" 2>/dev/null || true
sleep 1

echo "→ Устанавливаю в «Программы»…"
if [ -w /Applications ]; then
    rm -rf "${APP}"
    ditto "${TMP}/${APP_NAME}.app" "${APP}"
    xattr -cr "${APP}" 2>/dev/null || true
else
    echo "  Нужен пароль администратора:"
    sudo rm -rf "${APP}"
    sudo ditto "${TMP}/${APP_NAME}.app" "${APP}"
    sudo xattr -cr "${APP}" 2>/dev/null || true
fi

echo "✓ Готово! Запускаю ${APP_NAME}…"
open "${APP}"
echo
echo "Значок VTranslator появится в строке меню (вверху справа)."
echo "Не забудьте разрешить «Универсальный доступ», если macOS попросит."
