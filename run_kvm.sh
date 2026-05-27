#!/bin/bash
cd /Users/user/.gemini/antigravity/scratch/MacTV_KVM

# IP-адрес вашего телевизора Google TV / Android TV
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
mkdir -p tv_kvm.app/Contents/MacOS
cp -f Info.plist tv_kvm.app/Contents/Info.plist

echo "===================================================="
echo " 🛠️ Компиляция нативного KVM-моста на Swift..."
echo "===================================================="
swiftc tv_kvm.swift -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker Info.plist -framework Speech -framework AVFoundation -o tv_kvm.app/Contents/MacOS/tv_kvm

if [ $? -ne 0 ]; then
  echo " ❌ Ошибка компиляции Swift-приложения."
  exit 1
fi

echo " 🛠️ Подпись бинарного файла KVM..."
codesign --force --sign - tv_kvm.app/Contents/MacOS/tv_kvm
echo " 🛠️ Подпись бандла KVM..."
codesign --force --sign - tv_kvm.app

echo "===================================================="
echo " 🚀 Запуск KVM-моста на базе Google TV Remote V2..."
echo " Нажмите Ctrl+C в этом окне для выключения программы."
echo "===================================================="

# Запуск фонового Node.js-моста
node tv_remote_bridge.js "$TV_IP" &
NODE_PID=$!

# Запуск Swift-клиента из бандла
./tv_kvm.app/Contents/MacOS/tv_kvm &
SWIFT_PID=$!

# Функция автоматической очистки процессов при прерывании
cleanup() {
  echo ""
  echo " 🛑 Завершение работы процессов KVM..."
  kill $NODE_PID 2>/dev/null
  kill $SWIFT_PID 2>/dev/null
  killall tv_kvm 2>/dev/null
  echo " 💤 Все процессы успешно остановлены. До свидания!"
  exit 0
}

# Ловушка для Ctrl+C (SIGINT) и закрытия терминала (SIGTERM, EXIT)
trap cleanup SIGINT SIGTERM EXIT

# Ожидаем завершения работы Swift-приложения
wait $SWIFT_PID
