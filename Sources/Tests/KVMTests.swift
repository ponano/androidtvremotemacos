import Cocoa
import Foundation
import AppKit
import Network
import ServiceManagement
import Speech
import AVFoundation
import Darwin

#if TESTING
// Мок для состояния кнопок мыши
class MockMouseStateProvider: MouseStateProviding {
    var pressedMouseButtons: Int = 0
}

// Мок для симуляции сессии перетаскивания (Drag & Drop)
class MockDraggingInfo: NSObject, NSDraggingInfo {
    var draggingDestinationWindow: NSWindow? { return nil }
    var draggingSourceOperationMask: NSDragOperation { return .copy }
    var draggingLocation: NSPoint { return .zero }
    var draggingSource: Any? { return nil }
    var draggingPasteboard: NSPasteboard { return NSPasteboard.withUniqueName() }
    var draggingSequenceNumber: Int { return 0 }
    
    var draggingFormation: NSDraggingFormation {
        get { return .default }
        set {}
    }
    var animatesToDestination: Bool {
        get { return false }
        set {}
    }
    var numberOfValidItemsForDrop: Int {
        get { return 0 }
        set {}
    }
    
    func enumerateDraggingItems(
        options: NSDraggingItemEnumerationOptions = [],
        for view: NSView?,
        classes: [AnyClass],
        searchOptions: [NSPasteboard.ReadingOptionKey : Any] = [:],
        using block: @escaping (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {}
    
    var springLoadingHighlight: NSSpringLoadingHighlight { return .none }
    
    var draggedImageLocation: NSPoint { return .zero }
    var draggedImage: NSImage? { return nil }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    func resetSpringLoading() {}
}

class KVMTests {
    func runAllTests() -> Bool {
        var allPassed = true
        
        print("======== ЗАПУСК ЮНИТ-ТЕСТОВ И ЮЗАБИЛИТИ-ТЕСТОВ (TDD) ========")
        
        let tests: [(String, () -> Bool)] = [
            ("testNormalMouseEntered_StartsTimer", testNormalMouseEntered_StartsTimer),
            ("testMouseEnteredWithButtonPressed_DoesNotStartTimer", testMouseEnteredWithButtonPressed_DoesNotStartTimer),
            ("testDraggingEntered_InvalidatesTimerAndBlocksActivation", testDraggingEntered_InvalidatesTimerAndBlocksActivation),
            ("testSelfDiagnostics_CertRejected", testSelfDiagnostics_CertRejected),
            ("testKeyboardMapping_CyrillicAndLatin", testKeyboardMapping_CyrillicAndLatin),
            ("testTextInputWindow_Initialization", testTextInputWindow_Initialization),
            ("testTextInputWindow_DynamicResizing", testTextInputWindow_DynamicResizing),
            ("testKVMView_SensitivitySettings", testKVMView_SensitivitySettings),
            ("testWelcomeGuideAndHelpOverlay_Initialization", testWelcomeGuideAndHelpOverlay_Initialization),
            ("testInfoPlist_Validity", testInfoPlist_Validity),
            ("testTVDiscovery_BonjourSearchAndResolve", testTVDiscovery_BonjourSearchAndResolve)
        ]
        
        for (name, test) in tests {
            if runTest(name: name, test: test) {
                print("✅ \(name): ПРОЙДЕН")
            } else {
                print("❌ \(name): ПРОВАЛЕН")
                allPassed = false
            }
        }
        
        print("=============================================================")
        return allPassed
    }
    
    private func runTest(name: String, test: () -> Bool) -> Bool {
        return test()
    }
    
    func testNormalMouseEntered_StartsTimer() -> Bool {
        let view = KVMView(frame: .zero)
        let mockProvider = MockMouseStateProvider()
        mockProvider.pressedMouseButtons = 0
        view.mouseStateProvider = mockProvider
        
        let dummyEvent = NSEvent()
        view.mouseEntered(with: dummyEvent)
        
        guard let timer = view.activationTimer else {
            print("   -> Ошибка: таймер не был запущен")
            return false
        }
        
        return timer.isValid
    }
    
    func testMouseEnteredWithButtonPressed_DoesNotStartTimer() -> Bool {
        let view = KVMView(frame: .zero)
        let mockProvider = MockMouseStateProvider()
        mockProvider.pressedMouseButtons = 1
        view.mouseStateProvider = mockProvider
        
        let dummyEvent = NSEvent()
        view.mouseEntered(with: dummyEvent)
        
        if view.activationTimer != nil {
            print("   -> Ошибка: таймер был запущен, несмотря на нажатую кнопку мыши")
            return false
        }
        
        return true
    }
    
    func testDraggingEntered_InvalidatesTimerAndBlocksActivation() -> Bool {
        let view = KVMView(frame: .zero)
        
        let mockProvider = MockMouseStateProvider()
        mockProvider.pressedMouseButtons = 0
        view.mouseStateProvider = mockProvider
        view.mouseEntered(with: NSEvent())
        
        if view.activationTimer == nil {
            print("   -> Ошибка инициализации теста: таймер не запустился")
            return false
        }
        
        let mockDragInfo = MockDraggingInfo()
        let resultOperation = view.draggingEntered(mockDragInfo)
        
        if view.activationTimer != nil {
            print("   -> Ошибка: таймер не был сброшен при входе Drag-сессии")
            return false
        }
        
        if !resultOperation.isEmpty {
            print("   -> Ошибка: возвращен непустой NSDraggingOperation (\(resultOperation))")
            return false
        }
        
        return true
    }
    
    // Тест 4: Самодиагностика при отклонении сертификата безопасности
    func testSelfDiagnostics_CertRejected() -> Bool {
        let delegate = AppDelegate()
        delegate.socketClient = SocketClient() // Мокаем для изоляции сети
        
        delegate.shouldAutoConnect = true
        delegate.updateStatusMenu("CERT_REJECTED")
        
        // Должно выключить автоподключение для исключения бесконечной циклической перегрузки ТВ
        if delegate.shouldAutoConnect {
            print("   -> Ошибка: shouldAutoConnect не был выставлен в false при CERT_REJECTED")
            return false
        }
        
        return true
    }
    
    // Тест 5: Раскладка клавиатуры (Латиница, Кириллица, спецсимволы)
    func testKeyboardMapping_CyrillicAndLatin() -> Bool {
        let view = KVMView(frame: .zero)
        
        // 1. Проверяем стандартную латиницу (EN)
        guard view.mapCharToKeyCode("A") == "KEYCODE_A",
              view.mapCharToKeyCode("z") == "KEYCODE_Z",
              view.mapCharToKeyCode(" ") == "KEYCODE_SPACE" else {
            print("   -> Ошибка: неверный маппинг латиницы")
            return false
        }
        
        // 2. Проверяем кириллицу (RU)
        guard view.mapCharToKeyCode("Ф") == "KEYCODE_A",
              view.mapCharToKeyCode("ы") == "KEYCODE_S",
              view.mapCharToKeyCode("ю") == "KEYCODE_PERIOD",
              view.mapCharToKeyCode("ё") == "KEYCODE_GRAVE" else {
            print("   -> Ошибка: неверный маппинг кириллицы (QWERTY)")
            return false
        }
        
        // 3. Проверяем спецсимволы, требующие фолбэка (должны возвращать nil)
        if view.mapCharToKeyCode("?") != nil || view.mapCharToKeyCode("№") != nil {
            print("   -> Ошибка: спецсимволы должны возвращать nil для фолбэка на Base64 CHAR")
            return false
        }
        
        return true
    }
    
    // Тест 6: Окно текстового ввода (HUD) и графические кнопки/элементы
    func testTextInputWindow_Initialization() -> Bool {
        let delegate = AppDelegate()
        
        // Инициализируем HUD окно с начальным текстом "Test text"
        delegate.showInputWindow(initialText: "Test text")
        
        guard let window = delegate.inputWindow else {
            print("   -> Ошибка: окно TextInputWindow не было создано")
            return false
        }
        
        // Проверяем характеристики окна
        if window.level != .statusBar {
            print("   -> Ошибка: TextInputWindow должно иметь статус statusBar")
            return false
        }
        
        // Проверяем текстовое поле ввода
        guard let textField = delegate.inputTextField else {
            print("   -> Ошибка: FocusTextField не создан")
            return false
        }
        
        if textField.stringValue != "Test text" {
            print("   -> Ошибка: значение текстового поля не соответствует переданному")
            return false
        }
        
        // Проверяем наличие кнопки микрофона (MicButton)
        guard let mic = delegate.micButton else {
            print("   -> Ошибка: Кнопка микрофона MicButton не создана")
            return false
        }
        
        // Проверяем изменение состояния кнопки микрофона при активации записи
        mic.isRecording = true
        if !mic.isRecording {
            print("   -> Ошибка: не удалось выставить состояние isRecording на кнопке микрофона")
            return false
        }
        
        // Закрываем окно (dismiss)
        delegate.dismissInputWindow(cancelled: true)
        if delegate.inputWindow != nil {
            print("   -> Ошибка: окно не было уничтожено после dismiss")
            return false
        }
        
        return true
    }
    
    // Тест: Динамическое изменение размеров поля ввода при длинном тексте
    func testTextInputWindow_DynamicResizing() -> Bool {
        let delegate = AppDelegate()
        
        // 1. Инициализируем HUD окно с коротким текстом
        delegate.showInputWindow(initialText: "Short text")
        
        guard let window = delegate.inputWindow,
              let textField = delegate.inputTextField,
              let container = delegate.inputContainer else {
            print("   -> Ошибка: компоненты окна ввода не были созданы")
            return false
        }
        
        // Проверяем начальные характеристики
        let initialWindowHeight = window.frame.height
        let initialTextFieldHeight = textField.frame.height
        let initialTop = window.frame.origin.y + initialWindowHeight
        
        // По умолчанию wraps должно быть включено, isScrollable выключено
        if textField.cell?.wraps != true || textField.cell?.isScrollable == true {
            print("   -> Ошибка: свойства переноса текста на FocusTextField не настроены")
            return false
        }
        
        // 2. Имитируем длинный многострочный текст, превышающий размеры
        let longText = "Это очень-очень длинный текст, который гарантированно займет несколько строк в нашем поле ввода, так как он превышает ширину контейнера в 392 пикселя!"
        textField.stringValue = longText
        
        // Вызываем перерасчет
        delegate.adjustInputLayout()
        
        let newWindowHeight = window.frame.height
        let newTextFieldHeight = textField.frame.height
        let newTop = window.frame.origin.y + newWindowHeight
        
        // Проверяем, что размеры увеличились
        if newTextFieldHeight <= initialTextFieldHeight {
            print("   -> Ошибка: высота текстового поля не увеличилась после длинного текста (было: \(initialTextFieldHeight), стало: \(newTextFieldHeight))")
            return false
        }
        
        if newWindowHeight <= initialWindowHeight {
            print("   -> Ошибка: высота окна не увеличилась")
            return false
        }
        
        // Проверяем, что верхняя грань осталась неподвижной (с погрешностью 0.5 пикселя)
        if abs(newTop - initialTop) > 0.5 {
            print("   -> Ошибка: верхняя грань окна сместилась (было: \(initialTop), стало: \(newTop))")
            return false
        }
        
        // Закрываем окно
        delegate.dismissInputWindow(cancelled: true)
        
        return true
    }
    
    // Тест 7: Чувствительность жестов тачпада
    func testKVMView_SensitivitySettings() -> Bool {
        let view = KVMView(frame: .zero)
        
        // По умолчанию чувствительность должна быть средней (medium)
        if view.scrollThreshold != 60.0 || view.swipeThreshold != 140.0 {
            print("   -> Ошибка: дефолтные пороги чувствительности сбиты")
            return false
        }
        
        // Симулируем изменение чувствительности на Very Fast (очень быстрая)
        view.scrollThreshold = 30.0
        view.swipeThreshold = 70.0
        
        if view.scrollThreshold != 30.0 || view.swipeThreshold != 70.0 {
            print("   -> Ошибка: не удалось изменить пороги чувствительности")
            return false
        }
        
        return true
    }
    
    // Тест 8: Приветственное руководство и оверлей подсказок (Welcome Guide & Help Overlay)
    func testWelcomeGuideAndHelpOverlay_Initialization() -> Bool {
        let delegate = AppDelegate()
        let oldDelegate = NSApp.delegate
        NSApp.delegate = delegate
        
        // 1. Проверяем оверлей подсказок (Help Overlay)
        delegate.showHelpOverlay()
        guard let helpWindow = delegate.helpOverlayWindow else {
            print("   -> Ошибка: HelpOverlayWindow не создан")
            NSApp.delegate = oldDelegate
            return false
        }
        
        if helpWindow.level != .floating {
            print("   -> Ошибка: HelpOverlayWindow должен быть в режиме .floating")
            NSApp.delegate = oldDelegate
            return false
        }
        
        delegate.hideHelpOverlay()
        
        // 2. Проверяем приветственное руководство (Welcome Guide)
        delegate.showWelcomeGuide()
        guard let guideWindow = delegate.welcomeGuideWindow else {
            print("   -> Ошибка: welcomeGuideWindow не создан")
            NSApp.delegate = oldDelegate
            return false
        }
        
        if guideWindow.styleMask.contains(.resizable) {
            print("   -> Ошибка: приветственное окно не должно менять размер")
            NSApp.delegate = oldDelegate
            return false
        }
        
        // 3. Автоматическая проверка закрытия окна по клавише Esc
        guard let activeGuideWindow = delegate.welcomeGuideWindow as? WelcomeGuideWindow else {
            print("   -> Ошибка: welcomeGuideWindow не является WelcomeGuideWindow")
            NSApp.delegate = oldDelegate
            return false
        }
        
        let escEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: activeGuideWindow.windowNumber,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 53 // Escape
        )
        
        if let event = escEvent {
            let handled = activeGuideWindow.performKeyEquivalent(with: event)
            if !handled {
                print("   -> Ошибка: Esc не был обработан в WelcomeGuideWindow")
                NSApp.delegate = oldDelegate
                return false
            }
        } else {
            print("   -> Ошибка: Не удалось создать NSEvent для Esc")
            NSApp.delegate = oldDelegate
            return false
        }
        
        // Даем закрывающей анимации отработать в цикле событий Cocoa
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.35))
        
