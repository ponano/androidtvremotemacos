#!/bin/bash
# ==============================================================================
#  🚀 Скрипт автоматической публикации проекта и Homebrew Cask на GitHub
# ==============================================================================

cd /Users/user/.gemini/antigravity/scratch/MacTV_KVM

echo "===================================================="
echo " 📤 1. Публикация исходного кода в репозиторий..."
echo "===================================================="
git remote remove origin 2>/dev/null
git remote add origin git@github.com:ponano/androidtvremotemacos.git

# Пробуем запушить через SSH
git push -u origin main

if [ $? -ne 0 ]; then
  echo "   ⚠️ SSH недоступен или репозиторий не найден. Пробуем через HTTPS..."
  git remote set-url origin https://github.com/ponano/androidtvremotemacos.git
  git push -u origin main
fi

if [ $? -ne 0 ]; then
  echo " ❌ Ошибка: Не удалось опубликовать основной проект. Проверьте права доступа и создание репозитория."
  exit 1
fi

echo "===================================================="
echo " 📤 2. Публикация формулы в Homebrew Tap (homebrew-pano)..."
echo "===================================================="

# Создаем временную директорию для клонирования тапа
TEMP_DIR=$(mktemp -d)

# Пробуем склонировать через SSH
git clone git@github.com:ponano/homebrew-pano.git "$TEMP_DIR" 2>/dev/null

if [ $? -ne 0 ]; then
  echo "   ⚠️ SSH недоступен для тапа. Пробуем через HTTPS..."
  git clone https://github.com/ponano/homebrew-pano.git "$TEMP_DIR"
fi

if [ $? -ne 0 ]; then
  echo " ❌ Ошибка: Не удалось склонировать репозиторий homebrew-pano."
  rm -rf "$TEMP_DIR"
  exit 1
fi

# Переходим во временную папку, создаем структуру и копируем формулу
cd "$TEMP_DIR"
mkdir -p Casks
cp -f /Users/user/.gemini/antigravity/scratch/MacTV_KVM/pano.rb Casks/pano.rb

# Добавляем, комитим и пушим формулу Cask
git add Casks/pano.rb
git commit -m "Add Pano Cask v1.0.0"
git branch -M main

# Пушим изменения
git push -u origin main

if [ $? -ne 0 ]; then
  echo " ❌ Ошибка: Не удалось отправить Cask-формулу на GitHub."
  rm -rf "$TEMP_DIR"
  exit 1
fi

# Очищаем временную папку
rm -rf "$TEMP_DIR"

echo "===================================================="
echo " 🎉 УСПЕХ: Все проекты успешно опубликованы на GitHub!"
echo "===================================================="
echo " Что нужно сделать вручную:"
echo " 1. Перейдите в репозиторий https://github.com/ponano/androidtvremotemacos"
echo " 2. Создайте релиз с тегом 'v1.0.0'"
echo " 3. Загрузите и прикрепите файл '/Users/user/.gemini/antigravity/scratch/MacTV_KVM/pano.zip' в ассеты этого релиза."
echo " 4. Готово! Пользователи смогут устанавливать приложение через:"
echo "    brew tap ponano/pano"
echo "    brew install --cask pano"
echo "===================================================="
