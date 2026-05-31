#!/bin/bash
cd /Users/user/.gemini/antigravity/scratch/MacTV_KVM

# IP-адрес вашего телевизора Google TV / Android TV (укажите конкретный IP или "auto" для автопоиска Bonjour)
TV_IP="192.168.31.67"

echo "===================================================="
echo " 🛠️ Проверка npm-зависимостей..."
echo "===================================================="
npm install --cache ./npm-cache

echo "===================================================="
echo " 🛠️ Применение патчей библиотеки androidtv-remote..."
echo "===================================================="
cp -f lib_patches/remote/remotemessage.proto node_modules/androidtv-remote/dist/remote/remotemessage.proto
cp -f lib_patches/remote/remotemessage.proto node_modules/androidtv-remote/src/remote/remotemessage.proto
cp -f lib_patches/remote/RemoteManager.js node_modules/androidtv-remote/dist/remote/RemoteManager.js
cp -f lib_patches/remote/RemoteManager.js node_modules/androidtv-remote/src/remote/RemoteManager.js
cp -f lib_patches/remote/RemoteMessageManager.js node_modules/androidtv-remote/dist/remote/RemoteMessageManager.js

echo "===================================================="
echo " 🛠️ Создание структуры macOS App Bundle..."
echo "===================================================="
mkdir -p Pano.app/Contents/MacOS
mkdir -p Pano.app/Contents/Resources
cp -f Info.plist Pano.app/Contents/Info.plist
cp -rf Resources/* Pano.app/Contents/Resources/

# Упаковываем Node.js мост и зависимости внутрь бандла для автономного запуска (Launchpad / /Applications)
mkdir -p Pano.app/Contents/Resources/bridge
cp -f tv_remote_bridge.js Pano.app/Contents/Resources/bridge/
cp -f package.json Pano.app/Contents/Resources/bridge/
cp -f package-lock.json Pano.app/Contents/Resources/bridge/
cp -rf .credentials Pano.app/Contents/Resources/bridge/ 2>/dev/null || true
cp -rf node_modules Pano.app/Contents/Resources/bridge/

echo "===================================================="
echo " 🛠️ Компиляция нативного KVM-моста на Swift..."
echo "===================================================="
swiftc Sources/App/*.swift Sources/Models/*.swift Sources/Services/*.swift Sources/UI/*.swift Sources/Tests/*.swift -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker Info.plist -framework Speech -framework AVFoundation -o Pano.app/Contents/MacOS/Pano

if [ $? -ne 0 ]; then
  echo " ❌ Ошибка компиляции Swift-приложения."
  exit 1
fi

echo " 🛠️ Подпись бинарного файла KVM..."
codesign --force --sign - --entitlements entitlements.plist Pano.app/Contents/MacOS/Pano
echo " 🛠️ Подпись бандла KVM..."
codesign --force --sign - --entitlements entitlements.plist Pano.app

echo "===================================================="
echo " 🚀 Запуск KVM-моста на базе Google TV Remote V2..."
echo " Нажмите Ctrl+C в этом окне для выключения программы."
echo "===================================================="

# Функция автоматической очистки процессов при прерывании
cleanup() {
  echo ""
  echo " 🛑 Завершение работы процессов KVM..."
  killall Pano 2>/dev/null
  killall -f "tv_remote_bridge.js" 2>/dev/null
  echo " 💤 Все процессы успешно остановлены. До свидания!"
  exit 0
}

# Ловушка для Ctrl+C (SIGINT) и закрытия терминала (SIGTERM, EXIT)
trap cleanup SIGINT SIGTERM EXIT

# Запуск приложения через LaunchServices (обязательно для запроса прав на микрофон macOS)
open -W Pano.app
