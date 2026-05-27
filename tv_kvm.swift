import Cocoa
import Foundation
import AppKit
import Network
import Speech
import AVFoundation

// ==========================================
// Ширина триггерной зоны захвата на краю экрана (окно больше не расширяется, исключая пересечение полей)
let INITIAL_ZONE_WIDTH = 8.0
// ==========================================

// Класс для живого распознавания речи с микрофона Mac на русский/английский языки
class SpeechManager {
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    var onTranscriptionUpdate: ((String) -> Void)?
    var onError: ((String) -> Void)?
    var onStateChange: ((Bool) -> Void)?
    
    private(set) var isRecording = false
    
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                if status == .authorized {
                    AVCaptureDevice.requestAccess(for: .audio) { granted in
                        DispatchQueue.main.async {
                            completion(granted)
                        }
                    }
                } else {
                    completion(false)
                }
            }
        }
    }
    
    func startRecording() {
        guard !isRecording else { return }
        
        if let recognitionTask = recognitionTask {
            recognitionTask.cancel()
            self.recognitionTask = nil
        }
        
        let inputNode = audioEngine.inputNode
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            onError?("Не удалось создать запрос распознавания.")
            return
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer: AVAudioPCMBuffer, when: AVAudioTime) in
            self.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
            isRecording = true
            onStateChange?(true)
            
            recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                guard let self = self else { return }
                
                var isFinal = false
                if let result = result {
                    let transcription = result.bestTranscription.formattedString
                    self.onTranscriptionUpdate?(transcription)
                    isFinal = result.isFinal
                }
                
                if error != nil || isFinal {
                    self.stopRecording()
                }
            }
        } catch {
            onError?("Ошибка запуска аудиодвижка: \(error.localizedDescription)")
            stopRecording()
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        recognitionTask?.cancel()
        recognitionTask = nil
        
        isRecording = false
        onStateChange?(false)
    }
}

// Премиальная круглая кнопка с эффектом красного неонового свечения при записи
class MicButton: NSButton {
    var isRecording = false {
        didSet {
            needsDisplay = true
            if isRecording {
                startPulseAnimation()
            } else {
                stopPulseAnimation()
            }
        }
    }
    
    private var pulseScale: CGFloat = 1.0
    private var pulseTimer: Timer?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
        self.layer?.masksToBounds = false
        self.title = ""
        self.isBordered = false
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func draw(_ dirtyRect: NSRect) {
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) / 2.0 - 4.0
        
        let path = NSBezierPath()
        path.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        
        if isRecording {
            let gradient = NSGradient(starting: NSColor(red: 0.95, green: 0.2, blue: 0.3, alpha: 0.9),
                                      ending: NSColor(red: 0.8, green: 0.05, blue: 0.15, alpha: 0.95))
            gradient?.draw(in: path, angle: 90)
            
            NSGraphicsContext.current?.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor(red: 0.95, green: 0.2, blue: 0.3, alpha: 0.6 * CGFloat(pulseScale))
            shadow.shadowBlurRadius = 8.0 * pulseScale
            shadow.shadowOffset = NSSize(width: 0, height: 0)
            shadow.set()
            
            let ringPath = NSBezierPath()
            let ringRadius = radius + 3.0 * pulseScale
            ringPath.appendArc(withCenter: center, radius: ringRadius, startAngle: 0, endAngle: 360)
            NSColor(red: 0.95, green: 0.2, blue: 0.3, alpha: 0.8 * (1.5 - pulseScale)).setStroke()
            ringPath.lineWidth = 1.5
            ringPath.stroke()
            
            NSGraphicsContext.current?.restoreGraphicsState()
        } else {
            NSColor(red: 0.15, green: 0.15, blue: 0.2, alpha: 0.6).setFill()
            path.fill()
            
            NSColor(red: 0.35, green: 0.35, blue: 0.45, alpha: 0.4).setStroke()
            path.lineWidth = 1.0
            path.stroke()
        }
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        
        let fontSize: CGFloat = isRecording ? 18.0 : 16.0
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize),
            .paragraphStyle: paragraphStyle,
            .foregroundColor: NSColor.white
        ]
        
        let glyph = "🎙"
        let size = glyph.size(withAttributes: attributes)
        let rect = NSRect(x: center.x - size.width / 2.0, y: center.y - size.height / 2.0 - 1.0, width: size.width, height: size.height)
        glyph.draw(in: rect, withAttributes: attributes)
    }
    
    private func startPulseAnimation() {
        pulseTimer?.invalidate()
        pulseScale = 1.0
        
        var growing = true
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if growing {
                self.pulseScale += 0.05
                if self.pulseScale >= 1.3 {
                    growing = false
                }
            } else {
                self.pulseScale -= 0.05
                if self.pulseScale <= 0.9 {
                    growing = true
                }
            }
            self.needsDisplay = true
        }
    }
    
    private func stopPulseAnimation() {
        pulseTimer?.invalidate()
        pulseTimer = nil
        pulseScale = 1.0
        needsDisplay = true
    }
}

