import Cocoa
import Foundation
import AppKit
import Network

// ==========================================
// Ширина триггерной зоны захвата на краю экрана (окно больше не расширяется, исключая пересечение полей)
let INITIAL_ZONE_WIDTH = 8.0
// Порог накопления движения (пиксели) для фиксации одного шага D-pad (свайпа) - увеличен для исключения резкости
let SWIPE_THRESHOLD = 40.0
// Порог накопления прокрутки для фиксации одного шага D-pad (увеличен для плавной дискретной прокрутки)
let SCROLL_THRESHOLD = 15.0
// ==========================================

enum KVMEdge: String {
    case right = "RIGHT"
    case left = "LEFT"
    case top = "TOP"
}

class SocketClient {
    var connection: NWConnection?
    var queue = DispatchQueue(label: "KVM_SocketQueue")
    var onStatusChange: ((String) -> Void)?
    
    func connect() {
        print("[Swift Socket] connect() called, starting NWConnection to 127.0.0.1:12345...")
        let host = NWEndpoint.Host("127.0.0.1")
        let port = NWEndpoint.Port(integerLiteral: 12345)
        
        connection = NWConnection(host: host, port: port, using: .tcp)
        connection?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("[Swift Socket] Connected to local TV KVM bridge.")
                self?.receive()
            case .failed(let error):
                print("[Swift Socket] Connection failed: \(error). Reconnecting...")
                self?.reconnect()
            case .waiting(let error):
                print("[Swift Socket] Connection waiting: \(error). Retrying in 3 seconds...")
                self?.reconnect()
            case .cancelled:
                print("[Swift Socket] Connection cancelled.")
            default:
                break
            }
        }
        connection?.start(queue: queue)
    }
    
    func disconnect() {
        connection?.cancel()
        connection = nil
    }
    
    func reconnect() {
        disconnect()
        DispatchQueue.global().asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.connect()
        }
    }
    
    func send(cmd: String) {
        guard let connection = connection else { return }
        let data = (cmd + "\n").data(using: .utf8)!
        connection.send(content: data, completion: .contentProcessed({ error in
            if let error = error {
                print("[Swift Socket] Send error: \(error)")
            }
        }))
    }
    
    private func receive() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] data, _, isComplete, error in
            if let data = data, !data.isEmpty {
                if let str = String(data: data, encoding: .utf8) {
                    let lines = str.split(separator: "\n")
                    for line in lines {
                        self?.handleMessage(String(line))
                    }
                }
            }
            if error == nil && !isComplete {
                self?.receive()
            }
        }
    }
    
    private func handleMessage(_ msg: String) {
        let trimmed = msg.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("STATUS ") {
            let status = trimmed.replacingOccurrences(of: "STATUS ", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            onStatusChange?(status)
        }
    }
}

class KVMView: NSView {
    var isActive = false
    var activeEdge: KVMEdge = .right
    
    var macWidth = 1440.0
    var macHeight = 900.0
    
    var accumulatedX = 0.0
    var accumulatedY = 0.0
    var accumulatedScrollY = 0.0
    var lastKeySentTime = Date()
    var lastScrollGestureTime = Date()
    var lastScrollKeyTime = Date()
    var activationTimer: Timer?
    
