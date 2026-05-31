#!/bin/bash
# ==============================================================================
#  🚀 Скрипт подготовки релиза Pano для распространения через Homebrew
# ==============================================================================

cd /Users/user/.gemini/antigravity/scratch/MacTV_KVM

VERSION="1.0.0"
ZIP_NAME="pano.zip"
CASK_NAME="pano.rb"

echo "===================================================="
echo " 🧹 Очистка старых файлов сборки..."
echo "===================================================="
rm -rf Pano.app
rm -f "$ZIP_NAME"
rm -f "$CASK_NAME"

echo "===================================================="
echo " 🛠️ Сборка структуры macOS App Bundle..."
echo "===================================================="
mkdir -p Pano.app/Contents/MacOS
mkdir -p Pano.app/Contents/Resources
cp -f Info.plist Pano.app/Contents/Info.plist
cp -rf Resources/* Pano.app/Contents/Resources/

# Упаковка Node.js моста
mkdir -p Pano.app/Contents/Resources/bridge
cp -f tv_remote_bridge.js Pano.app/Contents/Resources/bridge/
cp -f package.json Pano.app/Contents/Resources/bridge/
cp -f package-lock.json Pano.app/Contents/Resources/bridge/
cp -rf node_modules Pano.app/Contents/Resources/bridge/

echo "===================================================="
echo " 🛠️ Компиляция нативного релиза на Swift..."
echo "===================================================="
swiftc Sources/App/*.swift Sources/Models/*.swift Sources/Services/*.swift Sources/UI/*.swift Sources/Tests/*.swift \
  -O -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker Info.plist \
  -framework Speech -framework AVFoundation \
  -o Pano.app/Contents/MacOS/Pano

if [ $? -ne 0 ]; then
  echo " ❌ Ошибка компиляции приложения."
  exit 1
fi

echo "===================================================="
echo " 🛠️ Подпись кода с правами доступа к микрофону..."
echo "===================================================="
codesign --force --sign - --entitlements entitlements.plist Pano.app/Contents/MacOS/Pano
codesign --force --sign - --entitlements entitlements.plist Pano.app

echo "===================================================="
echo " 📦 Архивация бандла в $ZIP_NAME..."
echo "===================================================="
zip -r -q "$ZIP_NAME" Pano.app

if [ $? -ne 0 ]; then
  echo " ❌ Ошибка архивации."
  exit 1
fi

echo "   ✅ Архив $ZIP_NAME успешно создан."

echo "===================================================="
echo " 💿 Создание образа диска Pano.dmg..."
echo "===================================================="
DMG_NAME="Pano.dmg"
rm -f "$DMG_NAME"

# Создаем временную директорию сборки DMG
DMG_TEMP_DIR="dmg_temp"
rm -rf "$DMG_TEMP_DIR"
mkdir -p "$DMG_TEMP_DIR"

# Копируем Pano.app туда
cp -R Pano.app "$DMG_TEMP_DIR/"

# Создаем симлинк на Applications
ln -s /Applications "$DMG_TEMP_DIR/Applications"

# Создаем сжатый образ диска (UDZO)
hdiutil create -volname "Pano" -srcfolder "$DMG_TEMP_DIR" -ov -format UDZO "$DMG_NAME"

# Очищаем временную директорию
rm -rf "$DMG_TEMP_DIR"

if [ $? -ne 0 ]; then
  echo " ❌ Ошибка создания DMG образа."
  exit 1
fi

echo "   ✅ Образ диска $DMG_NAME успешно создан."

echo "===================================================="
echo " 🧮 Вычисление SHA-256 хэша..."
echo "===================================================="
SHA256_HASH=$(shasum -a 256 "$ZIP_NAME" | awk '{print $1}')
echo "   SHA-256: $SHA256_HASH"

echo "===================================================="
echo " 📝 Генерация формулы Homebrew Cask ($CASK_NAME)..."
echo "===================================================="

cat <<EOF > "$CASK_NAME"
cask "pano" do
  version "$VERSION"
  sha256 "$SHA256_HASH"

  # Укажите здесь URL, куда вы загрузите созданный pano.zip
  # Например, GitHub Releases:
  url "https://github.com/ponano/androidtvremotemacos/releases/download/v#{version}/pano.zip"
  name "Pano"
  desc "macOS TV KVM client using Google TV Remote V2 protocol with smooth trackpad gestures and native voice input"
  homepage "https://github.com/ponano/androidtvremotemacos"

  app "Pano.app"

  zap trash: [
    "~/.tv_kvm_credentials",
    "~/Library/Logs/tv_kvm"
  ]
end
EOF

chmod +x "$CASK_NAME"

echo "===================================================="
echo " 🎉 Релизная сборка завершена успешно!"
echo "===================================================="
echo " 1. Загрузите файл '$ZIP_NAME' в релиз вашего репозитория."
echo " 2. Скопируйте сгенерированный файл '$CASK_NAME' в ваш Homebrew Tap."
echo " 3. Для локального тестирования установки выполните:"
echo "    brew install --cask ./$CASK_NAME"
echo "===================================================="
