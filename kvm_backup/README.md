# 📺 macOS to Android TV Wireless KVM Bridge (Backup)

Поздравляем! Мы успешно отладили и запустили беспроводной KVM-мост для управления Android TV с трекпада и клавиатуры MacBook по Wi-Fi.

В этой папке сохранен бэкап двух полностью рабочих конфигураций.

---

## 🛠️ Конфигурация 1: Нативный KVM-мост на Swift (База для Mac App)
Этот код написан на Swift/Cocoa, работает нативно без внешних зависимостей и служит фундаментом для будущего полноценного macOS-приложения.

* **Файл исходного кода:** [tv_kvm.swift](file:///Users/user/.gemini/antigravity/scratch/MacTV_KVM/kvm_backup/tv_kvm.swift)
* **Скрипт компиляции и запуска:** [run_kvm.sh](file:///Users/user/.gemini/antigravity/scratch/MacTV_KVM/kvm_backup/run_kvm.sh)

### Как запустить из бэкапа:
Откройте Терминал и запустите:
```bash
bash /Users/user/.gemini/antigravity/scratch/MacTV_KVM/kvm_backup/run_kvm.sh
```

---

## 🚀 Конфигурация 2: Стелс-команда scrcpy (С нативной стрелочкой на ТВ)
Эта конфигурация использует официальный бинарник `scrcpy v4.0` в режиме `UHID` (виртуальной USB-мыши), который выводит **настоящую компьютерную стрелку-курсор** на телевизор из коробки и поддерживает жест «Назад» по тапу двумя пальцами.

### Команда для запуска в Терминале:
```bash
/Users/user/.gemini/antigravity/scratch/scrcpy-macos-x86_64-v4.0/scrcpy --tcpip=192.168.31.67:5555 --no-video-playback --window-borderless --always-on-top --window-x=1435 --window-y=0 --window-width=5 --window-height=900 --mouse=uhid --mouse-bind=bhsn
```

---

## 📁 Структура сохраненных файлов:
* `tv_kvm.swift` — исходный код нативного моста (добавлено автоматическое фоновое переподключение и пинг жизнедеятельности).
* `run_kvm.sh` — скрипт быстрой компиляции и запуска.
