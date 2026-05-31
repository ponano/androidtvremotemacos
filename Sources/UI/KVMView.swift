import Cocoa
import Foundation
import AppKit
import Network
import ServiceManagement
import Speech
import AVFoundation
import Darwin

class KVMView: NSView {
    var isActive = false
    var activeEdge: KVMEdge = .right
    
    // Позволяет подменять источник состояния мыши в тестах (Dependency Injection)
    var mouseStateProvider: MouseStateProviding = DefaultMouseStateProvider()
    
    var macWidth = 1440.0
    var macHeight = 900.0
    
    var accumulatedX = 0.0
    var accumulatedY = 0.0
    var accumulatedScrollY = 0.0
    var lastKeySentTime = Date()
    var lastScrollGestureTime = Date()
    var lastScrollKeyTime = Date()
    var activationTimer: Timer?
    var currentAppPackage: String = ""
    
    // Приложения-браузеры, для которых используется непрерывное удержание стрелки (имитация пульта)
    let browserPackages: Set<String> = [
        "com.tcl.browser",        // BrowseHere
        "com.opera.browser",
        "com.phlox.tvwebbrowser", // TV Bro
    ]
    var isBrowserActive: Bool {
        return browserPackages.contains(currentAppPackage)
    }
    var scrollThreshold = 60.0
    var swipeThreshold = 140.0
    
    // Отслеживание тапа и свайпа 3 пальцами
    var maxSimultaneousTouches = 0
    var threeFingerTouchStartTime: Date?
    var threeFingerStartAvgX: CGFloat?
    var threeFingerStartAvgY: CGFloat?
    
    // Непрерывное удержание стрелки (имитация зажатой кнопки физического пульта)
    var currentHoldDirection: String? = nil  // Текущая зажатая клавиша (nil = ничего не зажато)
    var holdIdleTimer: Timer? = nil          // Таймер отпускания при остановке пальца
    
    // Количество пальцев на трекпаде (для определения жеста: 1=навигация, 2=громкость, 3=Home)
    var currentTouchCount = 0
    var accumulatedVolumeDeltaY = 0.0        // Накопление дельты для 2-пальцевого управления громкостью
    let volumeSwipeThreshold = 6.0           // Порог срабатывания изменения громкости (аналог шага на пульте)
    var lastVolumeKeyTime = Date.distantPast // Кулдаун между командами громкости
    
    private var trackingArea: NSTrackingArea?
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        
        // Автоматически определяем разрешение вашего экрана Mac
        if let screenFrame = NSScreen.main?.frame {
            macWidth = Double(screenFrame.width)
            macHeight = Double(screenFrame.height)
        }
        
        // Включаем отслеживание касаний трекпада для обнаружения мультитач-жестов
        self.allowedTouchTypes = [.indirect]
        self.acceptsTouchEvents = true
        
        // Регистрируем типы Drag & Drop для предотвращения активации при перетаскивании файлов/вкладок
        self.registerForDraggedTypes([
            .fileURL,
            .string,
            .html,
            .tiff,
            .png,
            .pdf,
            .rtf,
            .rtfd
        ])
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
    