    private var trackingArea: NSTrackingArea?
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        
        // Автоматически определяем разрешение вашего экрана Mac
        if let screenFrame = NSScreen.main?.frame {
            macWidth = Double(screenFrame.width)
            macHeight = Double(screenFrame.height)
        }
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        
        let newArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(newArea)
        trackingArea = newArea
    }
    
    func sendKey(_ key: String) {
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.socketClient.send(cmd: "KEY \(key)")
        }
    }
    
    func sendNavKey(_ key: String) {
        let now = Date()
        // Кулдаун 120 мс между командами навигации для идеальной плавности без дрифта фокуса
        if now.timeIntervalSince(lastKeySentTime) >= 0.12 {
            sendKey(key)
            lastKeySentTime = now
        }
    }
    
    override func mouseEntered(with event: NSEvent) {
        if !isActive {
            // Отменяем любой предыдущий таймер на всякий случай
            activationTimer?.invalidate()
            
            // Запускаем таймер задержки на 0.8 секунды (800 мс).
            // Если мышь останется прижатой к выбранному краю в течение этого времени, включится режим ТВ.
            // Это идеальная защита от случайных уходов курсора при скроллинге или кликах на Mac.
            activationTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                self.enterTVMode()
            }
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        // Если мышь покинула триггерную зону ДО того, как истекли 450 мс,
        // мы просто отменяем таймер. Режим KVM не включится!
        if !isActive {
            activationTimer?.invalidate()
            activationTimer = nil
        }
    }
    
    func enterTVMode() {
        guard !isActive else { return }
        isActive = true
        print("\n>>> РЕЖИМ УПРАВЛЕНИЯ ТВ АКТИВЕН (Трекпад захвачен) <<<")
        print("Для возврата на Mac проведите пальцем влево или нажмите Escape / Option.")
        
        accumulatedX = 0.0
        accumulatedY = 0.0
        
        // Временно переключаем активационную политику приложения на .regular.
        // Без этого операционная система блокирует фокус ввода (key window) для фоновых агентов (.accessory),
        // из-за чего клавиатура и ввод текста не перехватывались.
        NSApp.setActivationPolicy(.regular)
        
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            self.window?.makeKeyAndOrderFront(nil)
            self.window?.makeFirstResponder(self)
        }
        
        // Скрываем курсор на Макбуке
        NSCursor.hide()
    }
    
    func exitTVMode() {
        if isActive {
            isActive = false
            print("<<< ВОЗВРАТ НА MAC <<<\n")
            
            accumulatedX = 0.0
            accumulatedY = 0.0
            accumulatedScrollY = 0.0
            
            // Перемещаем курсор мыши внутрь экрана Mac (на 50 пикселей от триггерной зоны)
            // в зависимости от выбранного края перехода, чтобы избежать моментального авто-захвата
            let exitPoint: CGPoint
            switch activeEdge {
            case .right:
                exitPoint = CGPoint(x: macWidth - 50.0, y: macHeight / 2.0)
            case .left:
                exitPoint = CGPoint(x: 50.0, y: macHeight / 2.0)
            case .top:
                exitPoint = CGPoint(x: macWidth / 2.0, y: 50.0) // Y=0 верх в Core Graphics, смещаемся на 50 пикселей вниз
            }
            CGWarpMouseCursorPosition(exitPoint)
            
            // Показываем курсор обратно на Макбуке
            NSCursor.unhide()
            
            // Возвращаем активационную политику обратно на .accessory, убирая иконку из Дока,
            // и возвращаем клавиатурный фокус предыдущей активной программе на Mac
            NSApp.deactivate()
            NSApp.setActivationPolicy(.accessory)
        }
    }
    
    override func mouseMoved(with event: NSEvent) {
        guard isActive else { return }
        
        // Накапливаем относительные дельты аппаратного сдвига мыши/трекпада
        accumulatedX += Double(event.deltaX)
        
        let now = Date()
        let timeSinceLastScroll = now.timeIntervalSince(lastScrollGestureTime)
        
        // Если пользователь скроллит двумя пальцами (последний скролл был менее 0.3 сек назад),
        // мы полностью блокируем обработку вертикальных свайпов в mouseMoved.
        // Это предотвращает "двоение" команд и резкие хаотичные прыжки фокуса.
        if timeSinceLastScroll >= 0.3 {
            accumulatedY += Double(event.deltaY)
        } else {
            accumulatedY = 0.0
        }
        
        // Условия возврата на Mac на основе активной стороны KVM (требуется сдвиг >= 120 пикселей в противоположную сторону)
        switch activeEdge {
        case .right:
            if accumulatedX <= -120.0 { // Движение влево для выхода
                exitTVMode()
                return
            }
        case .left:
            if accumulatedX >= 120.0 { // Движение вправо для выхода
                exitTVMode()
                return
            }
        case .top:
            if accumulatedY >= 120.0 { // Движение вниз для выхода (deltaY > 0)
                exitTVMode()
                return
            }
        }
        
        // Обработка горизонтального свайпа с сохранением остатка дельты для плавной непрерывной навигации
        if abs(accumulatedX) >= SWIPE_THRESHOLD {
            if accumulatedX > 0 {
                sendNavKey("KEYCODE_DPAD_RIGHT")
                accumulatedX -= SWIPE_THRESHOLD
            } else {
                sendNavKey("KEYCODE_DPAD_LEFT")
                accumulatedX += SWIPE_THRESHOLD
            }
        }
        
        // Обработка вертикального свайпа с сохранением остатка дельты
        if abs(accumulatedY) >= SWIPE_THRESHOLD {
            if accumulatedY > 0 {
                sendNavKey("KEYCODE_DPAD_DOWN")
                accumulatedY -= SWIPE_THRESHOLD
            } else {
                sendNavKey("KEYCODE_DPAD_UP")
                accumulatedY += SWIPE_THRESHOLD
            }
        }
        
        // Удерживаем курсор мыши строго по центру нашей триггерной полоски захвата.
        // Это блокирует курсор от вылета на рабочий стол Mac и случайных кликов,
        // позволяя считывать бесконечное плавное скольжение по трекпаду.
        let centerPoint: CGPoint
        switch activeEdge {
        case .right:
            centerPoint = CGPoint(x: macWidth - (INITIAL_ZONE_WIDTH / 2.0), y: macHeight / 2.0)
        case .left:
            centerPoint = CGPoint(x: INITIAL_ZONE_WIDTH / 2.0, y: macHeight / 2.0)
        case .top:
            centerPoint = CGPoint(x: macWidth / 2.0, y: INITIAL_ZONE_WIDTH / 2.0)
        }
        CGWarpMouseCursorPosition(centerPoint)
    }
    
    override func mouseDown(with event: NSEvent) {
        guard isActive else { return }
        print("[KVM] Клик: Выбор (DPAD CENTER)")
        sendKey("KEYCODE_DPAD_CENTER")
    }
    
    override func rightMouseDown(with event: NSEvent) {
        guard isActive else { return }
        print("[KVM] Правый клик: Назад (KEYCODE_BACK)")
        sendKey("KEYCODE_BACK")
    }
    
    override func scrollWheel(with event: NSEvent) {
        guard isActive else { return }
        
        let now = Date()
        lastScrollGestureTime = now // Фиксируем время физического жеста скроллинга при каждом входящем событии прокрутки
        
        accumulatedScrollY += Double(event.deltaY)
        
        // Лимитируем максимальное накопление (не более 3 шагов), чтобы избежать "инерционного перелета"
        // после того, как пользователь уже убрал пальцы с трекпада
        let maxAccumulated = SCROLL_THRESHOLD * 3.0
        if accumulatedScrollY > maxAccumulated {
            accumulatedScrollY = maxAccumulated
        } else if accumulatedScrollY < -maxAccumulated {
            accumulatedScrollY = -maxAccumulated
        }
        
        if abs(accumulatedScrollY) >= SCROLL_THRESHOLD {
            // Мягкий кулдаун отправки команд прокрутки списков на ТВ (150 мс)
            // Это идеальная частота для автоповтора команд на Android TV
            if now.timeIntervalSince(lastScrollKeyTime) >= 0.15 {
                if accumulatedScrollY > 0 {
                    sendKey("KEYCODE_DPAD_UP")
                    accumulatedScrollY -= SCROLL_THRESHOLD
                } else {
                    sendKey("KEYCODE_DPAD_DOWN")
                    accumulatedScrollY += SCROLL_THRESHOLD
                }
                lastScrollKeyTime = now
            }
        }
    }
    
    override func keyDown(with event: NSEvent) {
        guard isActive else { return }
        
        // Escape (код 53) или Option (Alt) — мгновенный выход на Mac
        if event.keyCode == 53 || event.modifierFlags.contains(.option) {
            exitTVMode()
            return
        }
        
        // Управление громкостью ТВ: Control + Shift + Стрелка Вверх (громче) / Стрелка Вниз (тише)
        // Это гарантированно не занято Mission Control в macOS и на 100% свободно
        if event.modifierFlags.contains(.control) && event.modifierFlags.contains(.shift) {
            if event.keyCode == 126 { // Control + Shift + Стрелка Вверх
                sendKey("KEYCODE_VOLUME_UP")
                return
            }
            if event.keyCode == 125 { // Control + Shift + Стрелка Вниз
                sendKey("KEYCODE_VOLUME_DOWN")
                return
            }
        }
        
        // Backspace (код 51)
        if event.keyCode == 51 {
            if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) {
                // Command + Backspace или Control + Backspace — действие "Назад" (KEYCODE_BACK)
                sendKey("KEYCODE_BACK")
            } else {
                // Обычный Backspace — стирание текста (KEYCODE_DEL)
                sendKey("KEYCODE_DEL")
            }
            return
        }
        
        // Enter (код 36) или Numpad Enter (код 76)
        if event.keyCode == 36 || event.keyCode == 76 {
            sendKey("KEYCODE_ENTER")
            return
        }
        
        // Стрелочки клавиатуры для дублирования навигации
        if event.keyCode == 126 { sendNavKey("KEYCODE_DPAD_UP"); return }
        if event.keyCode == 125 { sendNavKey("KEYCODE_DPAD_DOWN"); return }
        if event.keyCode == 123 { sendNavKey("KEYCODE_DPAD_LEFT"); return }
        if event.keyCode == 124 { sendNavKey("KEYCODE_DPAD_RIGHT"); return }
        
        // Обработка текстового набора букв
        if let chars = event.characters, !chars.isEmpty {
            for char in chars {
                let charStr = String(char).uppercased()
                if let keyCode = mapCharToKeyCode(charStr) {
                    sendKey(keyCode)
                }
            }
        }
    }
    
    func mapCharToKeyCode(_ char: String) -> String? {
        let mapping: [String: String] = [
            "A": "KEYCODE_A", "B": "KEYCODE_B", "C": "KEYCODE_C", "D": "KEYCODE_D",
            "E": "KEYCODE_E", "F": "KEYCODE_F", "G": "KEYCODE_G", "H": "KEYCODE_H",
            "I": "KEYCODE_I", "J": "KEYCODE_J", "K": "KEYCODE_K", "L": "KEYCODE_L",
            "M": "KEYCODE_M", "N": "KEYCODE_N", "O": "KEYCODE_O", "P": "KEYCODE_P",
            "Q": "KEYCODE_Q", "R": "KEYCODE_R", "S": "KEYCODE_S", "T": "KEYCODE_T",
            "U": "KEYCODE_U", "V": "KEYCODE_V", "W": "KEYCODE_W", "X": "KEYCODE_X",
            "Y": "KEYCODE_Y", "Z": "KEYCODE_Z",
            "0": "KEYCODE_0", "1": "KEYCODE_1", "2": "KEYCODE_2", "3": "KEYCODE_3",
            "4": "KEYCODE_4", "5": "KEYCODE_5", "6": "KEYCODE_6", "7": "KEYCODE_7",
            "8": "KEYCODE_8", "9": "KEYCODE_9",
            " ": "KEYCODE_SPACE", ".": "KEYCODE_PERIOD", ",": "KEYCODE_COMMA",
            "-": "KEYCODE_MINUS", "=": "KEYCODE_EQUALS", "/": "KEYCODE_SLASH"
        ]
        
        // Русская раскладка QWERTY: маппинг в латинские клавиши для встроенного транслятора Android TV
        let cyrillicMapping: [String: String] = [
            "Ф": "KEYCODE_A", "И": "KEYCODE_B", "С": "KEYCODE_C", "В": "KEYCODE_D",
            "У": "KEYCODE_E", "А": "KEYCODE_F", "П": "KEYCODE_G", "Р": "KEYCODE_H",
            "Ш": "KEYCODE_I", "О": "KEYCODE_J", "Л": "KEYCODE_K", "Д": "KEYCODE_L",
            "Ь": "KEYCODE_M", "Т": "KEYCODE_N", "Щ": "KEYCODE_O", "З": "KEYCODE_P",
            "Й": "KEYCODE_Q", "К": "KEYCODE_R", "Ы": "KEYCODE_S", "Е": "KEYCODE_T",
            "Г": "KEYCODE_U", "М": "KEYCODE_V", "Ц": "KEYCODE_W", "Ч": "KEYCODE_X",
            "Н": "KEYCODE_Y", "Я": "KEYCODE_Z",
            "Б": "KEYCODE_COMMA", "Ю": "KEYCODE_PERIOD", "Х": "KEYCODE_LEFT_BRACKET",
            "Ъ": "KEYCODE_RIGHT_BRACKET", "Ж": "KEYCODE_SEMICOLON", "Э": "KEYCODE_APOSTROPHE",
            "Ё": "KEYCODE_GRAVE"
        ]
        
        if let key = mapping[char] {
            return key
        }
        if let key = cyrillicMapping[char] {
            return key
        }
        return nil
    }
    
    override var acceptsFirstResponder: Bool { return true }
}