enum KVMEdge: String {
    case right = "RIGHT"
    case left = "LEFT"
    case top = "TOP"
}

class SocketClient {
    var connection: NWConnection?
    var queue = DispatchQueue(label: "KVM_SocketQueue")
    var onStatusChange: ((String) -> Void)?
    var onImeShow: ((String) -> Void)?
    var onAppChange: ((String) -> Void)?
    
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
        } else if trimmed.hasPrefix("IME_SHOW") {
            let parts = trimmed.split(separator: " ", maxSplits: 1)
            let base64Val = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
            let text: String
            if base64Val.isEmpty {
                text = ""
            } else if let data = Data(base64Encoded: base64Val),
                      let decoded = String(data: data, encoding: .utf8) {
                text = decoded
            } else {
                text = ""
            }
            print("[Swift Socket] IME_SHOW received, text: \"\(text)\"")
            onImeShow?(text)
        } else if trimmed.hasPrefix("APP ") {
            let appPackage = trimmed.replacingOccurrences(of: "APP ", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            print("[Swift Socket] APP received: \"\(appPackage)\"")
            onAppChange?(appPackage)
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
    var currentAppPackage: String = ""
    var scrollThreshold = 30.0
    var swipeThreshold = 80.0
    
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
        // Кулдаун 60 мс между командами навигации для плавной, отзывчивой и быстрой работы свайпов трекпада
        if now.timeIntervalSince(lastKeySentTime) >= 0.06 {
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
            
            // Сбрасываем текстовый буфер на мосте
            if let delegate = NSApp.delegate as? AppDelegate {
                delegate.socketClient.send(cmd: "RESET")
            }
            
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
        if abs(accumulatedX) >= swipeThreshold {
            if accumulatedX > 0 {
                sendNavKey("KEYCODE_DPAD_RIGHT")
                accumulatedX -= swipeThreshold
            } else {
                sendNavKey("KEYCODE_DPAD_LEFT")
                accumulatedX += swipeThreshold
            }
        }
        
        // Обработка вертикального свайпа с сохранением остатка дельты
        if abs(accumulatedY) >= swipeThreshold {
            if accumulatedY > 0 {
                sendNavKey("KEYCODE_DPAD_DOWN")
                accumulatedY -= swipeThreshold
            } else {
                sendNavKey("KEYCODE_DPAD_UP")
                accumulatedY += swipeThreshold
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
        let maxAccumulated = scrollThreshold * 3.0
        if accumulatedScrollY > maxAccumulated {
            accumulatedScrollY = maxAccumulated
        } else if accumulatedScrollY < -maxAccumulated {
            accumulatedScrollY = -maxAccumulated
        }
        
        if abs(accumulatedScrollY) >= scrollThreshold {
            // Мягкий кулдаун отправки команд прокрутки списков на ТВ (80 мс)
            // Это идеальная частота для автоповтора скроллинга страниц
            if now.timeIntervalSince(lastScrollKeyTime) >= 0.08 {
                let pkg = currentAppPackage.lowercased()
                let isBrowser = pkg.contains("browser") || pkg.contains("chrome") || pkg.contains("firefox") || pkg.contains("opera") || pkg.contains("webview")
                
                if accumulatedScrollY > 0 {
                    let key = isBrowser ? "KEYCODE_PAGE_UP" : "KEYCODE_DPAD_UP"
                    sendKey(key)
                    accumulatedScrollY -= scrollThreshold
                } else {
                    let key = isBrowser ? "KEYCODE_PAGE_DOWN" : "KEYCODE_DPAD_DOWN"
                    sendKey(key)
                    accumulatedScrollY += scrollThreshold
                }
                lastScrollKeyTime = now
            }
        }
    }
    
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

class FocusTextField: NSTextField {
    var onFocusChange: ((Bool) -> Void)?
    
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            onFocusChange?(true)
        }
        return result
    }
    
    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result {
            onFocusChange?(false)
        }
        return result
    }
}

class StyledTextFieldContainer: NSView {
    var isFocused = false {
        didSet {
            needsDisplay = true
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), xRadius: 8, yRadius: 8)
        
        // Премиальный темный полупрозрачный фон (slate dark translucent)
        NSColor(red: 0.08, green: 0.08, blue: 0.1, alpha: 0.85).setFill()
        path.fill()
        
        if isFocused {
            // Элегантная неоновая бирюзово-синяя рамка фокуса
            NSColor(red: 0.15, green: 0.55, blue: 0.95, alpha: 0.95).setStroke()
            path.lineWidth = 2.0
            
            NSGraphicsContext.current?.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor(red: 0.15, green: 0.55, blue: 0.95, alpha: 0.3)
            shadow.shadowBlurRadius = 6.0
            shadow.shadowOffset = NSSize(width: 0, height: 0)
            shadow.set()
            path.stroke()
            NSGraphicsContext.current?.restoreGraphicsState()
        } else {
            // Мягкая неактивная рамка
            NSColor(red: 0.25, green: 0.25, blue: 0.3, alpha: 0.4).setStroke()
            path.lineWidth = 1.0
            path.stroke()
        }
    }
}