    func sendTrackpadKey(_ key: String) {
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.socketClient.send(cmd: "TRACKPAD \(key)")
        }
    }
    
    /// Начать удержание стрелки (или продлить, если направление не изменилось)
    func holdNavKey(_ key: String) {
        // Сбрасываем таймер idle — палец всё ещё движется
        holdIdleTimer?.invalidate()
        
        if currentHoldDirection == key {
            // Та же кнопка уже зажата — просто продлеваем удержание
            // Запускаем таймер отпускания: если палец остановится на 150 мс — отпускаем
            holdIdleTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
                self?.releaseHold()
            }
            return
        }
        
        // Если зажата другая кнопка — сначала отпускаем её
        if currentHoldDirection != nil {
            releaseHold()
        }
        
        // Зажимаем новую кнопку
        currentHoldDirection = key
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.socketClient.send(cmd: "HOLD_START \(key)")
        }
        print("[KVM] HOLD_START: \(key)")
        
        // Таймер отпускания при остановке пальца
        holdIdleTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
            self?.releaseHold()
        }
    }
    
    /// Отпустить текущую зажатую стрелку
    func releaseHold() {
        holdIdleTimer?.invalidate()
        holdIdleTimer = nil
        if let dir = currentHoldDirection {
            if let delegate = NSApp.delegate as? AppDelegate {
                delegate.socketClient.send(cmd: "HOLD_END \(dir)")
            }
            print("[KVM] HOLD_END: \(dir)")
            currentHoldDirection = nil
        }
    }
    
    func sendNavKey(_ key: String) {
        let now = Date()
        // Кулдаун 100 мс (0.10 сек) между командами навигации для защиты от дребезга и мгновенного отклика на жесты
        if now.timeIntervalSince(lastKeySentTime) >= 0.10 {
            sendTrackpadKey(key)
            lastKeySentTime = now
        }
    }
    
    override func mouseEntered(with event: NSEvent) {
        // Проверяем, зажата ли левая кнопка мыши (перетаскивание, выделение текста или окон)
        if (mouseStateProvider.pressedMouseButtons & 1) != 0 {
            print("[KVM] Левая кнопка мыши зажата (возможно перетаскивание). Игнорируем активацию режима ТВ.")
            return
        }
        
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
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        print("[KVM] Сессия перетаскивания вошла в триггерную зону. Блокируем KVM.")
        activationTimer?.invalidate()
        activationTimer = nil
        return []
    }
    
    func enterTVMode() {
        guard !isActive else { return }
        isActive = true
        print("\n>>> РЕЖИМ УПРАВЛЕНИЯ ТВ АКТИВЕН (Трекпад захвачен) <<<")
        print("Для возврата на Mac проведите тремя пальцами влево или нажмите Escape / Option.")
        
        accumulatedX = 0.0
        accumulatedY = 0.0
        threeFingerStartAvgX = nil
        threeFingerStartAvgY = nil
        
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
            threeFingerStartAvgX = nil
            threeFingerStartAvgY = nil
            accumulatedScrollY = 0.0
            accumulatedVolumeDeltaY = 0.0
            
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
            
            // Сбрасываем текстовый буфер на мосте
            if let delegate = NSApp.delegate as? AppDelegate {
                delegate.socketClient.send(cmd: "RESET")
            }
            
            // Отпускаем зажатую кнопку, если есть
            releaseHold()
            
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
        
        // Накапливаем относительные дельты аппаратного сдвига мыши/трекпада для обычных свайпов
        accumulatedX += Double(event.deltaX)
        
        let now = Date()
        let timeSinceLastScroll = now.timeIntervalSince(lastScrollGestureTime)
        
        // Если пользователь скроллит двумя пальцами (последний скролл был менее 0.3 сек назад),
        // мы полностью блокируем обработку вертикальных свайпов в mouseMoved.
        if timeSinceLastScroll >= 0.3 {
            accumulatedY += Double(event.deltaY)
        } else {
            accumulatedY = 0.0
        }
        
        // --- 1. Обрабатываем горизонтальный свайп навигации ---
        if abs(accumulatedX) >= swipeThreshold {
            let key = accumulatedX > 0 ? "KEYCODE_DPAD_RIGHT" : "KEYCODE_DPAD_LEFT"
            if isBrowserActive {
                holdNavKey(key)
            } else {
                sendNavKey(key)
            }
            accumulatedX = 0.0
            accumulatedY = 0.0
        }
        
        // --- 2. Обрабатываем вертикальный свайп навигации ---
        if abs(accumulatedY) >= swipeThreshold {
            let key = accumulatedY > 0 ? "KEYCODE_DPAD_DOWN" : "KEYCODE_DPAD_UP"
            if isBrowserActive {
                holdNavKey(key)
            } else {
                sendNavKey(key)
            }
            accumulatedX = 0.0
            accumulatedY = 0.0
        }
        
        // Удерживаем курсор мыши строго по центру нашей триггерной полоски захвата.
        // Это блокирует курсор от вылета на рабочий стол Mac и случайных кликов,
        // позволяя считывать бесконечное плавное скольжение по трекпаду.
        let centerPoint: CGPoint
        switch activeEdge {
        case .right:
            centerPoint = CGPoint(x: macWidth - (Config.INITIAL_ZONE_WIDTH / 2.0), y: macHeight / 2.0)
        case .left:
            centerPoint = CGPoint(x: Config.INITIAL_ZONE_WIDTH / 2.0, y: macHeight / 2.0)
        case .top:
            centerPoint = CGPoint(x: macWidth / 2.0, y: Config.INITIAL_ZONE_WIDTH / 2.0)
        }
        CGWarpMouseCursorPosition(centerPoint)
    }
    
    var mouseDownTime: Date? = nil       // Время начала клика
    var longPressTimer: Timer? = nil     // Таймер для определения long press
    var isLongPressActive = false        // Флаг: режим long press активирован
    
    override func mouseDown(with event: NSEvent) {
        guard isActive else { return }
        mouseDownTime = Date()
        isLongPressActive = false
        
        // Через 1 секунду удержания → отправляем START_LONG DPAD_CENTER
        longPressTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.isLongPressActive = true
            print("[KVM] Длинный клик: START_LONG DPAD_CENTER (вход в режим скроллинга)")
            if let delegate = NSApp.delegate as? AppDelegate {
                delegate.socketClient.send(cmd: "HOLD_START KEYCODE_DPAD_CENTER")
            }
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        guard isActive else { return }
        longPressTimer?.invalidate()
        longPressTimer = nil
        
        if isLongPressActive {
            // Отпускаем long press → END_LONG DPAD_CENTER
            print("[KVM] Отпускание: END_LONG DPAD_CENTER")
            if let delegate = NSApp.delegate as? AppDelegate {
                delegate.socketClient.send(cmd: "HOLD_END KEYCODE_DPAD_CENTER")
            }
            isLongPressActive = false
        } else {
            // Короткий клик (<1 сек) → обычный DPAD_CENTER (выбор)
            print("[KVM] Клик: Выбор (DPAD CENTER)")
            sendKey("KEYCODE_DPAD_CENTER")
        }
        mouseDownTime = nil
    }
    
    override func rightMouseDown(with event: NSEvent) {
        guard isActive else { return }
        print("[KVM] Правый клик: Назад (KEYCODE_BACK)")
        sendKey("KEYCODE_BACK")
    }
    
    override func scrollWheel(with event: NSEvent) {
        guard isActive else { return }
        
        let now = Date()
        lastScrollGestureTime = now
        
        accumulatedVolumeDeltaY += Double(event.deltaY)
        
        // Ограничим накопление дельты, чтобы громкость не менялась бесконечно после одного сильного движения
        let maxAccumulated = volumeSwipeThreshold * 3.0
        if accumulatedVolumeDeltaY > maxAccumulated {
            accumulatedVolumeDeltaY = maxAccumulated
        } else if accumulatedVolumeDeltaY < -maxAccumulated {
            accumulatedVolumeDeltaY = -maxAccumulated
        }
        
        if abs(accumulatedVolumeDeltaY) >= volumeSwipeThreshold {
            // Кулдаун 60 мс для моментального и супербыстрого изменения громкости
            if now.timeIntervalSince(lastVolumeKeyTime) >= 0.06 {
                if accumulatedVolumeDeltaY > 0 {
                    sendKey("KEYCODE_VOLUME_UP")
                    print("[KVM] 2-finger scroll/swipe: Volume Up")
                } else {
                    sendKey("KEYCODE_VOLUME_DOWN")
                    print("[KVM] 2-finger scroll/swipe: Volume Down")
                }
                accumulatedVolumeDeltaY = 0.0
                lastVolumeKeyTime = now
            }
        }
    }
    
    // === Мультитач-жесты трекпада ===
    
    override func touchesBegan(with event: NSEvent) {
        guard isActive else { return }
        let touches = event.touches(matching: .touching, in: self)
        let count = touches.count
        currentTouchCount = count
        print("[KVM Touch] touchesBegan: count=\(count), currentTouchCount=\(currentTouchCount)")
        maxSimultaneousTouches = max(maxSimultaneousTouches, count)
        if count == 3 {
            threeFingerTouchStartTime = Date()
            let avgX = touches.map { $0.normalizedPosition.x }.reduce(0, +) / 3.0
            let avgY = touches.map { $0.normalizedPosition.y }.reduce(0, +) / 3.0
            threeFingerStartAvgX = avgX
            threeFingerStartAvgY = avgY
        } else {
            threeFingerStartAvgX = nil
            threeFingerStartAvgY = nil
        }
    }
    
    override func touchesMoved(with event: NSEvent) {
        guard isActive else { return }
        let touches = event.touches(matching: .touching, in: self)
        let count = touches.count
        currentTouchCount = count
        
        if count == 3 {
            let avgX = touches.map { $0.normalizedPosition.x }.reduce(0, +) / 3.0
            let avgY = touches.map { $0.normalizedPosition.y }.reduce(0, +) / 3.0
            
            if let startX = threeFingerStartAvgX {
                let deltaX = avgX - startX // deltaX отрицательный при свайпе влево
                
                // Свайп влево тремя пальцами (смещение на 12% от ширины трекпада)
                if deltaX <= -0.12 {
                    print("[KVM Touch] 3-finger swipe left detected! Exiting TV mode.")
                    exitTVMode()
                    return
                }
            } else {
                threeFingerStartAvgX = avgX
                threeFingerStartAvgY = avgY
            }
        } else {
            threeFingerStartAvgX = nil
            threeFingerStartAvgY = nil
        }
    }
    
    override func touchesEnded(with event: NSEvent) {
        guard isActive else {
            maxSimultaneousTouches = 0
            threeFingerTouchStartTime = nil
            threeFingerStartAvgX = nil
            threeFingerStartAvgY = nil
            return
        }
        let remaining = event.touches(matching: .touching, in: self)
        currentTouchCount = remaining.count
        print("[KVM Touch] touchesEnded: remaining=\(remaining.count), currentTouchCount=\(currentTouchCount)")
        if remaining.count == 0 {
            // Все пальцы подняты
            let now = Date()
            if maxSimultaneousTouches == 3, let start = threeFingerTouchStartTime {
                let duration = now.timeIntervalSince(start)
                if duration < 0.4 { // Менее 400 мс — это тап, а не свайп
                    print("[KVM] Тап 3 пальцами: Home (KEYCODE_HOME)")
                    sendKey("KEYCODE_HOME")
                }
            }
            maxSimultaneousTouches = 0
            threeFingerTouchStartTime = nil
            threeFingerStartAvgX = nil
            threeFingerStartAvgY = nil
        }
    }
    
    override func touchesCancelled(with event: NSEvent) {
        print("[KVM Touch] touchesCancelled")
        currentTouchCount = 0
        maxSimultaneousTouches = 0
        threeFingerTouchStartTime = nil
        threeFingerStartAvgX = nil
        threeFingerStartAvgY = nil
    }
    
    // === Клавиатура ===
    
    override func keyDown(with event: NSEvent) {
        guard isActive else { return }
        
        print("[Swift KVM] KeyDown event captured: keyCode=\(event.keyCode), modifierFlags=\(event.modifierFlags), chars=\"\(event.characters ?? "")\"")
        
        // Горячая клавиша Control + Shift + T — принудительный ручной вызов HUD ввода текста
        if event.modifierFlags.contains(.control) && event.modifierFlags.contains(.shift) && event.keyCode == 17 { // 17 — это код клавиши 'T'
            print("[Swift KVM] Control + Shift + T pressed. Manually invoking HUD Input Window.")
            if let delegate = NSApp.delegate as? AppDelegate {
                delegate.showInputWindow(initialText: "")
            }
            return
        }
        
        // Escape (код 53) или Option (Alt) — мгновенный выход на Mac
        if event.keyCode == 53 || event.modifierFlags.contains(.option) {
            print("[Swift KVM] Escape or Option key pressed. Exiting TV mode.")
            exitTVMode()
            return
        }
        
        // Управление громкостью ТВ: Control + Shift + Стрелка Вверх (громче) / Стрелка Вниз (тише)
        // Это гарантированно не занято Mission Control в macOS и на 100% свободно
        if event.modifierFlags.contains(.control) && event.modifierFlags.contains(.shift) {
            if event.keyCode == 126 { // Control + Shift + Стрелка Вверх
                print("[Swift KVM] Control + Shift + Up pressed. Volume Up.")
                sendKey("KEYCODE_VOLUME_UP")
                return
            }
            if event.keyCode == 125 { // Control + Shift + Стрелка Вниз
                print("[Swift KVM] Control + Shift + Down pressed. Volume Down.")
                sendKey("KEYCODE_VOLUME_DOWN")
                return
            }
        }
        
        // Backspace (код 51)
        if event.keyCode == 51 {
            if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) {
                // Command + Backspace или Control + Backspace — действие "Назад" (KEYCODE_BACK)
                print("[Swift KVM] Command/Control + Backspace pressed. Sending KEYCODE_BACK.")
                sendKey("KEYCODE_BACK")
            } else {
                // Обычный Backspace — стирание текста (KEYCODE_DEL)
                print("[Swift KVM] Backspace pressed. Sending KEYCODE_DEL.")
                sendKey("KEYCODE_DEL")
            }
            return
        }
        
        // Enter (код 36) или Numpad Enter (код 76)
        if event.keyCode == 36 || event.keyCode == 76 {
            print("[Swift KVM] Enter pressed. Sending KEYCODE_ENTER.")
            sendKey("KEYCODE_ENTER")
            return
        }
        
        // Стрелочки клавиатуры для дублирования навигации напрямую без кулдауна с системным автоповтором
        if event.keyCode == 126 { print("[Swift KVM] Up Arrow pressed."); sendKey("KEYCODE_DPAD_UP"); return }
        if event.keyCode == 125 { print("[Swift KVM] Down Arrow pressed."); sendKey("KEYCODE_DPAD_DOWN"); return }
        if event.keyCode == 123 { print("[Swift KVM] Left Arrow pressed."); sendKey("KEYCODE_DPAD_LEFT"); return }
        if event.keyCode == 124 { print("[Swift KVM] Right Arrow pressed."); sendKey("KEYCODE_DPAD_RIGHT"); return }
        
        // Обработка текстового набора букв через прямые KEYCODES для максимальной надежности,
        // с резервным фолбэком на Base64 CHAR (нативный IME), если символ не замаплен
        if let chars = event.characters, !chars.isEmpty {
            for char in chars {
                let scalars = char.unicodeScalars
                if let first = scalars.first, first.value >= 32 && first.value != 127 {
                    let charStr = String(char)
                    print("[Swift KVM] Transmitting character: \"\(charStr)\"")
                    
                    if let mappedKey = mapCharToKeyCode(charStr) {
                        print("[Swift KVM] Character mapped to standard keycode: \(mappedKey)")
                        sendKey(mappedKey)
                    } else {
                        // Резервный фолбэк на Base64 IME для редких спецсимволов
                        if let base64Char = charStr.data(using: .utf8)?.base64EncodedString() {
                            print("[Swift KVM] Character fell back to Base64 IME: \(base64Char)")
                            if let delegate = NSApp.delegate as? AppDelegate {
                                delegate.socketClient.send(cmd: "CHAR \(base64Char)")
                            }
                        }
                    }
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
            
            "a": "KEYCODE_A", "b": "KEYCODE_B", "c": "KEYCODE_C", "d": "KEYCODE_D",
            "e": "KEYCODE_E", "f": "KEYCODE_F", "g": "KEYCODE_G", "h": "KEYCODE_H",
            "i": "KEYCODE_I", "j": "KEYCODE_J", "k": "KEYCODE_K", "l": "KEYCODE_L",
            "m": "KEYCODE_M", "n": "KEYCODE_N", "o": "KEYCODE_O", "p": "KEYCODE_P",
            "q": "KEYCODE_Q", "r": "KEYCODE_R", "s": "KEYCODE_S", "t": "KEYCODE_T",
            "u": "KEYCODE_U", "v": "KEYCODE_V", "w": "KEYCODE_W", "x": "KEYCODE_X",
            "y": "KEYCODE_Y", "z": "KEYCODE_Z",
            
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
            
            "ф": "KEYCODE_A", "и": "KEYCODE_B", "с": "KEYCODE_C", "в": "KEYCODE_D",
            "у": "KEYCODE_E", "а": "KEYCODE_F", "п": "KEYCODE_G", "р": "KEYCODE_H",
            "ш": "KEYCODE_I", "о": "KEYCODE_J", "л": "KEYCODE_K", "д": "KEYCODE_L",
            "ь": "KEYCODE_M", "т": "KEYCODE_N", "щ": "KEYCODE_O", "з": "KEYCODE_P",
            "й": "KEYCODE_Q", "к": "KEYCODE_R", "ы": "KEYCODE_S", "е": "KEYCODE_T",
            "г": "KEYCODE_U", "м": "KEYCODE_V", "ц": "KEYCODE_W", "ч": "KEYCODE_X",
            "н": "KEYCODE_Y", "я": "KEYCODE_Z",
            
            "б": "KEYCODE_COMMA", "ю": "KEYCODE_PERIOD", "х": "KEYCODE_LEFT_BRACKET",
            "ъ": "KEYCODE_RIGHT_BRACKET", "ж": "KEYCODE_SEMICOLON", "э": "KEYCODE_APOSTROPHE",
            "ё": "KEYCODE_GRAVE", "Б": "KEYCODE_COMMA", "Ю": "KEYCODE_PERIOD",
            "Х": "KEYCODE_LEFT_BRACKET", "Ъ": "KEYCODE_RIGHT_BRACKET", "Ж": "KEYCODE_SEMICOLON",
            "Э": "KEYCODE_APOSTROPHE", "Ё": "KEYCODE_GRAVE"
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

