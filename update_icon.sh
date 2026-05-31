#!/bin/bash
set -e

NEW_ICON="/Users/user/Downloads/Icon on transparent background.png"
WORKSPACE_DIR="/Users/user/.gemini/antigravity/scratch/MacTV_KVM"
ICONSET_DIR="$WORKSPACE_DIR/Resources/AppIcon.iconset"
ICNS_FILE="$WORKSPACE_DIR/Resources/AppIcon.icns"

echo "=== Обновление иконки приложения ==="
echo "Исходный файл: $NEW_ICON"

if [ ! -f "$NEW_ICON" ]; then
    echo "Ошибка: Файл $NEW_ICON не найден!"
    exit 1
fi

mkdir -p "$ICONSET_DIR"

echo "Шаг 1: Нарезка иконки под разные разрешения с помощью sips..."
sips -z 16 16 "$NEW_ICON" --out "$ICONSET_DIR/icon_16x16.png"
sips -z 32 32 "$NEW_ICON" --out "$ICONSET_DIR/icon_16x16@2x.png"
sips -z 32 32 "$NEW_ICON" --out "$ICONSET_DIR/icon_32x32.png"
sips -z 64 64 "$NEW_ICON" --out "$ICONSET_DIR/icon_32x32@2x.png"
sips -z 128 128 "$NEW_ICON" --out "$ICONSET_DIR/icon_128x128.png"
sips -z 256 256 "$NEW_ICON" --out "$ICONSET_DIR/icon_128x128@2x.png"
sips -z 256 256 "$NEW_ICON" --out "$ICONSET_DIR/icon_256x256.png"
sips -z 512 512 "$NEW_ICON" --out "$ICONSET_DIR/icon_256x256@2x.png"
sips -z 512 512 "$NEW_ICON" --out "$ICONSET_DIR/icon_512x512.png"
sips -z 1024 1024 "$NEW_ICON" --out "$ICONSET_DIR/icon_512x512@2x.png"

echo "Шаг 2: Компиляция iconset в файл .icns с помощью iconutil..."
iconutil -c icns "$ICONSET_DIR" --out "$ICNS_FILE"

echo "Шаг 3: Обновление иконки в уже собранных бандлах приложений..."
if [ -d "$WORKSPACE_DIR/Pano.app" ]; then
    echo "Обновление Pano.app..."
    cp -f "$ICNS_FILE" "$WORKSPACE_DIR/Pano.app/Contents/Resources/AppIcon.icns"
    touch "$WORKSPACE_DIR/Pano.app"
fi

# Сброс кэша иконок Finder
echo "Шаг 4: Сброс кэша Finder..."
killall Finder 2>/dev/null || true

echo "=== Готово! Иконка успешно обновлена! ==="