class TextInputWindow: NSWindow {
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return true }
    
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == 53 { // Escape
            if let delegate = NSApp.delegate as? AppDelegate {
                delegate.dismissInputWindow(cancelled: true)
                return true
            }
        }
        if event.keyCode == 36 || event.keyCode == 76 { // Enter
            if let delegate = NSApp.delegate as? AppDelegate {
                delegate.submitText()
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }
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
    var shouldAutoConnect = true
    
    var inputWindow: TextInputWindow?
    var inputTextField: FocusTextField?
    var inputContainer: StyledTextFieldContainer?
    var micButton: MicButton?
    let speechManager = SpeechManager()
    var wasKVMActiveBeforeInput = false
    var isTyping = false
    
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
    
    @objc func setScrollVeryFast() { changeScrollThreshold(15.0) }
    @objc func setScrollFast() { changeScrollThreshold(22.0) }
    @objc func setScrollNormal() { changeScrollThreshold(30.0) }
    @objc func setScrollSlow() { changeScrollThreshold(45.0) }
    @objc func setScrollVerySlow() { changeScrollThreshold(60.0) }
    
    func changeScrollThreshold(_ value: Double) {
        kvmView?.scrollThreshold = value
        UserDefaults.standard.set(value, forKey: "KVM_ScrollThreshold")
        updateStatusMenu(self.lastStatus)
    }
    
    @objc func setSwipeVeryFast() { changeSwipeThreshold(40.0) }
    @objc func setSwipeFast() { changeSwipeThreshold(60.0) }
    @objc func setSwipeNormal() { changeSwipeThreshold(80.0) }
    @objc func setSwipeSlow() { changeSwipeThreshold(110.0) }
    @objc func setSwipeVerySlow() { changeSwipeThreshold(140.0) }
    
    func changeSwipeThreshold(_ value: Double) {
        kvmView?.swipeThreshold = value
        UserDefaults.standard.set(value, forKey: "KVM_SwipeThreshold")
        updateStatusMenu(self.lastStatus)
    }
    
    @objc func toggleVoiceInput() {
        if speechManager.isRecording {
            speechManager.stopRecording()
        } else {
            speechManager.requestAuthorization { [weak self] granted in
                guard let self = self else { return }
                if granted {
                    self.speechManager.startRecording()
                } else {
                    print("[Speech] Authorization denied")
                    let alert = NSAlert()
                    alert.messageText = "Доступ к микрофону и распознаванию речи отклонен"
                    alert.informativeText = "Пожалуйста, разрешите доступ к Микрофону и Распознаванию речи для tv_kvm в Системных настройках macOS в разделе Безопасность и Конфиденциальность."
                    alert.addButton(withTitle: "ОК")
                    alert.runModal()
                }
            }
        }
    }
    
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
        
        // Загружаем сохраненный порог скроллинга из UserDefaults
        if let savedScroll = UserDefaults.standard.object(forKey: "KVM_ScrollThreshold") as? Double {
            kvmView.scrollThreshold = savedScroll
        } else {
            kvmView.scrollThreshold = 30.0
        }
        
        // Загружаем сохраненный порог свайпов из UserDefaults
        if let savedSwipe = UserDefaults.standard.object(forKey: "KVM_SwipeThreshold") as? Double {
            kvmView.swipeThreshold = savedSwipe
        } else {
            kvmView.swipeThreshold = 80.0
        }
        
        window.contentView = kvmView
        window.makeFirstResponder(kvmView)
        
        // Настройка колбэков SpeechManager
        speechManager.onTranscriptionUpdate = { [weak self] text in
            DispatchQueue.main.async {
                if let textField = self?.inputTextField {
                    textField.stringValue = text
                    
                    // Мгновенная посимвольная трансляция на ТВ в реальном времени
                    if let base64Text = text.data(using: .utf8)?.base64EncodedString() {
                        self?.socketClient.send(cmd: "SET_TEXT \(base64Text)")
                    }
                }
            }
        }
        
        speechManager.onStateChange = { [weak self] isRecording in
            DispatchQueue.main.async {
                self?.micButton?.isRecording = isRecording
            }
        }
        
        speechManager.onError = { [weak self] errorMsg in
            print("[Speech Error] \(errorMsg)")
            DispatchQueue.main.async {
                self?.micButton?.isRecording = false
            }
        }
        
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
        
        socketClient.onImeShow = { [weak self] text in
            DispatchQueue.main.async {
                self?.showInputWindow(initialText: text)
            }
        }
        
        socketClient.onAppChange = { [weak self] appPackage in
            DispatchQueue.main.async {
                self?.kvmView?.currentAppPackage = appPackage
            }
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
    
    @objc func manuallyTriggerTextInput() {
        print("[Swift KVM] Menu item click: Manually triggering text input HUD.")
        self.showInputWindow(initialText: "")
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
        if status == "CONFLICT" {
            print("[Swift Socket] Connection conflict detected! Disabling autoconnect to prevent port war.")
            self.shouldAutoConnect = false
            self.disconnectKVM()
            
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Конфликт подключений"
                alert.informativeText = "Управление телевизором было перехвачено другим устройством (например, приложением Google TV на телефоне).\n\nАвтоматическое переподключение приостановлено во избежание конфликтов. Вы можете подключиться заново вручную через меню KVM после отключения другого пульта."
                alert.addButton(withTitle: "ОК")
                alert.runModal()
            }
            
            // Также обновим статус меню на DISCONNECTED, чтобы перерисовать UI как отключенный
            self.updateStatusMenu("DISCONNECTED")
            return
        }
        
        self.lastStatus = status
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Управляем видимостью триггерного окна на краю экрана:
            // Оно выводится на экран только при зеленом статусе READY (Подключен) и если мы не в режиме ввода текста.
            // Во всех остальных состояниях (Отключен, Подключение, Ввод PIN)
            // триггерная область полностью скрывается, чтобы никак не мешать пользователю на Mac.
            if status == "READY" && !self.isTyping {
                self.window.makeKeyAndOrderFront(nil)
            } else {
                self.window.orderOut(nil)
                if let kvmView = self.window.contentView as? KVMView {
                    if !self.isTyping {
                        kvmView.exitTVMode()
                    }
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
                    menu.addItem(NSMenuItem(title: "📝 Ввести текст на ТВ (Ctrl+Shift+T)", action: #selector(self.manuallyTriggerTextInput), keyEquivalent: "t"))
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
                        
                        if self.shouldAutoConnect {
                            self.shouldAutoConnect = false
                            // Небольшая задержка 0.5с, чтобы дать сокету полностью инициализироваться
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                                self?.connectKVM()
                            }
                        }
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
            
            // Настройка подменю с выбором плавности/чувствительности прокрутки
            let scrollMenu = NSMenu()
            let threshold = self.kvmView?.scrollThreshold ?? 30.0
            
            let scrollVeryFast = NSMenuItem(title: "Очень быстрая (чувствительная)", action: #selector(self.setScrollVeryFast), keyEquivalent: "")
            scrollVeryFast.state = (threshold == 15.0) ? .on : .off
            scrollMenu.addItem(scrollVeryFast)
            
            let scrollFast = NSMenuItem(title: "Быстрая", action: #selector(self.setScrollFast), keyEquivalent: "")
            scrollFast.state = (threshold == 22.0) ? .on : .off
            scrollMenu.addItem(scrollFast)
            
            let scrollNormal = NSMenuItem(title: "Средняя (по умолчанию)", action: #selector(self.setScrollNormal), keyEquivalent: "")
            scrollNormal.state = (threshold == 30.0) ? .on : .off
            scrollMenu.addItem(scrollNormal)
            
            let scrollSlow = NSMenuItem(title: "Плавная / Медленная", action: #selector(self.setScrollSlow), keyEquivalent: "")
            scrollSlow.state = (threshold == 45.0) ? .on : .off
            scrollMenu.addItem(scrollSlow)
            
            let scrollVerySlow = NSMenuItem(title: "Очень медленная", action: #selector(self.setScrollVerySlow), keyEquivalent: "")
            scrollVerySlow.state = (threshold == 60.0) ? .on : .off
            scrollMenu.addItem(scrollVerySlow)
            
            let scrollMenuItem = NSMenuItem(title: "Чувствительность прокрутки", action: nil, keyEquivalent: "")
            scrollMenuItem.submenu = scrollMenu
            menu.addItem(scrollMenuItem)
            
            // Настройка подменю с выбором плавности/чувствительности свайпов
            let swipeMenu = NSMenu()
            let swipeThreshold = self.kvmView?.swipeThreshold ?? 80.0
            
            let swipeVeryFast = NSMenuItem(title: "Очень быстрая (чувствительная)", action: #selector(self.setSwipeVeryFast), keyEquivalent: "")
            swipeVeryFast.state = (swipeThreshold == 40.0) ? .on : .off
            swipeMenu.addItem(swipeVeryFast)
            
            let swipeFast = NSMenuItem(title: "Быстрая", action: #selector(self.setSwipeFast), keyEquivalent: "")
            swipeFast.state = (swipeThreshold == 60.0) ? .on : .off
            swipeMenu.addItem(swipeFast)
            
            let swipeNormal = NSMenuItem(title: "Средняя (по умолчанию)", action: #selector(self.setSwipeNormal), keyEquivalent: "")
            swipeNormal.state = (swipeThreshold == 80.0) ? .on : .off
            swipeMenu.addItem(swipeNormal)
            
            let swipeSlow = NSMenuItem(title: "Плавная / Медленная", action: #selector(self.setSwipeSlow), keyEquivalent: "")
            swipeSlow.state = (swipeThreshold == 110.0) ? .on : .off
            swipeMenu.addItem(swipeSlow)
            
            let swipeVerySlow = NSMenuItem(title: "Очень медленная", action: #selector(self.setSwipeVerySlow), keyEquivalent: "")
            swipeVerySlow.state = (swipeThreshold == 140.0) ? .on : .off
            swipeMenu.addItem(swipeVerySlow)
            
            let swipeMenuItem = NSMenuItem(title: "Чувствительность свайпов", action: nil, keyEquivalent: "")
            swipeMenuItem.submenu = swipeMenu
            menu.addItem(swipeMenuItem)
            
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Выйти из KVM", action: #selector(self.terminate), keyEquivalent: "q"))
            
            self.statusItem.menu = menu
        }
    }
    

    func showInputWindow(initialText: String) {
        if let inputWindow = self.inputWindow {
            if let textField = self.inputTextField {
                textField.stringValue = initialText
            }
            inputWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        if let kvmView = self.kvmView {
            self.wasKVMActiveBeforeInput = kvmView.isActive
            if kvmView.isActive {
                NSCursor.unhide()
            }
        }
        
        self.isTyping = true
        self.window?.orderOut(nil)
        
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let windowWidth = 500.0
        let windowHeight = 130.0
        let x = (screenFrame.width - windowWidth) / 2.0 + screenFrame.origin.x
        let y = (screenFrame.height - windowHeight) / 2.0 + screenFrame.origin.y
        let frame = NSRect(x: x, y: y, width: windowWidth, height: windowHeight)
        
        let window = TextInputWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .statusBar
        
        let effectView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight))
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 14.0
        effectView.layer?.masksToBounds = true
        window.contentView = effectView
        
        let titleLabel = NSTextField(labelWithString: "ВВОД ТЕКСТА НА TV")
        titleLabel.frame = NSRect(x: 20, y: windowHeight - 30, width: windowWidth - 40, height: 16)
        titleLabel.textColor = NSColor(white: 0.9, alpha: 0.75)
        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        titleLabel.alignment = .left
        effectView.addSubview(titleLabel)
        
        let containerWidth = windowWidth - 40 - 52 // 408
        let container = StyledTextFieldContainer(frame: NSRect(x: 20, y: 45, width: containerWidth, height: 42))
        effectView.addSubview(container)
        self.inputContainer = container
        
        let textField = FocusTextField(frame: NSRect(x: 8, y: 8, width: containerWidth - 16, height: 26))
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.textColor = .white
        textField.font = NSFont.systemFont(ofSize: 15, weight: .regular)
        textField.placeholderString = "Введите текст для отправки..."
        textField.focusRingType = .none
        textField.delegate = self
        textField.stringValue = initialText
        
        textField.onFocusChange = { [weak container] isFocused in
            container?.isFocused = isFocused
        }
        
        container.addSubview(textField)
        self.inputTextField = textField
        
        // Создаем кнопку микрофона с пульсирующим неоновым эффектом
        let mic = MicButton(frame: NSRect(x: 20 + containerWidth + 10, y: 45, width: 42, height: 42))
        mic.target = self
        mic.action = #selector(toggleVoiceInput)
        effectView.addSubview(mic)
        self.micButton = mic
        
        let helpLabel = NSTextField(labelWithString: "Enter — отправить • Esc — отмена • Поддержка языков RU / EN")
        helpLabel.frame = NSRect(x: 20, y: 18, width: windowWidth - 40, height: 14)
        helpLabel.textColor = NSColor(white: 0.9, alpha: 0.45)
        helpLabel.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        helpLabel.alignment = .left
        effectView.addSubview(helpLabel)
        
        self.inputWindow = window
        
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(textField)
        
        if !initialText.isEmpty {
            textField.currentEditor()?.selectAll(nil)
        }
    }
    
    @objc func submitText() {
        if let textField = self.inputTextField {
            let text = textField.stringValue
            print("[Swift KVM] submitText called, text: \"\(text)\"")
            if let base64Text = text.data(using: .utf8)?.base64EncodedString() {
                socketClient.send(cmd: "SET_TEXT \(base64Text)")
            }
        }
        
        // Задержка 150 мс перед отправкой ENTER и скрытием окна, чтобы гарантировать,
        // что телевизор успел полностью получить и применить SET_TEXT BatchEdit.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.socketClient.send(cmd: "KEY KEYCODE_ENTER")
            self?.dismissInputWindow(cancelled: false)
        }
    }
    
    func dismissInputWindow(cancelled: Bool) {
        guard let window = self.inputWindow else { return }
        
        speechManager.stopRecording()
        
        window.orderOut(nil)
        self.inputWindow = nil
        self.inputTextField = nil
        self.inputContainer = nil
        self.micButton = nil
        self.isTyping = false
        
        // Сбрасываем локальный текстовый буфер на мосте
        socketClient.send(cmd: "RESET")
        
        if self.lastStatus == "READY" {
            self.window?.makeKeyAndOrderFront(nil)
        }
        
        if !cancelled || wasKVMActiveBeforeInput {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if let kvmView = self.kvmView {
                    if !kvmView.isActive {
                        kvmView.enterTVMode()
                    } else {
                        NSCursor.hide()
                        self.window?.makeKeyAndOrderFront(nil)
                        self.window?.makeFirstResponder(kvmView)
                    }
                }
            }
        } else {
            NSApp.deactivate()
            NSApp.setActivationPolicy(.accessory)
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

extension AppDelegate: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard let textField = obj.object as? NSTextField else { return }
        let text = textField.stringValue
        print("[Swift KVM] controlTextDidChange, text: \"\(text)\"")
        if let base64Text = text.data(using: .utf8)?.base64EncodedString() {
            socketClient.send(cmd: "SET_TEXT \(base64Text)")
        }
    }
}

setbuf(stdout, nil)
setbuf(stderr, nil)

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