        if delegate.welcomeGuideWindow != nil {
            print("   -> Ошибка: welcomeGuideWindow не был удален после нажатия Esc")
            NSApp.delegate = oldDelegate
            return false
        }
        
        NSApp.delegate = oldDelegate
        return true
    }
    
    // Тест 9: Валидация структуры Info.plist (CFBundleExecutable и права доступа TCC)
    func testInfoPlist_Validity() -> Bool {
        let plistPath = "Info.plist"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: plistPath)),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            print("   -> Ошибка: Не удалось прочитать Info.plist с диска")
            return false
        }
        
        guard let exec = plist["CFBundleExecutable"] as? String else {
            print("   -> Ошибка: Ключ CFBundleExecutable отсутствует в Info.plist")
            return false
        }
        
        if exec != "Pano" {
            print("   -> Ошибка: CFBundleExecutable равен '\(exec)' вместо 'Pano'")
            return false
        }
        
        if plist["NSMicrophoneUsageDescription"] == nil {
            print("   -> Ошибка: Ключ NSMicrophoneUsageDescription отсутствует в Info.plist")
            return false
        }
        
        if plist["NSSpeechRecognitionUsageDescription"] == nil {
            print("   -> Ошибка: Ключ NSSpeechRecognitionUsageDescription отсутствует в Info.plist")
            return false
        }
        
        return true
    }
    
    // Тест 9: Автопоиск по Bonjour и разрешение IP локальной службы
    func testTVDiscovery_BonjourSearchAndResolve() -> Bool {
        // Создаем локальную Bonjour-службу для имитации телевизора
        let mockService = NetService(domain: "local.", type: "_androidtvremote2._tcp.", name: "Mock Test TV", port: 12345)
        
        // Публикуем мок-службу локально
        mockService.publish()
        
        var foundIP: String? = nil
        var isFinished = false
        
        let discovery = TVDiscovery()
        discovery.onTVFound = { ip in
            foundIP = ip
            isFinished = true
        }
        discovery.onSearchFailed = {
            isFinished = true
        }
        
        discovery.startSearch()
        
        // Ожидаем в цикле RunLoop, чтобы дать возможность выполниться событиям Bonjour
        let timeoutDate = Date(timeIntervalSinceNow: 4.0)
        while !isFinished && Date() < timeoutDate {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
        }
        
        // Сворачиваем наши службы
        discovery.stopSearch()
        mockService.stop()
        
        if !isFinished {
            print("   -> Ошибка: тест автопоиска превысил таймаут 4.0с")
            return false
        }
        
        guard let ip = foundIP else {
            print("   -> Ошибка: телевизор был найден, но его IP не был разрешен")
            return false
        }
        
        print("   -> Успешно разрешен IP локальной службы: \(ip)")
        return ip == "127.0.0.1" || ip == "localhost" || ip.hasPrefix("192.") || ip.hasPrefix("10.") || ip.hasPrefix("172.") || ip == "::1"
    }
}


#endif
