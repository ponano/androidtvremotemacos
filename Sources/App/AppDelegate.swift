import Cocoa
import Foundation
import AppKit
import Network
import ServiceManagement
import Speech
import AVFoundation
import Darwin

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var statusItem: NSStatusItem!
    var socketClient = SocketClient()
    var lastStatus: String = "DISCONNECTED"
    var shouldAutoConnect = true
    var tvDiscovery: TVDiscovery?
    
    var inputWindow: TextInputWindow?
    var inputTextField: FocusTextField?
    var inputContainer: StyledTextFieldContainer?
    var inputTitleLabel: NSTextField?
    var inputHelpLabel: NSTextField?
    var micButton: MicButton?
    var speechManager: SpeechManager? = nil
    var wasKVMActiveBeforeInput = false
    var isTyping = false
    
    var nodeProcess: Process?
    var nodeRestartCount = 0          // Счётчик перезапусков Node.js моста
    let maxNodeRestarts = 3           // Максимум автоперезапусков
    var isBridgeAlive = false         // Жив ли Node.js мост
    var blinkTimer: Timer?            // Таймер мигания при подключении
    var blinkVisible = true           // Текущее состояние мигания
    var resolvedIP: String? = nil
    var discoveryTimer: Timer?
    
    func getTVIP() -> String {
        let bundlePath = Bundle.main.bundlePath
        let parentDir = (bundlePath as NSString).deletingLastPathComponent
        let scriptPath = "\(parentDir)/run_kvm.sh"
        if let content = try? String(contentsOfFile: scriptPath, encoding: .utf8) {
            let lines = content.components(separatedBy: .newlines)
            for line in lines {
                if line.hasPrefix("TV_IP=") {
                    let parts = line.components(separatedBy: "=")
                    if parts.count > 1 {
                        let ip = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'\n\r "))
                        if !ip.isEmpty {
                            return ip
                        }
                    }
                }
            }
        }
        // Fallback на автопоиск Bonjour, если IP не задан явно
        return "auto"
    }
    
    func startNodeBridge(resolvedIP: String? = nil) {
        let tvIP = resolvedIP ?? getTVIP()
        if tvIP == "auto" {
            print("[Swift] TV IP is set to 'auto'. Postponing bridge startup until TV is discovered by Bonjour.")
            return
        }
        
        // Сначала подчищаем возможных сирот от предыдущего запуска
        cleanupOrphanedBridge()
        
        // Проверяем, не запущен ли уже мост (run_kvm.sh мог запустить его отдельно)
        if let existingProcess = nodeProcess, existingProcess.isRunning {
            print("[Swift] Node.js bridge already running (PID: \(existingProcess.processIdentifier)), skipping launch.")
            isBridgeAlive = true
            return
        }
        
        let bundlePath = Bundle.main.bundlePath
        let parentDir = (bundlePath as NSString).deletingLastPathComponent
        let currentDir = FileManager.default.currentDirectoryPath
        
        // Ищем bridge-скрипт в нескольких местах (приоритет):
        let searchPaths = [
            // 1. Внутри .app бандла (для запуска из Launchpad / /Applications)
            "\(bundlePath)/Contents/Resources/bridge/tv_remote_bridge.js",
            // 2. Рядом с .app бандлом (для запуска из MacTV_KVM/tv_kvm.app)
            "\(parentDir)/tv_remote_bridge.js",
            // 3. В текущей рабочей директории (для запуска ./tv_kvm напрямую)
            "\(currentDir)/tv_remote_bridge.js",
        ]
        
        var bridgeScript: String? = nil
        for path in searchPaths {
            if FileManager.default.fileExists(atPath: path) {
                bridgeScript = path
                break
            }
        }
        
        // Проверяем, найден ли bridge-скрипт
        guard let foundScript = bridgeScript else {
            print("[Swift Error] Bridge script not found! Searched paths:")
            for path in searchPaths {
                print("[Swift Error]   - \(path)")
            }
            return
        }
        
        let workDir = (foundScript as NSString).deletingLastPathComponent
        
        print("[Swift] Bundle path: \(bundlePath)")
        print("[Swift] Bridge script: \(foundScript)")
        print("[Swift] Working directory: \(workDir)")
        print("[Swift] Starting background Node.js bridge for IP: \(tvIP)...")
        
        let process = Process()
        let nodePaths = ["/usr/local/bin/node", "/opt/homebrew/bin/node", "/usr/bin/node"]
        var chosenPath = "/usr/bin/env"
        var args = ["node", foundScript, tvIP]
        
        for path in nodePaths {
            if FileManager.default.fileExists(atPath: path) {
                chosenPath = path
                args = [foundScript, tvIP]
                break
            }
        }
        
        process.executableURL = URL(fileURLWithPath: chosenPath)
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: workDir)
        
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        
        // Мониторинг завершения Node.js процесса — автоперезапуск при крахе
        process.terminationHandler = { [weak self] terminatedProcess in
            guard let self = self else { return }
            let exitCode = terminatedProcess.terminationStatus
            let reason = terminatedProcess.terminationReason
            
            print("[Swift] Node.js bridge terminated (exit code: \(exitCode), reason: \(reason.rawValue))")
            self.isBridgeAlive = false
            
            // Если завершение было не по нашей инициативе (не .exit с кодом 0)
            if reason == .uncaughtSignal || exitCode != 0 {
                DispatchQueue.main.async {
                    if self.nodeRestartCount < self.maxNodeRestarts {
                        self.nodeRestartCount += 1
                        print("[Swift] Auto-restarting Node.js bridge (attempt \(self.nodeRestartCount)/\(self.maxNodeRestarts))...")
                        
                        // Задержка перед перезапуском
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                            self?.startNodeBridge()
                            // Переподключить сокет после перезапуска моста
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                                self?.socketClient.connect()
                            }
                        }
                    } else {
                        print("[Swift Error] Max Node.js bridge restart attempts reached (\(self.maxNodeRestarts)).")
                        self.updateStatusMenu("BRIDGE_DEAD")
                    }
                }
            }
        }
        
        do {
            try process.run()
            self.nodeProcess = process
            self.isBridgeAlive = true
            print("[Swift] Successfully launched Node.js bridge subprocess (PID: \(process.processIdentifier))")
        } catch {
            print("[Swift Error] Failed to launch Node.js bridge: \(error)")
            self.isBridgeAlive = false
        }
    }
    
    func stopNodeBridge() {
        if let process = nodeProcess, process.isRunning {
            process.terminationHandler = nil  // Отключаем автоперезапуск
            process.terminate()  // SIGTERM → graceful shutdown в Node.js
            print("[Swift] Sent SIGTERM to Node.js bridge (PID: \(process.processIdentifier)). Waiting for exit...")
            
            // Ждём до 3 секунд, пока процесс завершится
            let deadline = Date().addingTimeInterval(3.0)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.1)
            }
            
            // Если процесс всё ещё жив — убиваем принудительно
            if process.isRunning {
                print("[Swift] Node.js bridge did not exit in time. Sending SIGKILL...")
                kill(process.processIdentifier, SIGKILL)
                process.waitUntilExit()
            }
            
            print("[Swift] Node.js bridge terminated successfully.")
        }
        nodeProcess = nil
        isBridgeAlive = false
        
        // Подчищаем возможных сирот на порту 12345
        cleanupOrphanedBridge()
    }
    
    /// Убивает любые процессы, занимающие порт 12345 (защита от зависших экземпляров моста)
    func cleanupOrphanedBridge() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "lsof -ti :12345 | xargs kill -9 2>/dev/null; exit 0"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
    }
    
    // HUD-справка по жестам
    var helpOverlayWindow: NSWindow?
    var helpDismissTimer: Timer?
    
    func showHelpOverlay() {
        // Закрываем старый если есть
        hideHelpOverlay()
        
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let windowWidth: CGFloat = 340.0
        let windowHeight: CGFloat = 322.0
        let x = (screenFrame.width - windowWidth) / 2.0 + screenFrame.origin.x
        let y = screenFrame.origin.y + 60.0  // Внизу экрана
        let frame = NSRect(x: x, y: y, width: windowWidth, height: windowHeight)
        
        let helpWindow = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        helpWindow.isOpaque = false
        helpWindow.backgroundColor = .clear
        helpWindow.hasShadow = true
        helpWindow.level = .floating
        helpWindow.ignoresMouseEvents = true  // Не перехватывает клики
        helpWindow.alphaValue = 0.0  // Начинаем с невидимого
        
        let effectView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight))
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 16.0
        
        // Заголовок
        let titleLabel = NSTextField(labelWithString: "📺 TV Пульт — Управление трекпадом")
        titleLabel.frame = NSRect(x: 16, y: windowHeight - 36, width: windowWidth - 32, height: 20)
        titleLabel.font = NSFont.boldSystemFont(ofSize: 14)
        titleLabel.textColor = .white
        titleLabel.alignment = .center
        
        // Разделитель
        let separator = NSBox(frame: NSRect(x: 20, y: windowHeight - 44, width: windowWidth - 40, height: 1))
        separator.boxType = .separator
        
        // Жесты — строки
        let gestures: [(String, String)] = [
            ("☝️  Свайп 1 пальцем", "Навигация (стрелки)"),
            ("👆  Клик (короткий)", "Выбор / OK"),
            ("👆  Клик (зажать ≥1с)", "Режим скроллинга"),
            ("✌️  Клик 2 пальцами", "Назад"),
            ("🔊  Скролл 2 пальцами", "Громкость ТВ"),
            ("🤟  Тап 3 пальцами", "Home"),
            ("⬅️  Свайп 3 пальцами влево / Esc", "Выход на Mac"),
        ]
        
        let lineHeight: CGFloat = 32.0
        let startY = windowHeight - 58.0
        
        for (i, gesture) in gestures.enumerated() {
            let y = startY - CGFloat(i) * lineHeight
            
            let iconLabel = NSTextField(labelWithString: gesture.0)
            iconLabel.frame = NSRect(x: 16, y: y, width: 190, height: 22)
            iconLabel.font = NSFont.systemFont(ofSize: 13)
            iconLabel.textColor = NSColor.white.withAlphaComponent(0.95)
            
            let descLabel = NSTextField(labelWithString: gesture.1)
            descLabel.frame = NSRect(x: 200, y: y, width: windowWidth - 216, height: 22)
            descLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
            descLabel.textColor = NSColor(calibratedRed: 0.4, green: 0.85, blue: 1.0, alpha: 1.0)
            descLabel.alignment = .right
            
            effectView.addSubview(iconLabel)
            effectView.addSubview(descLabel)
        }
        
        // Подсказка внизу
        let hintLabel = NSTextField(labelWithString: "Подсказка исчезнет через 4 сек")
        hintLabel.frame = NSRect(x: 16, y: 8, width: windowWidth - 32, height: 16)
        hintLabel.font = NSFont.systemFont(ofSize: 10)
        hintLabel.textColor = NSColor.white.withAlphaComponent(0.4)
        hintLabel.alignment = .center
        
        effectView.addSubview(titleLabel)
        effectView.addSubview(separator)
        effectView.addSubview(hintLabel)
        
        helpWindow.contentView = effectView
        helpWindow.orderFront(nil)
        
        // Плавное появление
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            helpWindow.animator().alphaValue = 0.95
        }
        
        self.helpOverlayWindow = helpWindow
        
        // Автоисчезновение через 4 сек
        helpDismissTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
            self?.hideHelpOverlay()
        }
    }
    
    func hideHelpOverlay() {
        helpDismissTimer?.invalidate()
        helpDismissTimer = nil
        
        guard let helpWindow = self.helpOverlayWindow else { return }
        
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.5
            helpWindow.animator().alphaValue = 0.0
        }, completionHandler: {
            helpWindow.orderOut(nil)
            self.helpOverlayWindow = nil
        })
    }
    
    // Всплывающее окно-инструкция при первом запуске
    var welcomeGuideWindow: NSWindow?
    
    func showWelcomeGuide() {
        // Если окно уже открыто — выносим на передний план
        if let existingWindow = welcomeGuideWindow {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let windowWidth: CGFloat = 480.0
        let pad: CGFloat = 30.0              // Горизонтальные отступы
        let contentWidth = windowWidth - pad * 2  // Ширина контента
        let cornerRadius: CGFloat = 20.0
        
        // ===== Динамическое измерение высоты текстовых блоков =====
        
        // Подзаголовок
        let subtitleFont = NSFont.systemFont(ofSize: 12, weight: .regular)
        let subtitleStr = Localization.get("guide_subtitle")
        let subtitleAttr = NSAttributedString(string: subtitleStr, attributes: [.font: subtitleFont])
        let subtitleHeight = ceil(subtitleAttr.boundingRect(
            with: NSSize(width: contentWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).height) + 4.0
        
        // Текст «Как это работает»
        let howFont = NSFont.systemFont(ofSize: 11.5, weight: .regular)
        let howStr = Localization.get("guide_how_text")
        let howAttr = NSAttributedString(string: howStr, attributes: [.font: howFont])
        let howTextHeight = ceil(howAttr.boundingRect(
            with: NSSize(width: contentWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).height) + 6.0
        
        // Подсказка (Tip)
        let tipFont = NSFont.systemFont(ofSize: 11, weight: .medium)
        let tipStr = Localization.get("guide_tip")
        let tipAttr = NSAttributedString(string: tipStr, attributes: [.font: tipFont])
        let tipHeight = ceil(tipAttr.boundingRect(
            with: NSSize(width: contentWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).height) + 4.0
        
        // ===== Вычисляем общую высоту окна =====
        let iconH: CGFloat = 48.0
        let titleH: CGFloat = 28.0
        let sectionH: CGFloat = 16.0
        let rowH: CGFloat = 28.0
        let rowCount: CGFloat = 7.0
        let checkH: CGFloat = 18.0
        let btnH: CGFloat = 36.0
        
        let windowHeight: CGFloat =
            40.0 +            // Верхний отступ
            iconH + 10.0 +   // Иконка + отступ
            titleH + 8.0 +   // Заголовок + отступ
            subtitleHeight + 16.0 +  // Подзаголовок + отступ
            1.0 + 14.0 +     // Разделитель + отступ
            sectionH + 6.0 + // «Как это работает» заголовок + отступ
            howTextHeight + 14.0 +   // Описание + отступ
            sectionH + 8.0 + // «Жесты» заголовок + отступ
            (rowH * rowCount) + 10.0 +  // Таблица жестов + отступ
            tipHeight + 14.0 +  // Подсказка + отступ
            1.0 + 14.0 +     // Разделитель + отступ
            checkH + 18.0 +  // Чекбокс + отступ
            btnH +            // Кнопка
            28.0              // Нижний отступ
        
        // ===== Создаём окно =====
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let x = (screenFrame.width - windowWidth) / 2.0 + screenFrame.origin.x
        let y = (screenFrame.height - windowHeight) / 2.0 + screenFrame.origin.y
        let frame = NSRect(x: x, y: y, width: windowWidth, height: windowHeight)
        
        let guideWindow = WelcomeGuideWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        guideWindow.isOpaque = false
        guideWindow.backgroundColor = .clear
        guideWindow.hasShadow = true
        guideWindow.level = .floating
        guideWindow.alphaValue = 0.0
        
        // Glassmorphism фон с нативной маской скругления (без артефактов углов)
        let effectView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight))
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        
        // Нативный macOS-способ скругления NSVisualEffectView через maskImage
        let edgeLength = 2.0 * cornerRadius + 1.0
        let maskImg = NSImage(size: NSSize(width: edgeLength, height: edgeLength), flipped: false) { rect in
            let bezierPath = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
            NSColor.black.set()
            bezierPath.fill()
            return true
        }
        maskImg.capInsets = NSEdgeInsets(top: cornerRadius, left: cornerRadius, bottom: cornerRadius, right: cornerRadius)
        maskImg.resizingMode = .stretch
        effectView.maskImage = maskImg
        
        guideWindow.contentView = effectView
        
        // ===== Layout: сверху вниз, currentY считает от верха окна =====
        var currentY = windowHeight - 40.0
        
        // — Иконка приложения —
        let iconView = NSImageView(frame: NSRect(x: (windowWidth - iconH) / 2.0, y: currentY - iconH, width: iconH, height: iconH))
        if let appIcon = NSImage(named: NSImage.applicationIconName) {
            iconView.image = appIcon
        }
        iconView.imageScaling = .scaleProportionallyUpOrDown
        effectView.addSubview(iconView)
        currentY -= iconH + 10.0
        
        // — Заголовок —
        let titleLabel = NSTextField(labelWithString: Localization.get("guide_title"))
        titleLabel.frame = NSRect(x: 20, y: currentY - titleH, width: windowWidth - 40, height: titleH)
        titleLabel.font = NSFont.systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.alignment = .center
        effectView.addSubview(titleLabel)
        currentY -= titleH + 8.0
        
        // — Подзаголовок —
        let subtitleLabel = NSTextField(wrappingLabelWithString: subtitleStr)
        subtitleLabel.frame = NSRect(x: pad, y: currentY - subtitleHeight, width: contentWidth, height: subtitleHeight)
        subtitleLabel.font = subtitleFont
        subtitleLabel.textColor = NSColor(white: 1.0, alpha: 0.55)
        subtitleLabel.alignment = .center
        subtitleLabel.maximumNumberOfLines = 0
        subtitleLabel.lineBreakMode = .byWordWrapping
        effectView.addSubview(subtitleLabel)
        currentY -= subtitleHeight + 16.0
        
        // — Разделитель 1 —
        let sep1 = NSBox(frame: NSRect(x: pad, y: currentY, width: contentWidth, height: 1))
        sep1.boxType = .separator
        effectView.addSubview(sep1)
        currentY -= 14.0
        
        // — Заголовок секции «Как это работает» —
        let howTitle = NSTextField(labelWithString: Localization.get("guide_how_title"))
        howTitle.frame = NSRect(x: pad, y: currentY - sectionH, width: contentWidth, height: sectionH)
        howTitle.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        howTitle.textColor = NSColor(calibratedRed: 0.4, green: 0.85, blue: 1.0, alpha: 1.0)
        howTitle.alignment = .left
        effectView.addSubview(howTitle)
        currentY -= sectionH + 6.0
        
        // — Текст описания (динамическая высота) —
        let howText = NSTextField(wrappingLabelWithString: howStr)
        howText.frame = NSRect(x: pad, y: currentY - howTextHeight, width: contentWidth, height: howTextHeight)
        howText.font = howFont
        howText.textColor = NSColor(white: 1.0, alpha: 0.78)
        howText.alignment = .left
        howText.maximumNumberOfLines = 0
        howText.lineBreakMode = .byWordWrapping
        effectView.addSubview(howText)
        currentY -= howTextHeight + 14.0
        
        // — Заголовок секции «Жесты управления» —
        let gesturesTitle = NSTextField(labelWithString: Localization.get("guide_gestures_title"))
        gesturesTitle.frame = NSRect(x: pad, y: currentY - sectionH, width: contentWidth, height: sectionH)
        gesturesTitle.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        gesturesTitle.textColor = NSColor(calibratedRed: 0.4, green: 0.85, blue: 1.0, alpha: 1.0)
        gesturesTitle.alignment = .left
        effectView.addSubview(gesturesTitle)
        currentY -= sectionH + 8.0
        
        // — Таблица жестов —
        let gestures: [(String, String, String)] = [
            ("☝️", Localization.get("guide_g1_action"), Localization.get("guide_g1_desc")),
            ("👆", Localization.get("guide_g2_action"), Localization.get("guide_g2_desc")),
            ("👆", Localization.get("guide_g3_action"), Localization.get("guide_g3_desc")),
            ("✌️", Localization.get("guide_g4_action"), Localization.get("guide_g4_desc")),
            ("🔊", Localization.get("guide_g7_action"), Localization.get("guide_g7_desc")),
            ("🤟", Localization.get("guide_g5_action"), Localization.get("guide_g5_desc")),
            ("⬅️", Localization.get("guide_g6_action"), Localization.get("guide_g6_desc")),
        ]
        
        for (i, gesture) in gestures.enumerated() {
            let rowY = currentY - CGFloat(i) * rowH - rowH
            
            // Чередующийся фон строк
            if i % 2 == 0 {
                let rowBg = NSView(frame: NSRect(x: 24, y: rowY - 2, width: windowWidth - 48, height: rowH))
                rowBg.wantsLayer = true
                rowBg.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.04).cgColor
                rowBg.layer?.cornerRadius = 6.0
                effectView.addSubview(rowBg)
            }
            
            let emojiLabel = NSTextField(labelWithString: gesture.0)
            emojiLabel.frame = NSRect(x: 32, y: rowY, width: 28, height: 22)
            emojiLabel.font = NSFont.systemFont(ofSize: 14)
            effectView.addSubview(emojiLabel)
            
            let actionLabel = NSTextField(labelWithString: gesture.1)
            actionLabel.frame = NSRect(x: 64, y: rowY, width: 200, height: 22)
            actionLabel.font = NSFont.systemFont(ofSize: 12.5)
            actionLabel.textColor = NSColor.white.withAlphaComponent(0.9)
            effectView.addSubview(actionLabel)
            
            let descLabel = NSTextField(labelWithString: gesture.2)
            descLabel.frame = NSRect(x: 260, y: rowY, width: windowWidth - 290, height: 22)
            descLabel.font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
            descLabel.textColor = NSColor(calibratedRed: 0.4, green: 0.85, blue: 1.0, alpha: 1.0)
            descLabel.alignment = .right
            effectView.addSubview(descLabel)
        }
        currentY -= CGFloat(gestures.count) * rowH + 10.0
        
        // — Подсказка (Tip) —
        let tipLabel = NSTextField(wrappingLabelWithString: tipStr)
        tipLabel.frame = NSRect(x: pad, y: currentY - tipHeight, width: contentWidth, height: tipHeight)
        tipLabel.font = tipFont
        tipLabel.textColor = NSColor(calibratedRed: 1.0, green: 0.85, blue: 0.35, alpha: 0.85)
        tipLabel.alignment = .center
        tipLabel.maximumNumberOfLines = 0
        tipLabel.lineBreakMode = .byWordWrapping
        effectView.addSubview(tipLabel)
        currentY -= tipHeight + 14.0
        
        // — Разделитель 2 —
        let sep2 = NSBox(frame: NSRect(x: pad, y: currentY, width: contentWidth, height: 1))
        sep2.boxType = .separator
        effectView.addSubview(sep2)
        currentY -= 14.0
        
        // — Чекбокс «Не показывать при запуске» —
        let checkbox = NSButton(checkboxWithTitle: Localization.get("guide_dont_show"), target: nil, action: nil)
        checkbox.frame = NSRect(x: pad, y: currentY - checkH, width: 300, height: checkH)
        checkbox.state = UserDefaults.standard.bool(forKey: "KVM_HideGuideOnStartup") ? .on : .off
        let checkboxCell = checkbox.cell as? NSButtonCell
        checkboxCell?.attributedTitle = NSAttributedString(
            string: Localization.get("guide_dont_show"),
            attributes: [
                .font: NSFont.systemFont(ofSize: 11.5),
                .foregroundColor: NSColor(white: 1.0, alpha: 0.6)
            ]
        )
        checkbox.tag = 9999
        effectView.addSubview(checkbox)
        currentY -= checkH + 18.0
        
        // — Кнопка «Начать» —
        let buttonWidth: CGFloat = 180.0
        let buttonX = (windowWidth - buttonWidth) / 2.0
        let startButton = NSButton(frame: NSRect(x: buttonX, y: currentY - btnH, width: buttonWidth, height: btnH))
        startButton.wantsLayer = true
        startButton.isBordered = false
        startButton.layer?.cornerRadius = btnH / 2.0
        startButton.layer?.backgroundColor = NSColor(calibratedRed: 0.2, green: 0.6, blue: 1.0, alpha: 0.85).cgColor
        let btnCell = startButton.cell as? NSButtonCell
        btnCell?.attributedTitle = NSAttributedString(
            string: Localization.get("guide_start_btn"),
            attributes: [
                .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
                .foregroundColor: NSColor.white
            ]
        )
        startButton.target = self
        startButton.action = #selector(dismissWelcomeGuide(_:))
        effectView.addSubview(startButton)
        
        self.welcomeGuideWindow = guideWindow
        
        // Показываем с анимацией
        NSApp.setActivationPolicy(.regular)
        guideWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            guideWindow.animator().alphaValue = 1.0
        }
    }
    
    @objc func dismissWelcomeGuide(_ sender: Any?) {
        guard let guideWindow = self.welcomeGuideWindow else { return }
        
        // Ищем чекбокс по tag в содержимом окна
        if let effectView = guideWindow.contentView {
            for subview in effectView.subviews {
                if let checkbox = subview as? NSButton, checkbox.tag == 9999 {
                    UserDefaults.standard.set(checkbox.state == .on, forKey: "KVM_HideGuideOnStartup")
                    break
                }
            }
        }
        
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            guideWindow.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            guideWindow.orderOut(nil)
            self?.welcomeGuideWindow = nil
            NSApp.setActivationPolicy(.accessory)
        })
    }
    
    @objc func showWelcomeGuideFromMenu() {
        showWelcomeGuide()
    }

    
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
            newRect = NSRect(x: screenWidth - Config.INITIAL_ZONE_WIDTH, y: 0, width: Config.INITIAL_ZONE_WIDTH, height: screenHeight)
        case .left:
            newRect = NSRect(x: 0, y: 0, width: Config.INITIAL_ZONE_WIDTH, height: screenHeight)
        case .top:
            newRect = NSRect(x: 0, y: screenHeight - Config.INITIAL_ZONE_WIDTH, width: screenWidth, height: Config.INITIAL_ZONE_WIDTH)
        }
        
        window?.setFrame(newRect, display: true)
        kvmView.frame = NSRect(x: 0, y: 0, width: newRect.width, height: newRect.height)
    }
    
    @objc func setEdgeToRight() { changeEdge(.right) }
    @objc func setEdgeToLeft() { changeEdge(.left) }
    @objc func setEdgeToTop() { changeEdge(.top) }
    
    @objc func setLanguageToRU() { changeLanguage("ru") }
    @objc func setLanguageToEN() { changeLanguage("en") }
    @objc func setLanguageToFR() { changeLanguage("fr") }
    @objc func setLanguageToIT() { changeLanguage("it") }
    @objc func setLanguageToDE() { changeLanguage("de") }
    @objc func setLanguageToES() { changeLanguage("es") }
    @objc func setLanguageToZH() { changeLanguage("zh") }
    
    func changeLanguage(_ lang: String) {
        Localization.currentLanguage = lang
        updateStatusMenu(self.lastStatus)
    }
    
    @objc func setScrollVeryFast() { changeScrollThreshold(30.0) }
    @objc func setScrollFast() { changeScrollThreshold(44.0) }
    @objc func setScrollNormal() { changeScrollThreshold(60.0) }
    @objc func setScrollSlow() { changeScrollThreshold(90.0) }
    @objc func setScrollVerySlow() { changeScrollThreshold(120.0) }
    
    func changeScrollThreshold(_ value: Double) {
        kvmView?.scrollThreshold = value
        UserDefaults.standard.set(value, forKey: "KVM_ScrollThreshold")
        updateStatusMenu(self.lastStatus)
    }
    
    @objc func setSwipeVeryFast() { changeSwipeThreshold(70.0) }
    @objc func setSwipeFast() { changeSwipeThreshold(105.0) }
    @objc func setSwipeNormal() { changeSwipeThreshold(140.0) }
    @objc func setSwipeSlow() { changeSwipeThreshold(192.0) }
    @objc func setSwipeVerySlow() { changeSwipeThreshold(245.0) }
    
    func changeSwipeThreshold(_ value: Double) {
        kvmView?.swipeThreshold = value
        UserDefaults.standard.set(value, forKey: "KVM_SwipeThreshold")
        updateStatusMenu(self.lastStatus)
    }
    
    // === Launch at Login (LaunchAgent) ===
    
    private var launchAgentPlistPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/LaunchAgents/com.ponano.pano.plist"
    }
    
    var isLaunchAtLoginEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            return FileManager.default.fileExists(atPath: launchAgentPlistPath)
        }
    }
    
    @objc func openLogsDirectory() {
        let homeDir = NSHomeDirectory()
        let logsPath = homeDir + "/Library/Logs/tv_kvm"
        let url = URL(fileURLWithPath: logsPath)
        NSWorkspace.shared.open(url)
    }
    
    @objc func toggleLaunchAtLogin() {
        let newState = !isLaunchAtLoginEnabled
        setLaunchAtLogin(enabled: newState)
        updateStatusMenu(self.lastStatus)
    }
    
    func setLaunchAtLogin(enabled: Bool) {
        if #available(macOS 13.0, *) {
            // Используем современный API SMAppService (macOS 13+)
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                    print("[Swift] Launch at Login enabled via SMAppService")
                } else {
                    try SMAppService.mainApp.unregister()
                    print("[Swift] Launch at Login disabled via SMAppService")
                }
            } catch {
                print("[Swift] SMAppService error: \(error.localizedDescription)")
                // Fallback на LaunchAgent если SMAppService не сработал
                setLaunchAtLoginViaLaunchAgent(enabled: enabled)
            }
        } else {
            // Для macOS 11–12: используем LaunchAgent plist
            setLaunchAtLoginViaLaunchAgent(enabled: enabled)
        }
    }
    
    private func setLaunchAtLoginViaLaunchAgent(enabled: Bool) {
        if enabled {
            // Определяем путь к .app бандлу
            let bundlePath = Bundle.main.bundlePath
            let appPath: String
            if bundlePath.hasSuffix(".app") {
                appPath = bundlePath
            } else {
                // Если запущено напрямую как бинарник, ищем .app рядом
                let parentDir = (bundlePath as NSString).deletingLastPathComponent
                appPath = "\(parentDir)/Pano.app"
            }
            
            let plistContent = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>com.ponano.pano</string>
                <key>ProgramArguments</key>
                <array>
                    <string>/usr/bin/open</string>
                    <string>-a</string>
                    <string>\(appPath)</string>
                </array>
                <key>RunAtLoad</key>
                <true/>
            </dict>
            </plist>
            """
            
            // Создаём директорию LaunchAgents если её нет
            let launchAgentsDir = (launchAgentPlistPath as NSString).deletingLastPathComponent
            try? FileManager.default.createDirectory(atPath: launchAgentsDir, withIntermediateDirectories: true)
            
            do {
                try plistContent.write(toFile: launchAgentPlistPath, atomically: true, encoding: .utf8)
                print("[Swift] Launch at Login enabled via LaunchAgent: \(launchAgentPlistPath)")
            } catch {
                print("[Swift] Failed to write LaunchAgent plist: \(error.localizedDescription)")
            }
        } else {
            // Удаляем LaunchAgent plist
            try? FileManager.default.removeItem(atPath: launchAgentPlistPath)
            print("[Swift] Launch at Login disabled, removed LaunchAgent plist")
        }
    }
    
    @objc func toggleVoiceInput() {
        if speechManager == nil {
            let sm = SpeechManager()
            sm.onTranscriptionUpdate = { [weak self] text in
                DispatchQueue.main.async {
                    if let textField = self?.inputTextField {
                        textField.stringValue = text
                        self?.adjustInputLayout()
                        
                        // Мгновенная посимвольная трансляция на ТВ в реальном времени
                        if let base64Text = text.data(using: .utf8)?.base64EncodedString() {
                            self?.socketClient.send(cmd: "SET_TEXT \(base64Text)")
                        }
                    }
                }
            }
            sm.onStateChange = { [weak self] isRecording in
                DispatchQueue.main.async {
                    self?.micButton?.isRecording = isRecording
                }
            }
            sm.onError = { [weak self] errorMsg in
                print("[Speech Error] \(errorMsg)")
                DispatchQueue.main.async {
                    self?.micButton?.isRecording = false
                }
            }
            self.speechManager = sm
        }
        
        guard let sm = speechManager else { return }
        
        if sm.isRecording {
            sm.stopRecording()
        } else {
            sm.requestAuthorization { [weak self] granted in
                guard let self = self else { return }
                if granted {
                    self.speechManager?.startRecording()
                } else {
                    print("[Speech] Authorization denied")
                    let alert = NSAlert()
                    alert.messageText = Localization.get("denied_mic_title")
                    alert.informativeText = Localization.get("denied_mic_text")
                    alert.addButton(withTitle: "OK")
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
    
    func requestSpeechAndMicrophonePermissions() {
        SFSpeechRecognizer.requestAuthorization { status in
            if status == .authorized {
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    if granted {
                        print("[Speech] Speech and Microphone permissions successfully granted on startup.")
                    } else {
                        print("[Speech Warning] Microphone permission denied on startup.")
                    }
                }
            } else {
                print("[Speech Warning] Speech Recognition permission denied on startup.")
            }
        }
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[Swift] applicationDidFinishLaunching started. Initializing window...")
        
        #if !TESTING
        requestSpeechAndMicrophonePermissions()
        #endif
        
        // Автоматически запускаем Node.js-мост в фоновом режиме
        startNodeBridge()
        
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
            kvmView.scrollThreshold = 60.0
        }
        
        // Загружаем сохраненный порог свайпов из UserDefaults
        if let savedSwipe = UserDefaults.standard.object(forKey: "KVM_SwipeThreshold") as? Double {
            kvmView.swipeThreshold = savedSwipe
        } else {
            kvmView.swipeThreshold = 140.0
        }
        
        window.contentView = kvmView
        window.makeFirstResponder(kvmView)
        // Настройка колбэков SpeechManager отложена до ленивого создания в toggleVoiceInput()
        
        // Делаем иконку программы скрытой из Дока, чтобы не мешала
        // Если нужно показать инструкцию — она сама переключит в .regular
        let shouldShowGuide = !UserDefaults.standard.bool(forKey: "KVM_HideGuideOnStartup")
        if !shouldShowGuide {
            NSApp.setActivationPolicy(.accessory)
        }
        
        // Устанавливаем корректный фрейм триггерной зоны
        updateWindowFrame()
        
        // Настройка Меню в строке состояния (Menu Bar)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Устанавливаем начальное значение, чтобы иконка была видна сразу
        statusItem.button?.image = makeMenuBarIcon(isActive: false)
        statusItem.button?.title = ""
        startBlinking()  // Мигание при старте (подключение)
        let initialMenu = NSMenu()
        initialMenu.addItem(NSMenuItem(title: Localization.get("cancel_connection"), action: #selector(self.terminate), keyEquivalent: "q"))
        statusItem.menu = initialMenu
        
        // Колбэки сокета
        socketClient.onStatusChange = { [weak self] status in
            self?.updateStatusMenu(status)
        }
        
        socketClient.onImeShow = { [weak self] text in
            DispatchQueue.main.async {
                self?.showInputWindow(initialText: text)
            }
        }
        
        socketClient.onImeUpdate = { [weak self] text in
            DispatchQueue.main.async {
                // Обновляем текст в уже открытом HUD без повторного показа
                if let textField = self?.inputTextField, self?.inputWindow != nil {
                    textField.stringValue = text
                    self?.adjustInputLayout()
                }
            }
        }
        
        socketClient.onImeHide = { [weak self] in
            DispatchQueue.main.async {
                // Автоматическое закрытие HUD при смене фокуса на ТВ
                // Не отправляем KEYCODE_BACK, потому что ТВ сам закрыл клавиатуру
                if self?.inputWindow != nil {
                    self?.dismissInputWindow(cancelled: false)
                }
            }
        }
        
        socketClient.onAppChange = { [weak self] appPackage in
            DispatchQueue.main.async {
                self?.kvmView?.currentAppPackage = appPackage
            }
        }
        
        // Стартуем локальный TCP-клиент
        socketClient.connect()
        
        let tvIP = getTVIP()
        if tvIP == "auto" {
            startBonjourDiscovery()
        } else {
            // Мы не вызываем connectKVM() с жестким таймаутом 0.5с здесь, чтобы избежать состояния гонки
            // (когда сокет еще не успел подключиться к запускаемому Node.js мосту).
            // Вместо этого мы оставляем shouldAutoConnect = true.
            // При подключении сокета мост пришлет статус DISCONNECTED, и метод updateStatusMenu()
            // автоматически и надежно выполнит подключение через connectKVM().
        }
        
        // Показываем инструкцию при запуске (если пользователь не отключил)
        if shouldShowGuide {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                print("[Swift] Showing welcome guide...")
                self?.showWelcomeGuide()
            }
        }
    }
    
    func startBonjourDiscovery() {
        print("[Swift] Starting Bonjour TV Discovery...")
        updateStatusMenu("SEARCHING")
        
        discoveryTimer?.invalidate()
        discoveryTimer = Timer.scheduledTimer(timeInterval: 8.0, target: self, selector: #selector(discoveryTimeout), userInfo: nil, repeats: false)
        
        tvDiscovery = TVDiscovery()
        tvDiscovery?.onTVFound = { [weak self] resolvedIP in
            guard let self = self else { return }
            print("[Swift Discovery] Found TV IP: \(resolvedIP)")
            
            self.discoveryTimer?.invalidate()
            self.discoveryTimer = nil
            
            self.resolvedIP = resolvedIP
            self.startNodeBridge(resolvedIP: resolvedIP)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                print("[Swift] Sending CONNECT command to start connection...")
                self.socketClient.send(cmd: "CONNECT")
            }
        }
        tvDiscovery?.onSearchFailed = { [weak self] in
            guard let self = self else { return }
            print("[Swift Discovery] Bonjour search failed, returning to disconnected status")
            self.discoveryTimer?.invalidate()
            self.discoveryTimer = nil
            self.updateStatusMenu("DISCONNECTED")
        }
        tvDiscovery?.startSearch()
    }
    
    @objc func discoveryTimeout() {
        print("[Swift Discovery] Bonjour auto-discovery timed out, prompting user for manual IP input...")
        
        tvDiscovery?.stopSearch()
        discoveryTimer?.invalidate()
        discoveryTimer = nil
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.promptForIP { [weak self] ip in
                guard let self = self else { return }
                print("[Swift Discovery] User manually entered IP: \(ip)")
                
                self.resolvedIP = ip
                self.startNodeBridge(resolvedIP: ip)
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    print("[Swift] Sending CONNECT command to start connection...")
                    self.socketClient.send(cmd: "CONNECT")
                }
            }
        }
    }
    
    func promptForIP(completion: @escaping (String) -> Void) {
        let alert = NSAlert()
        alert.messageText = Localization.get("manual_ip_title")
        alert.informativeText = Localization.get("manual_ip_message")
        alert.addButton(withTitle: Localization.get("connect"))
        alert.addButton(withTitle: Localization.get("cancel"))
        
        let inputTextField = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        inputTextField.placeholderString = "192.168.1.50"
        alert.accessoryView = inputTextField
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let rawIP = inputTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Защита: Ограничиваем длину ввода для предотвращения переполнения буфера
            guard rawIP.count <= 15 else {
                showInvalidIPAlert()
                return
            }
            
            // Проверяем валидность IPv4 адреса через inet_pton из библиотеки Darwin (POSIX-стандарт)
            var sin = sockaddr_in()
            let isValid = rawIP.withCString { cstr in
                inet_pton(AF_INET, cstr, &sin.sin_addr) == 1
            }
            
            if isValid {
                completion(rawIP)
            } else {
                showInvalidIPAlert()
            }
        }
    }
    
    func showInvalidIPAlert() {
        DispatchQueue.main.async {
            let errorAlert = NSAlert()
            errorAlert.messageText = Localization.get("invalid_ip_title")
            errorAlert.informativeText = Localization.get("invalid_ip_message")
            errorAlert.addButton(withTitle: "OK")
            errorAlert.runModal()
            
            // Повторный запуск диалога ввода для удобства пользователя
            self.discoveryTimeout()
        }
    }
    
    @objc func connectKVM() {
        let ip = getTVIP()
        if ip == "auto" {
            startBonjourDiscovery()
        } else {
            print("[Swift] Sending CONNECT command to start connection...")
            socketClient.send(cmd: "CONNECT")
        }
    }
    
    @objc func disconnectKVM() {
        print("[Swift] Sending DISCONNECT command to break connection...")
        socketClient.send(cmd: "DISCONNECT")
        
        discoveryTimer?.invalidate()
        discoveryTimer = nil
        
        if getTVIP() == "auto" {
            tvDiscovery?.stopSearch()
            tvDiscovery = nil
            // Переключаем статус на DISCONNECTED
            self.updateStatusMenu("DISCONNECTED")
        }
    }
    
    @objc func manuallyTriggerTextInput() {
        print("[Swift KVM] Menu item click: Manually triggering text input HUD.")
        self.showInputWindow(initialText: "")
    }
    
    @objc func unpairKVM() {
        let alert = NSAlert()
        alert.messageText = Localization.get("unpair_title")
        alert.informativeText = Localization.get("unpair_text")
        alert.addButton(withTitle: Localization.get("forget_tv_btn"))
        alert.addButton(withTitle: Localization.get("cancel"))
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            print("[Swift] Sending UNPAIR command to delete credentials...")
            socketClient.send(cmd: "UNPAIR")
            
            resolvedIP = nil
            discoveryTimer?.invalidate()
            discoveryTimer = nil
        }
    }
    
    @objc func startPairing() {
        print("[Swift] Sending CONNECT command to start pairing...")
        socketClient.send(cmd: "CONNECT")
    }
    
    @objc func forceReconnect() {
        print("[Swift] User forced reconnect to TV.")
        socketClient.send(cmd: "CONNECT")
        updateStatusMenu("CONNECTING")
    }
    
    @objc func forceRestartBridge() {
        print("[Swift] User forced bridge restart.")
        nodeRestartCount = 0  // Сбрасываем счётчик
        stopNodeBridge()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.startNodeBridge()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.socketClient.connect()
            }
        }
        updateStatusMenu("CONNECTING")
    }
    
    @objc func terminate() {
        socketClient.send(cmd: "DISCONNECT")
        socketClient.disconnect()
        stopNodeBridge()
        NSApp.terminate(nil)
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        stopNodeBridge()
    }
    
    // Создаёт иконку монитора/ТВ для menu bar (18x18)
    func makeMenuBarIcon(isActive: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let color: NSColor = isActive ? .controlTextColor : NSColor.controlTextColor.withAlphaComponent(0.35)
            color.setStroke()
            
            // Корпус монитора (скруглённый прямоугольник)
            let bodyRect = NSRect(x: 1.5, y: 5, width: 15, height: 10)
            let body = NSBezierPath(roundedRect: bodyRect, xRadius: 1.5, yRadius: 1.5)
            body.lineWidth = 1.4
            body.stroke()
            
            // Экран — заливка при активном состоянии
            if isActive {
                let screenRect = NSRect(x: 3, y: 6.5, width: 12, height: 7)
                color.withAlphaComponent(0.15).setFill()
                NSBezierPath(rect: screenRect).fill()
            }
            
            // Ножка монитора
            let stand = NSBezierPath()
            stand.move(to: NSPoint(x: 7, y: 5))
            stand.line(to: NSPoint(x: 7, y: 3))
            stand.move(to: NSPoint(x: 11, y: 5))
            stand.line(to: NSPoint(x: 11, y: 3))
            // Подставка
            stand.move(to: NSPoint(x: 5, y: 3))
            stand.line(to: NSPoint(x: 13, y: 3))
            stand.lineWidth = 1.2
            stand.stroke()
            
            return true
        }
        image.isTemplate = true  // Позволяет macOS адаптировать цвет под тему
        return image
    }
    
    func startBlinking() {
        stopBlinking()
        blinkVisible = true
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            guard let self = self, let button = self.statusItem.button else { return }
            self.blinkVisible.toggle()
            button.image = self.blinkVisible ? self.makeMenuBarIcon(isActive: false) : nil
        }
    }
    
    func stopBlinking() {
        blinkTimer?.invalidate()
        blinkTimer = nil
        blinkVisible = true
    }
    
    func updateStatusMenu(_ status: String) {
        if status == "CERT_REJECTED" {
            print("[Swift Socket] TV rejected the TLS certificate! Triggering self-diagnostics alert.")
            self.shouldAutoConnect = false
            self.disconnectKVM()
            
            #if !TESTING
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = Localization.get("cert_rejected_title")
                alert.informativeText = Localization.get("cert_rejected_text")
                alert.addButton(withTitle: Localization.get("cert_rejected_repair"))
                alert.addButton(withTitle: Localization.get("cancel"))
                
                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    print("[Swift] Self-Diagnostics: User agreed to re-pair. Sending UNPAIR and starting pairing.")
                    self.socketClient.send(cmd: "UNPAIR")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.socketClient.send(cmd: "CONNECT")
                    }
                }
            }
            #else
            // В режиме тестирования симулируем авто-сброс и переподключение для TDD верификации
            print("[Swift Test] Self-Diagnostics: Auto-resetting pairing credentials in test mode.")
            self.socketClient.send(cmd: "UNPAIR")
            self.socketClient.send(cmd: "CONNECT")
            #endif
            
            self.updateStatusMenu("DISCONNECTED")
            return
        }
        
        if status == "CONFLICT" {
            print("[Swift Socket] Connection conflict detected! Disabling autoconnect to prevent port war.")
            self.shouldAutoConnect = false
            self.disconnectKVM()
            
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = Localization.get("conflict_title")
                alert.informativeText = Localization.get("conflict_text")
                alert.addButton(withTitle: "OK")
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
            
            let bundlePath = Bundle.main.bundlePath
            let parentDir = (bundlePath as NSString).deletingLastPathComponent
            let currentDir = FileManager.default.currentDirectoryPath
            let homeDir = NSHomeDirectory()
            
            let possibleCertPaths = [
                "\(homeDir)/.tv_kvm_credentials/cert.json",
                "\(bundlePath)/Contents/Resources/bridge/.credentials/cert.json",
                "\(parentDir)/.credentials/cert.json",
                "\(currentDir)/.credentials/cert.json"
            ]
            
            var hasCert = false
            for path in possibleCertPaths {
                if FileManager.default.fileExists(atPath: path) {
                    hasCert = true
                    break
                }
            }
            
            if let button = self.statusItem.button {
                switch status {
                case "READY":
                    self.stopBlinking()
                    button.image = self.makeMenuBarIcon(isActive: true)
                    button.title = ""
                    self.nodeRestartCount = 0  // Сбрасываем счётчик рестартов при успехе
                    
                    // - Меню при активном подключении
                    menu.addItem(NSMenuItem(title: Localization.get("disconnect_tv"), action: #selector(self.disconnectKVM), keyEquivalent: "d"))
                    menu.addItem(NSMenuItem(title: Localization.get("type_text_tv"), action: #selector(self.manuallyTriggerTextInput), keyEquivalent: "t"))
                    menu.addItem(NSMenuItem(title: Localization.get("forget_tv"), action: #selector(self.unpairKVM), keyEquivalent: "u"))
                    
                case "NEED_PIN":
                    self.startBlinking()
                    button.title = ""
                    
                    // - Меню при вводе PIN
                    menu.addItem(NSMenuItem(title: Localization.get("cancel_pairing"), action: #selector(self.disconnectKVM), keyEquivalent: "c"))
                    
                    self.promptForPIN { [weak self] pin in
                        self?.socketClient.send(cmd: "PIN \(pin)")
                    }
                    
                case "SEARCHING":
                    self.startBlinking()
                    button.image = self.makeMenuBarIcon(isActive: false)
                    button.title = ""
                    
                    let searchItem = NSMenuItem(title: Localization.get("searching_tv"), action: nil, keyEquivalent: "")
                    searchItem.isEnabled = false
                    menu.addItem(searchItem)
                    menu.addItem(NSMenuItem(title: Localization.get("cancel_connection"), action: #selector(self.disconnectKVM), keyEquivalent: "c"))
                    
                case "CONNECTING":
                    self.startBlinking()
                    button.title = ""
                    
                    // - Меню при подключении
                    menu.addItem(NSMenuItem(title: Localization.get("cancel_connection"), action: #selector(self.disconnectKVM), keyEquivalent: "c"))
                    
                case "TV_UNREACHABLE":
                    self.stopBlinking()
                    button.image = self.makeMenuBarIcon(isActive: false)
                    button.title = ""
                    
                    // Подсказка для пользователя
                    let hintItem = NSMenuItem(title: Localization.get("tv_unreachable_hint"), action: nil, keyEquivalent: "")
                    hintItem.isEnabled = false
                    menu.addItem(hintItem)
                    menu.addItem(NSMenuItem(title: Localization.get("reconnect_now"), action: #selector(self.forceReconnect), keyEquivalent: "r"))
                    menu.addItem(NSMenuItem(title: Localization.get("forget_tv"), action: #selector(self.unpairKVM), keyEquivalent: "u"))
                    
                case "BRIDGE_DEAD":
                    self.stopBlinking()
                    button.image = self.makeMenuBarIcon(isActive: false)
                    button.title = ""
                    
                    let hintItem = NSMenuItem(title: Localization.get("bridge_restart_failed"), action: nil, keyEquivalent: "")
                    hintItem.isEnabled = false
                    menu.addItem(hintItem)
                    menu.addItem(NSMenuItem(title: Localization.get("reconnect_now"), action: #selector(self.forceRestartBridge), keyEquivalent: "r"))
                    
                default: // - DISCONNECTED
                    self.stopBlinking()
                    button.image = self.makeMenuBarIcon(isActive: false)
                    button.title = ""
                    
                    if hasCert {
                        // - Если сопряжение уже выполнено, даем кнопку подключения
                        menu.addItem(NSMenuItem(title: Localization.get("connect_tv"), action: #selector(self.connectKVM), keyEquivalent: "c"))
                        menu.addItem(NSMenuItem(title: Localization.get("forget_tv"), action: #selector(self.unpairKVM), keyEquivalent: "u"))
                        
                        if self.shouldAutoConnect {
                            self.shouldAutoConnect = false
                            // - Небольшая задержка 0.5с, чтобы дать сокету полностью инициализироваться
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                                self?.connectKVM()
                            }
                        }
                    } else {
                        // - Если сопряжения еще нет, даем кнопку запуска сопряжения
                        menu.addItem(NSMenuItem(title: Localization.get("start_pairing"), action: #selector(self.startPairing), keyEquivalent: "p"))
                    }
                }
            }
            
            menu.addItem(NSMenuItem.separator())
            
            // - Настройка подменю с выбором сторон
            let edgeMenu = NSMenu()
            
            let rightItem = NSMenuItem(title: Localization.get("edge_right"), action: #selector(self.setEdgeToRight), keyEquivalent: "")
            rightItem.state = (self.kvmView?.activeEdge == .right) ? .on : .off
            edgeMenu.addItem(rightItem)
            
            let leftItem = NSMenuItem(title: Localization.get("edge_left"), action: #selector(self.setEdgeToLeft), keyEquivalent: "")
            leftItem.state = (self.kvmView?.activeEdge == .left) ? .on : .off
            edgeMenu.addItem(leftItem)
            
            let topItem = NSMenuItem(title: Localization.get("edge_top"), action: #selector(self.setEdgeToTop), keyEquivalent: "")
            topItem.state = (self.kvmView?.activeEdge == .top) ? .on : .off
            edgeMenu.addItem(topItem)
            
            let edgeMenuItem = NSMenuItem(title: Localization.get("tv_entry_edge"), action: nil, keyEquivalent: "")
            edgeMenuItem.submenu = edgeMenu
            menu.addItem(edgeMenuItem)
            
            // - Настройка подменю с выбором плавности/чувствительности прокрутки
            let scrollMenu = NSMenu()
            let threshold = self.kvmView?.scrollThreshold ?? 60.0
            
            let scrollVeryFast = NSMenuItem(title: Localization.get("sens_very_fast"), action: #selector(self.setScrollVeryFast), keyEquivalent: "")
            scrollVeryFast.state = (threshold == 30.0) ? .on : .off
            scrollMenu.addItem(scrollVeryFast)
            
            let scrollFast = NSMenuItem(title: Localization.get("sens_fast"), action: #selector(self.setScrollFast), keyEquivalent: "")
            scrollFast.state = (threshold == 44.0) ? .on : .off
            scrollMenu.addItem(scrollFast)
            
            let scrollNormal = NSMenuItem(title: Localization.get("sens_medium"), action: #selector(self.setScrollNormal), keyEquivalent: "")
            scrollNormal.state = (threshold == 60.0) ? .on : .off
            scrollMenu.addItem(scrollNormal)
            
            let scrollSlow = NSMenuItem(title: Localization.get("sens_slow"), action: #selector(self.setScrollSlow), keyEquivalent: "")
            scrollSlow.state = (threshold == 90.0) ? .on : .off
            scrollMenu.addItem(scrollSlow)
            
            let scrollVerySlow = NSMenuItem(title: Localization.get("sens_very_slow"), action: #selector(self.setScrollVerySlow), keyEquivalent: "")
            scrollVerySlow.state = (threshold == 120.0) ? .on : .off
            scrollMenu.addItem(scrollVerySlow)
            
            let scrollMenuItem = NSMenuItem(title: Localization.get("scroll_sensitivity"), action: nil, keyEquivalent: "")
            scrollMenuItem.submenu = scrollMenu
            menu.addItem(scrollMenuItem)
            
            // - Настройка подменю с выбором плавности/чувствительности свайпов
            let swipeMenu = NSMenu()
            let swipeThreshold = self.kvmView?.swipeThreshold ?? 140.0
            
            let swipeVeryFast = NSMenuItem(title: Localization.get("sens_very_fast"), action: #selector(self.setSwipeVeryFast), keyEquivalent: "")
            swipeVeryFast.state = (swipeThreshold == 70.0) ? .on : .off
            swipeMenu.addItem(swipeVeryFast)
            
            let swipeFast = NSMenuItem(title: Localization.get("sens_fast"), action: #selector(self.setSwipeFast), keyEquivalent: "")
            swipeFast.state = (swipeThreshold == 105.0) ? .on : .off
            swipeMenu.addItem(swipeFast)
            
            let swipeNormal = NSMenuItem(title: Localization.get("sens_medium"), action: #selector(self.setSwipeNormal), keyEquivalent: "")
            swipeNormal.state = (swipeThreshold == 140.0) ? .on : .off
            swipeMenu.addItem(swipeNormal)
            
            let swipeSlow = NSMenuItem(title: Localization.get("sens_slow"), action: #selector(self.setSwipeSlow), keyEquivalent: "")
            swipeSlow.state = (swipeThreshold == 192.0) ? .on : .off
            swipeMenu.addItem(swipeSlow)
            
            let swipeVerySlow = NSMenuItem(title: Localization.get("sens_very_slow"), action: #selector(self.setSwipeVerySlow), keyEquivalent: "")
            swipeVerySlow.state = (swipeThreshold == 245.0) ? .on : .off
            swipeMenu.addItem(swipeVerySlow)
            
            let swipeMenuItem = NSMenuItem(title: Localization.get("swipe_sensitivity"), action: nil, keyEquivalent: "")
            swipeMenuItem.submenu = swipeMenu
            menu.addItem(swipeMenuItem)
            
            // - Настройка подменю с выбором языка
            let langMenu = NSMenu()
            let currentLang = Localization.currentLanguage
            
            let langRU = NSMenuItem(title: "Русский", action: #selector(self.setLanguageToRU), keyEquivalent: "")
            langRU.state = (currentLang == "ru") ? .on : .off
            langMenu.addItem(langRU)
            
            let langEN = NSMenuItem(title: "English", action: #selector(self.setLanguageToEN), keyEquivalent: "")
            langEN.state = (currentLang == "en") ? .on : .off
            langMenu.addItem(langEN)
            
            let langFR = NSMenuItem(title: "Français", action: #selector(self.setLanguageToFR), keyEquivalent: "")
            langFR.state = (currentLang == "fr") ? .on : .off
            langMenu.addItem(langFR)
            
            let langIT = NSMenuItem(title: "Italiano", action: #selector(self.setLanguageToIT), keyEquivalent: "")
            langIT.state = (currentLang == "it") ? .on : .off
            langMenu.addItem(langIT)
            
            let langDE = NSMenuItem(title: "Deutsch", action: #selector(self.setLanguageToDE), keyEquivalent: "")
            langDE.state = (currentLang == "de") ? .on : .off
            langMenu.addItem(langDE)
            
            let langES = NSMenuItem(title: "Español", action: #selector(self.setLanguageToES), keyEquivalent: "")
            langES.state = (currentLang == "es") ? .on : .off
            langMenu.addItem(langES)
            
            let langZH = NSMenuItem(title: "简体中文", action: #selector(self.setLanguageToZH), keyEquivalent: "")
            langZH.state = (currentLang == "zh") ? .on : .off
            langMenu.addItem(langZH)
            
            let langMenuItem = NSMenuItem(title: Localization.get("language"), action: nil, keyEquivalent: "")
            langMenuItem.submenu = langMenu
            menu.addItem(langMenuItem)
            
            // - Автозапуск при входе в систему
            let launchAtLoginItem = NSMenuItem(title: Localization.get("launch_at_login"), action: #selector(self.toggleLaunchAtLogin), keyEquivalent: "")
            launchAtLoginItem.state = self.isLaunchAtLoginEnabled ? .on : .off
            menu.addItem(launchAtLoginItem)
            
            // - Открыть папку логов
            let logsItem = NSMenuItem(title: Localization.get("show_logs"), action: #selector(self.openLogsDirectory), keyEquivalent: "")
            menu.addItem(logsItem)
            
            menu.addItem(NSMenuItem(title: Localization.get("guide_menu_item"), action: #selector(self.showWelcomeGuideFromMenu), keyEquivalent: "h"))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: Localization.get("exit_kvm"), action: #selector(self.terminate), keyEquivalent: "q"))
            
            self.statusItem.menu = menu
        }
    }
    

    func adjustInputLayout() {
        guard let window = self.inputWindow,
              let textField = self.inputTextField,
              let container = self.inputContainer,
              let titleLabel = self.inputTitleLabel,
              let helpLabel = self.inputHelpLabel,
              let mic = self.micButton else { return }
        
        let containerWidth = 500.0 - 40.0 - 52.0 // 408
        let textFieldWidth = containerWidth - 16.0 // 392
        
        // Рассчитываем необходимую высоту текстового поля на основе текста
        let constraintSize = NSSize(width: textFieldWidth, height: CGFloat.greatestFiniteMagnitude)
        let size = textField.cell?.cellSize(forBounds: NSRect(origin: .zero, size: constraintSize)) ?? NSSize(width: textFieldWidth, height: 26)
        
        let minTextHeight: CGFloat = 26.0
        let textHeight = max(minTextHeight, ceil(size.height))
        let deltaHeight = textHeight - minTextHeight
        
        let newContainerHeight = 42.0 + deltaHeight
        let newWindowHeight = 130.0 + deltaHeight
        
        if textField.frame.height != textHeight {
            // Вычисляем новую позицию окна, сохраняя неподвижным верхний край
            let oldFrame = window.frame
            let oldTop = oldFrame.origin.y + oldFrame.size.height
            let newY = oldTop - newWindowHeight
            let newWindowFrame = NSRect(x: oldFrame.origin.x, y: newY, width: oldFrame.size.width, height: newWindowHeight)
            
            // Устанавливаем новый фрейм для окна
            window.setFrame(newWindowFrame, display: true, animate: false)
            
            // Обновляем фрейм визуального оверлея
            if let effectView = window.contentView {
                effectView.frame = NSRect(x: 0, y: 0, width: oldFrame.size.width, height: newWindowHeight)
            }
            
            // Обновляем позицию заголовка (привязан к верхнему краю)
            titleLabel.frame = NSRect(x: 20, y: newWindowHeight - 30, width: oldFrame.size.width - 40, height: 16)
            
            // Обновляем контейнер текстового поля
            container.frame = NSRect(x: 20, y: 45, width: containerWidth, height: newContainerHeight)
            
            // Обновляем само текстовое поле внутри контейнера
            textField.frame = NSRect(x: 8, y: 8, width: textFieldWidth, height: textHeight)
            
            // Обновляем кнопку микрофона, центрируя ее вертикально относительно нового контейнера
            let newMicY = 45.0 + deltaHeight / 2.0
            mic.frame = NSRect(x: 20 + containerWidth + 10, y: newMicY, width: 42, height: 42)
            
            // helpLabel остается привязанным к низу (y: 18)
            helpLabel.frame = NSRect(x: 20, y: 18, width: oldFrame.size.width - 40, height: 14)
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
        let y = (screenFrame.height - windowHeight) * 0.65 + screenFrame.origin.y
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
        
        let titleLabel = NSTextField(labelWithString: Localization.get("hud_title"))
        titleLabel.frame = NSRect(x: 20, y: windowHeight - 30, width: windowWidth - 40, height: 16)
        titleLabel.textColor = NSColor(white: 0.9, alpha: 0.75)
        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        titleLabel.alignment = .left
        effectView.addSubview(titleLabel)
        self.inputTitleLabel = titleLabel
        
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
        textField.placeholderString = Localization.get("hud_placeholder")
        textField.focusRingType = .none
        textField.delegate = self
        textField.stringValue = initialText
        textField.cell?.isScrollable = false
        textField.cell?.wraps = true
        textField.maximumNumberOfLines = 0
        
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
        
        let helpLabel = NSTextField(labelWithString: Localization.get("hud_help"))
        helpLabel.frame = NSRect(x: 20, y: 18, width: windowWidth - 40, height: 14)
        helpLabel.textColor = NSColor(white: 0.9, alpha: 0.45)
        helpLabel.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        helpLabel.alignment = .left
        effectView.addSubview(helpLabel)
        self.inputHelpLabel = helpLabel
        
        self.inputWindow = window
        
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(textField)
        
        if !initialText.isEmpty {
            textField.currentEditor()?.selectAll(nil)
        }
        DispatchQueue.main.async {
            self.adjustInputLayout()
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
        
        window.orderOut(nil)
        self.inputWindow = nil
        self.inputTextField = nil
        self.inputContainer = nil
        self.inputTitleLabel = nil
        self.inputHelpLabel = nil
        self.micButton = nil
        self.isTyping = false
        
        // Сбрасываем локальный текстовый буфер на мосте
        socketClient.send(cmd: "RESET")
        
        if cancelled {
            // Принудительно закрываем виртуальную клавиатуру на ТВ, отправляя Back
            socketClient.send(cmd: "KEY KEYCODE_BACK")
        }
        
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
        alert.messageText = Localization.get("pairing_title")
        alert.informativeText = Localization.get("pairing_text")
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: Localization.get("cancel"))
        
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
        
        if textField === self.inputTextField {
            DispatchQueue.main.async {
                self.adjustInputLayout()
            }
        }
    }
    
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            print("[Swift KVM] Enter key intercepted in text field delegate.")
            self.submitText()
            return true
        } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            print("[Swift KVM] Escape key intercepted in text field delegate.")
            self.dismissInputWindow(cancelled: true)
            return true
        }
        return false
    }
}