class KVMWindow: NSWindow {
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return true }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var statusItem: NSStatusItem!
    var socketClient = SocketClient()
    var lastStatus: String = "DISCONNECTED"
    
    var kvmView: KVMView? {
        return window?.contentView as? KVMView
    }
    
    func updateWindowFrame() {
        guard let kvmView = self.kvmView else { return }
        
        var screenWidth = 1440.0
        var screenHeight = 900.0
        if let screenFrame = NSScreen.main?.frame {
            screenWidth = Double(screenFrame.width)
            screenHeight = Double(screenFrame.height)
        }
        
        let newRect: NSRect
        switch kvmView.activeEdge {
        case .right:
            newRect = NSRect(x: screenWidth - INITIAL_ZONE_WIDTH, y: 0, width: INITIAL_ZONE_WIDTH, height: screenHeight)
        case .left:
            newRect = NSRect(x: 0, y: 0, width: INITIAL_ZONE_WIDTH, height: screenHeight)
        case .top:
            newRect = NSRect(x: 0, y: screenHeight - INITIAL_ZONE_WIDTH, width: screenWidth, height: INITIAL_ZONE_WIDTH)
        }
        
        window?.setFrame(newRect, display: true)
        kvmView.frame = NSRect(x: 0, y: 0, width: newRect.width, height: newRect.height)
    }
    
    @objc func setEdgeToRight() { changeEdge(.right) }
    @objc func setEdgeToLeft() { changeEdge(.left) }
    @objc func setEdgeToTop() { changeEdge(.top) }
    
    func changeEdge(_ edge: KVMEdge) {
        kvmView?.activeEdge = edge
        UserDefaults.standard.set(edge.rawValue, forKey: "KVM_ActiveEdge")
        updateWindowFrame()
        updateStatusMenu(self.lastStatus)
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[Swift] applicationDidFinishLaunching started. Initializing window...")
        
        // Считываем сохраненную сторону KVM или берем по умолчанию .right
        var initialEdge: KVMEdge = .right
        if let savedRaw = UserDefaults.standard.string(forKey: "KVM_ActiveEdge"),
           let savedEdge = KVMEdge(rawValue: savedRaw) {
            initialEdge = savedEdge
        }
        
        // Создаем абсолютно прозрачное и невидимое безрамочное окно
        window = KVMWindow(
            contentRect: .zero,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = NSColor(red: 0, green: 0, blue: 0, alpha: 0.005)
        // Устанавливаем приоритет поверх всех окон и статус-бара
        window.level = .statusBar
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        
        // Подключаем наш перехватчик событий
        let kvmView = KVMView(frame: .zero)
        kvmView.activeEdge = initialEdge
        window.contentView = kvmView
        window.makeFirstResponder(kvmView)
        
        // Делаем иконку программы скрытой из Дока, чтобы не мешала
        NSApp.setActivationPolicy(.accessory)
        
        // Устанавливаем корректный фрейм триггерной зоны
        updateWindowFrame()
        
        // Настройка Меню в строке состояния (Menu Bar)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        // Колбэки сокета
        socketClient.onStatusChange = { [weak self] status in
            self?.updateStatusMenu(status)
        }
        
        // Стартуем локальный TCP-клиент
        socketClient.connect()
    }
    
    @objc func connectKVM() {
        print("[Swift] Sending CONNECT command to start connection...")
        socketClient.send(cmd: "CONNECT")
    }
    
    @objc func disconnectKVM() {
        print("[Swift] Sending DISCONNECT command to break connection...")
        socketClient.send(cmd: "DISCONNECT")
    }
    
    @objc func unpairKVM() {
        let alert = NSAlert()
        alert.messageText = "Разорвать сопряжение?"
        alert.informativeText = "Вы уверены, что хотите разорвать сопряжение с текущим телевизором и удалить сохраненные сертификаты?"
        alert.addButton(withTitle: "Забыть ТВ")
        alert.addButton(withTitle: "Отмена")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            print("[Swift] Sending UNPAIR command to delete credentials...")
            socketClient.send(cmd: "UNPAIR")
        }
    }
    
    @objc func startPairing() {
        print("[Swift] Sending CONNECT command to start pairing...")
        socketClient.send(cmd: "CONNECT")
    }
    
    @objc func terminate() {
        socketClient.send(cmd: "DISCONNECT")
        socketClient.disconnect()
        NSApp.terminate(nil)
    }
    
    func updateStatusMenu(_ status: String) {
        self.lastStatus = status
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Управляем видимостью триггерного окна на краю экрана:
            // Оно выводится на экран только при зеленом статусе READY (Подключен).
            // Во всех остальных состояниях (Отключен, Подключение, Ввод PIN)
            // триггерная область полностью скрывается, чтобы никак не мешать пользователю на Mac.
            if status == "READY" {
                self.window.makeKeyAndOrderFront(nil)
            } else {
                self.window.orderOut(nil)
                if let kvmView = self.window.contentView as? KVMView {
                    kvmView.exitTVMode()
                }
            }
            
            let menu = NSMenu()
            
            // Проверяем наличие ранее сохраненного TLS-сертификата сопряжения
            let currentDir = FileManager.default.currentDirectoryPath
            let certPath = "\(currentDir)/.credentials/cert.json"
            let hasCert = FileManager.default.fileExists(atPath: certPath)
            
            if let button = self.statusItem.button {
                switch status {
                case "READY":
                    button.title = "🟢 KVM: Подключен"
                    
                    // Меню при активном подключении
                    menu.addItem(NSMenuItem(title: "Отключить от ТВ", action: #selector(self.disconnectKVM), keyEquivalent: "d"))
                    menu.addItem(NSMenuItem(title: "Разорвать сопряжение (Забыть ТВ)", action: #selector(self.unpairKVM), keyEquivalent: "u"))
                    
                case "NEED_PIN":
                    button.title = "🟡 KVM: Введите PIN"
                    
                    // Меню при вводе PIN
                    menu.addItem(NSMenuItem(title: "Отменить сопряжение", action: #selector(self.disconnectKVM), keyEquivalent: "c"))
                    
                    self.promptForPIN { [weak self] pin in
                        self?.socketClient.send(cmd: "PIN \(pin)")
                    }
                    
                case "CONNECTING":
                    button.title = "🟡 KVM: Подключение..."
                    
                    // Меню при подключении
                    menu.addItem(NSMenuItem(title: "Отменить подключение", action: #selector(self.disconnectKVM), keyEquivalent: "c"))
                    
                default: // DISCONNECTED
                    button.title = "🔴 KVM: Отключен"
                    
                    if hasCert {
                        // Если сопряжение уже выполнено, даем кнопку подключения
                        menu.addItem(NSMenuItem(title: "Подключить к ТВ", action: #selector(self.connectKVM), keyEquivalent: "c"))
                        menu.addItem(NSMenuItem(title: "Разорвать сопряжение (Забыть ТВ)", action: #selector(self.unpairKVM), keyEquivalent: "u"))
                    } else {
                        // Если сопряжения еще нет, даем кнопку запуска сопряжения
                        menu.addItem(NSMenuItem(title: "Запустить сопряжение (Pairing)", action: #selector(self.startPairing), keyEquivalent: "p"))
                    }
                }
            }
            
            menu.addItem(NSMenuItem.separator())
            
            // Настройка подменю с выбором сторон
            let edgeMenu = NSMenu()
            
            let rightItem = NSMenuItem(title: "👉 Справа (по умолчанию)", action: #selector(self.setEdgeToRight), keyEquivalent: "")
            rightItem.state = (self.kvmView?.activeEdge == .right) ? .on : .off
            edgeMenu.addItem(rightItem)
            
            let leftItem = NSMenuItem(title: "👈 Слева", action: #selector(self.setEdgeToLeft), keyEquivalent: "")
            leftItem.state = (self.kvmView?.activeEdge == .left) ? .on : .off
            edgeMenu.addItem(leftItem)
            
            let topItem = NSMenuItem(title: "👆 Сверху", action: #selector(self.setEdgeToTop), keyEquivalent: "")
            topItem.state = (self.kvmView?.activeEdge == .top) ? .on : .off
            edgeMenu.addItem(topItem)
            
            let edgeMenuItem = NSMenuItem(title: "Сторона перехода на ТВ", action: nil, keyEquivalent: "")
            edgeMenuItem.submenu = edgeMenu
            menu.addItem(edgeMenuItem)
            
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Выйти из KVM", action: #selector(self.terminate), keyEquivalent: "q"))
            
            self.statusItem.menu = menu
        }
    }
    
    func promptForPIN(completion: @escaping (String) -> Void) {
        let alert = NSAlert()
        alert.messageText = "Сопряжение с Google TV"
        alert.informativeText = "Введите 6-значный PIN-код, отображаемый на экране вашего телевизора:"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Отмена")
        
        let inputTextField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        inputTextField.placeholderString = "123456"
        alert.accessoryView = inputTextField
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let pin = inputTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !pin.isEmpty {
                completion(pin)
            }
        }
    }
}

setbuf(stdout, nil)
setbuf(stderr, nil)

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
