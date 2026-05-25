import Cocoa
import Foundation
import AppKit

// ==========================================
#if true
// Виртуальное разрешение экрана вашего телевизора (обычно FullHD 1920x1080)
let TV_WIDTH = 1920.0
let TV_HEIGHT = 1080.0
// Ширина невидимой активной зоны управления при захвате
let CAPTURE_ZONE_WIDTH = 400.0
#endif
// ==========================================

class KVMView: NSView {
    var isActive = false
    var tvX = 960
    var tvY = 540
    var adbProcess: Process?
    var stdinPipe: Pipe?
    
    var macWidth = 1440.0
    var macHeight = 900.0
    
    var keepAliveTimer: Timer?
    var isReconnecting = false
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        
        // Автоматически определяем разрешение вашего экрана Mac
        if let screenFrame = NSScreen.main?.frame {
            macWidth = Double(screenFrame.width)
            macHeight = Double(screenFrame.height)
        }
        
        // Создаем область отслеживания курсора мыши
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        
        // Устанавливаем соединение с телевизором
        connectTV()
    }
    
    func findADB() -> String {
        // Пытаемся автоматически найти, где в системе лежит adb
        let which = Process()
        which.launchPath = "/usr/bin/which"
        which.arguments = ["adb"]
        
        let pipe = Pipe()
        which.standardOutput = pipe
        which.launch()
        which.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
            return path
        }
        return "/usr/local/bin/adb"
    }
    
    func connectTV() {
        let adbPath = findADB()
        print("[KVM] Подключение к телевизору 192.168.31.67:5555...")
        
        // Подключаемся к телевизору по Wi-Fi
        let connect = Process()
        connect.launchPath = adbPath
        connect.arguments = ["connect", "192.168.31.67:5555"]
        connect.launch()
        connect.waitUntilExit()
        
        // Открываем постоянный шелл ADB
        adbProcess = Process()
        adbProcess?.launchPath = adbPath
        adbProcess?.arguments = ["shell"]
        
        stdinPipe = Pipe()
        adbProcess?.standardInput = stdinPipe
        
        // Вешаем обработчик разрыва связи на фоновый поток ADB
        adbProcess?.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.handleDisconnect()
            }
        }
        
        do {
            if #available(macOS 10.13, *) {
                try adbProcess?.run()
            } else {
                adbProcess?.launch()
            }
            print("[KVM] Соединение установлено! Готово к работе.")
            isReconnecting = false
            startKeepAlive()
        } catch {
            print("[KVM] Ошибка запуска шелла, пробуем переподключиться...")
            handleDisconnect()
        }
    }
    
    func startKeepAlive() {
        keepAliveTimer?.invalidate()
        // Каждые 30 секунд шлем невидимый пинг-клавишу, чтобы Wi-Fi сокет на ТВ не засыпал
        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.sendCmd("input keyevent 0")
        }
    }
    
    func handleDisconnect() {
        guard !isReconnecting else { return }
        isReconnecting = true
        keepAliveTimer?.invalidate()
        
        print("[KVM] Связь потеряна. Запущен фоновый режим авто-подключения к ТВ...")
        
        // Каждые 5 секунд пытаемся тихо вернуть соединение в фоне
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] timer in
            guard let self = self else { return }
            print("[KVM] Попытка фонового подключения к ТВ...")
            
            let adbPath = self.findADB()
            let connect = Process()
            connect.launchPath = adbPath
            connect.arguments = ["connect", "192.168.31.67:5555"]
            connect.launch()
            connect.waitUntilExit()
            
            // Быстро опрашиваем adb devices, чтобы убедиться, что связь поднялась
            let check = Process()
            check.launchPath = adbPath
            check.arguments = ["devices"]
            let pipe = Pipe()
            check.standardOutput = pipe
            check.launch()
            check.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8), output.contains("192.168.31.67:5555") && output.contains("device") {
                print("[KVM] ТВ успешно вернулся в сеть!")
                timer.invalidate()
                self.connectTV()
            }
        }
    }
    
    func sendCmd(_ cmd: String) {
        if let data = (cmd + "\n").data(using: .utf8) {
            stdinPipe?.fileHandleForWriting.write(data)
        }
    }
    
    override func mouseEntered(with event: NSEvent) {
        if !isActive {
            isActive = true
            print("\n>>> РЕЖИМ УПРАВЛЕНИЯ ТВ АКТИВЕН (Трекпад захвачен) <<<")
            print("Для возврата на Mac проведите пальцем влево или нажмите Escape / Option.")
            
            // Расширяем невидимое окно до 400 пикселей для свободного движения пальцем
            if let window = self.window {
                let rect = NSRect(x: macWidth - CAPTURE_ZONE_WIDTH, y: 0, width: CAPTURE_ZONE_WIDTH, height: macHeight)
                window.setFrame(rect, display: true, animate: false)
            }
            
            // Удерживаем клавиатурный фокус на нашем окне
            self.window?.makeFirstResponder(self)
            
            // Скрываем курсор на Макбуке
            NSCursor.hide()
        }
    }
    
    func exitTVMode() {
        if isActive {
            isActive = false
            print("<<< ВОЗВРАТ НА MAC <<<\n")
            
            // Сжимаем окно обратно в невидимую 5-пиксельную нить на самом краю
            if let window = self.window {
                let rect = NSRect(x: macWidth - 5.0, y: 0, width: 5.0, height: macHeight)
                window.setFrame(rect, display: true, animate: false)
            }
            
            // Показываем курсор обратно на Макбуке
            NSCursor.unhide()
        }
    }
    
    override func mouseMoved(with event: NSEvent) {
        guard isActive else { return }
        
        // Получаем локальные координаты мыши внутри нашего окна
        let localPoint = self.convert(event.locationInWindow, from: nil)
        
        // Если палец ушел влево за пределы зоны захвата (меньше 15 пикселей) — возвращаемся на Mac
        if localPoint.x < 15.0 {
            exitTVMode()
            return
        }
        
        // Масштабируем координаты Mac на экран телевизора
        let relX = (localPoint.x - 15.0) / (CAPTURE_ZONE_WIDTH - 15.0)
        let relY = localPoint.y / macHeight
        
        tvX = Int(relX * TV_WIDTH)
        // В macOS Y-координата идет снизу вверх, а в Android сверху вниз — переворачиваем её
        tvY = Int((1.0 - relY) * TV_HEIGHT)
        
        tvX = max(0, min(Int(TV_WIDTH), tvX))
        tvY = max(0, min(Int(TV_HEIGHT), tvY))
        
        // Отправляем плавное скольжение курсора через touchscreen
        sendCmd("input touchscreen swipe \(tvX) \(tvY) \(tvX) \(tvY) 5")
    }
    
    override func mouseDown(with event: NSEvent) {
        guard isActive else { return }
        print("[KVM] Клик: X=\(tvX), Y=\(tvY)")
        sendCmd("input tap \(tvX) \(tvY)")
    }
    
    override func rightMouseDown(with event: NSEvent) {
        guard isActive else { return }
        print("[KVM] Нажатие «Назад»")
        sendCmd("input keyevent 4")
    }
    
    override func scrollWheel(with event: NSEvent) {
        guard isActive else { return }
        
        // Сглаживаем скролл трекпада Mac: свайпим на ТВ вверх или вниз на 150 пикселей
        let direction = event.deltaY > 0 ? 1 : -1
        let startY = tvY
        var endY = tvY + (direction * 150)
        endY = max(0, min(Int(TV_HEIGHT), endY))
        
        print("[KVM] Прокрутка: \(direction > 0 ? "Вверх" : "Вниз")")
        sendCmd("input touchscreen swipe \(tvX) \(startY) \(tvX) \(endY) 150")
    }
    
    override func keyDown(with event: NSEvent) {
        guard isActive else { return }
        
        // Escape (код 53) или Option (Alt) — мгновенный выход на Mac
        if event.keyCode == 53 || event.modifierFlags.contains(.option) {
            exitTVMode()
            return
        }
        
        // Backspace (код 51) — это кнопка «Назад» на ТВ
        if event.keyCode == 51 {
            sendCmd("input keyevent 4")
            return
        }
    }
    
    override var acceptsFirstResponder: Bool { return true }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Считываем размер экрана
        var screenWidth = 1440.0
        var screenHeight = 900.0
        if let screenFrame = NSScreen.main?.frame {
            screenWidth = Double(screenFrame.width)
            screenHeight = Double(screenFrame.height)
        }
        
        // Создаем абсолютно прозрачное и невидимое безрамочное окно на краю экрана
        let initialRect = NSRect(x: screenWidth - 5.0, y: 0, width: 5.0, height: screenHeight)
        window = NSWindow(
            contentRect: initialRect,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        // Устанавливаем приоритет поверх всех окон и статус-бара
        window.level = .statusBar
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true // Разрешаем отслеживание перемещений мыши!
        window.makeKeyAndOrderFront(nil)
        
        // Подключаем наш перехватчик событий
        let kvmView = KVMView(frame: NSRect(x: 0, y: 0, width: CAPTURE_ZONE_WIDTH, height: screenHeight))
        window.contentView = kvmView
        window.makeFirstResponder(kvmView)
        
        // Делаем иконку программы скрытой из Дока, чтобы не мешала
        NSApp.setActivationPolicy(.accessory)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
