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

// Класс динамической локализации на 6 языков (автоматическое определение при запуске)
struct Localization {
    static var currentLanguage: String {
        get {
            if let saved = UserDefaults.standard.string(forKey: "KVM_Language") {
                return saved
            }
            let pref = Locale.preferredLanguages.first?.prefix(2).lowercased() ?? "en"
            let supported = ["ru", "en", "fr", "it", "de", "es", "zh"]
            return supported.contains(pref) ? pref : "en"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "KVM_Language")
        }
    }
    
    static func get(_ key: String) -> String {
        guard let translations = strings[key] else { return key }
        return translations[currentLanguage] ?? translations["en"] ?? key
    }
    
    private static let strings: [String: [String: String]] = [
        "language": [
            "ru": "Язык интерфейса",
            "en": "Interface Language",
            "fr": "Langue de l'interface",
            "it": "Lingua dell'interfaccia",
            "de": "Oberflächensprache",
            "es": "Idioma de la interfaz",
            "zh": "界面语言"
        ],
        "kvm_connected": [
            "ru": "🟢 Pano: Подключен",
            "en": "🟢 Pano: Connected",
            "fr": "🟢 Pano: Connecté",
            "it": "🟢 Pano: Connesso",
            "de": "🟢 Pano: Verbunden",
            "es": "🟢 Pano: Conectado",
            "zh": "🟢 Pano: 已连接"
        ],
        "kvm_enter_pin": [
            "ru": "🟡 Pano: Введите PIN",
            "en": "🟡 Pano: Enter PIN",
            "fr": "🟡 Pano: Saisir le code PIN",
            "it": "🟡 Pano: Inserisci PIN",
            "de": "🟡 Pano: PIN eingeben",
            "es": "🟡 Pano: Introducir PIN",
            "zh": "🟡 Pano: 输入 PIN 码"
        ],
        "kvm_connecting": [
            "ru": "🟡 Pano: Подключение...",
            "en": "🟡 Pano: Connecting...",
            "fr": "🟡 Pano: Connexion...",
            "it": "🟡 Pano: Connessione...",
            "de": "🟡 Pano: Verbinden...",
            "es": "🟡 Pano: Conectando...",
            "zh": "🟡 Pano: 正在连接..."
        ],
        "kvm_disconnected": [
            "ru": "🔴 Pano: Отключен",
            "en": "🔴 Pano: Disconnected",
            "fr": "🔴 Pano: Déconnecté",
            "it": "🔴 Pano: Disconnesso",
            "de": "🔴 Pano: Trennen",
            "es": "🔴 Pano: Desconectado",
            "zh": "🔴 Pano: 已断开"
        ],
        "disconnect_tv": [
            "ru": "Отключить от ТВ",
            "en": "Disconnect from TV",
            "fr": "Se connecter à la TV",
            "it": "Disconnetti dalla TV",
            "de": "Von TV trennen",
            "es": "Desconectar de la TV",
            "zh": "断开电视连接"
        ],
        "type_text_tv": [
            "ru": "📝 Ввести текст на ТВ (Ctrl+Shift+T)",
            "en": "📝 Type text on TV (Ctrl+Shift+T)",
            "fr": "📝 Saisir du texte sur la TV (Ctrl+Shift+T)",
            "it": "📝 Scrivi testo sulla TV (Ctrl+Shift+T)",
            "de": "📝 Text auf TV eingeben (Ctrl+Shift+T)",
            "es": "📝 Escribir texto en la TV (Ctrl+Shift+T)",
            "zh": "📝 在电视上输入文本 (Ctrl+Shift+T)"
        ],
        "forget_tv": [
            "ru": "Разорвать сопряжение (Забыть ТВ)",
            "en": "Forget TV (Unpair)",
            "fr": "Oublier la TV (Dissocier)",
            "it": "Dimentica TV (Disassocia)",
            "de": "TV vergessen (Entkoppeln)",
            "es": "Olvidar TV (Desvincular)",
            "zh": "取消配对 (忘记此电视)"
        ],
        "cancel_pairing": [
            "ru": "Отменить сопряжение",
            "en": "Cancel Pairing",
            "fr": "Annuler l'association",
            "it": "Annulla associazione",
            "de": "Kopplung abbrechen",
            "es": "Cancelar vinculación",
            "zh": "取消配对"
        ],
        "cancel_connection": [
            "ru": "Отменить подключение",
            "en": "Cancel Connection",
            "fr": "Annuler la connexion",
            "it": "Annulla connessione",
            "de": "Verbindung abbrechen",
            "es": "Cancelar conexión",
            "zh": "取消连接"
        ],
        "connect_tv": [
            "ru": "Подключить к ТВ",
            "en": "Connect to TV",
            "fr": "Se connecter à la TV",
            "it": "Connetti alla TV",
            "de": "Mit TV verbinden",
            "es": "Conectar a la TV",
            "zh": "连接到电视"
        ],
        "start_pairing": [
            "ru": "Запустить сопряжение (Pairing)",
            "en": "Start Pairing",
            "fr": "Démarrer l'association",
            "it": "Avvia associazione",
            "de": "Kopplung starten",
            "es": "Iniciar vinculación",
            "zh": "开始配对"
        ],
        "tv_entry_edge": [
            "ru": "Сторона перехода на ТВ",
            "en": "TV Entry Edge",
            "fr": "Bord de transition vers la TV",
            "it": "Bordo di transizione alla TV",
            "de": "TV-Übergangskante",
            "es": "Borde de transición a la TV",
            "zh": "电视切换边缘"
        ],
        "edge_right": [
            "ru": "👉 Справа (по умолчанию)",
            "en": "👉 Right (Default)",
            "fr": "👉 Droite (Par défaut)",
            "it": "👉 Destra (Predefinito)",
            "de": "👉 Rechts (Standard)",
            "es": "👉 Derecha (Por defecto)",
            "zh": "👉 右侧 (默认)"
        ],
        "edge_left": [
            "ru": "👈 Слева",
            "en": "👈 Left",
            "fr": "👈 Gauche",
            "it": "👈 Sinistra",
            "de": "👈 Links",
            "es": "👈 Izquierda",
            "zh": "👈 左侧"
        ],
        "edge_top": [
            "ru": "👆 Сверху",
            "en": "👆 Top",
            "fr": "👆 Haut",
            "it": "👆 Sopra",
            "de": "👆 Oben",
            "es": "👆 Arriba",
            "zh": "👆 顶部"
        ],
        "scroll_sensitivity": [
            "ru": "Чувствительность прокрутки",
            "en": "Scrolling Sensitivity",
            "fr": "Sensibilité du défilement",
            "it": "Sensibilità di scorrimento",
            "de": "Scroll-Empfindlichkeit",
            "es": "Sensibilidad de desplazamiento",
            "zh": "滚动敏感度"
        ],
        "swipe_sensitivity": [
            "ru": "Чувствительность свайпов",
            "en": "Swipe Sensitivity",
            "fr": "Sensibilité des balayages",
            "it": "Sensibilità di scorrimento veloce",
            "de": "Swipe-Empfindlichkeit",
            "es": "Sensibilidad de gestos deslizar",
            "zh": "轻扫敏感度"
        ],
        "sens_very_fast": [
            "ru": "Очень быстрая (чувствительная)",
            "en": "Very Fast (Sensitive)",
            "fr": "Très rapide (Sensible)",
            "it": "Molto veloce (Sensibile)",
            "de": "Sehr schnell (Empfindlich)",
            "es": "Muy rápida (Sensible)",
            "zh": "极快 (高灵敏)"
        ],
        "sens_fast": [
            "ru": "Быстрая",
            "en": "Fast",
            "fr": "Rapide",
            "it": "Veloce",
            "de": "Schnell",
            "es": "Rápida",
            "zh": "快速"
        ],
        "sens_medium": [
            "ru": "Средняя (по умолчанию)",
            "en": "Medium (Default)",
            "fr": "Moyenne (Par défaut)",
            "it": "Media (Predefinito)",
            "de": "Mittel (Standard)",
            "es": "Media (Por defecto)",
            "zh": "中等 (默认)"
        ],
        "sens_slow": [
            "ru": "Плавная / Медленная",
            "en": "Slow / Gentle",
            "fr": "Lente / Fluide",
            "it": "Lenta / Fluida",
            "de": "Langsam / Sanft",
            "es": "Lenta / Fluida",
            "zh": "平滑 / 慢速"
        ],
        "sens_very_slow": [
            "ru": "Очень медленная",
            "en": "Very Slow",
            "fr": "Très lente",
            "it": "Molto lenta",
            "de": "Sehr langsam",
            "es": "Muy lenta",
            "zh": "极慢"
        ],
        "exit_kvm": [
            "ru": "Выйти из Pano",
            "en": "Exit Pano",
            "fr": "Quitter Pano",
            "it": "Esci da Pano",
            "de": "Pano beenden",
            "es": "Salir de Pano",
            "zh": "退出 Pano"
        ],
        "conflict_title": [
            "ru": "Конфликт подключений",
            "en": "Connection Conflict",
            "fr": "Conflit de connexion",
            "it": "Conflitto di connessione",
            "de": "Verbindungskonflikt",
            "es": "Conflicto de conexión",
            "zh": "连接冲突"
        ],
        "conflict_text": [
            "ru": "Управление телевизором было перехвачено другим устройством (например, приложением Google TV на телефоне).\n\nАвтоматическое переподключение приостановлено во избежание конфликтов. Вы можете подключиться заново вручную через меню Pano после отключения другого пульта.",
            "en": "TV control was intercepted by another device (e.g., Google TV app on your phone).\n\nAuto-reconnect is suspended to avoid conflicts. You can manually reconnect via the Pano menu after disconnecting the other remote.",
            "fr": "Le contrôle de la TV a été intercepté par un autre appareil (ex. l'application Google TV sur le téléphone).\n\nLa reconnexion automatique est suspendue pour éviter les conflits. Vous pouvez vous reconnecter manuellement via le menu Pano après avoir déconnecté l'autre télécommande.",
            "it": "Il controllo della TV è stato intercettato da un altro dispositivo (es. app Google TV sul telefono).\n\nLa riconnessione automatica è sospesa per evitare conflitti. Puoi riconnetterti manualmente tramite il menu Pano dopo aver disconnesso l'altro telecomando.",
            "de": "Die TV-Steuerung wurde von einem anderen Gerät abgefangen (z. B. der Google TV-App auf Ihrem Telefon).\n\nDie automatische Wiederverbindung wurde vorübergehend ausgesetzt, um Konflikte zu vermeiden. Sie können nach dem Trennen der anderen Fernbedienung manuell eine neue Verbindung über das Pano-Menü herstellen.",
            "es": "El control de la TV fue interceptado por otro dispositivo (ej. la aplicación Google TV en el teléfono).\n\nLa reconexión automática se suspende para evitar conflictos. Puede volver a conectarse manualmente a través del menú Pano después de desconectar el otro mando.",
            "zh": "电视控制权已被其他设备抢占 (例如手机上的 Google TV 应用)。\n\n为避免冲突，已暂停自动重新连接。您可以在断开其他遥控器后，通过 Pano 菜单手动重新连接。"
        ],
        "unpair_title": [
            "ru": "Разорвать сопряжение?",
            "en": "Unpair TV?",
            "fr": "Dissocier la TV?",
            "it": "Disassociare la TV?",
            "de": "TV entkoppeln?",
            "es": "¿Desvincular la TV?",
            "zh": "取消配对？"
        ],
        "unpair_text": [
            "ru": "Вы уверены, что хотите разорвать сопряжение с текущим телевизором и удалить сохраненные сертификаты?",
            "en": "Are you sure you want to unpair from the current TV and delete saved certificates?",
            "fr": "Êtes-vous sûr de vouloir vous dissocier de la TV actuelle et supprimer les certificats enregistrés?",
            "it": "Sei sicuro di voler disassociare la TV corrente e cancellare i certificati salvati?",
            "de": "Sind Sie sicher, dass Sie die Kopplung mit dem aktuellen TV aufheben und die gespeicherten Zertifikate löschen möchten?",
            "es": "¿Está seguro de que desea desvincular la TV actual y eliminar los certificados guardados?",
            "zh": "您确定要取消与当前电视的配对并删除保存的证书吗？"
        ],
        "forget_tv_btn": [
            "ru": "Забыть ТВ",
            "en": "Forget TV",
            "fr": "Oublier la TV",
            "it": "Dimentica TV",
            "de": "TV vergessen",
            "es": "Olvidar TV",
            "zh": "忘记电视"
        ],
        "cancel": [
            "ru": "Отмена",
            "en": "Cancel",
            "fr": "Annuler",
            "it": "Annulla",
            "de": "Abbrechen",
            "es": "Cancelar",
            "zh": "取消"
        ],
        "pairing_title": [
            "ru": "Сопряжение с Google TV",
            "en": "Pairing with Google TV",
            "fr": "Association avec Google TV",
            "it": "Associazione con Google TV",
            "de": "Kopplung mit Google TV",
            "es": "Vinculación con Google TV",
            "zh": "配对 Google TV"
        ],
        "pairing_text": [
            "ru": "Введите 6-значный PIN-код, отображаемый на экране вашего телевизора:",
            "en": "Enter the 6-digit PIN code displayed on your TV screen:",
            "fr": "Saisissez le code PIN à 6 chiffres affiché sur l'écran de votre TV:",
            "it": "Inserisci il codice PIN a 6 cifre visualizzato sullo schermo della TV:",
            "de": "Geben Sie den 6-stelligen PIN-Code ein, der auf Ihrem TV-Bildschirm angezeigt wird:",
            "es": "Introduzca el código PIN de 6 dígitos que se muestra en la pantalla de su TV:",
            "zh": "请输入电视屏幕上显示的 6 位 PIN 码："
        ],
        "hud_title": [
            "ru": "ВВОД ТЕКСТА НА TV",
            "en": "TYPE TEXT ON TV",
            "fr": "SAISIE DE TEXTE SUR LA TV",
            "it": "SCRIVI TESTO SULLA TV",
            "de": "TEXT EINGEBEN AUF TV",
            "es": "ESCRIBIR TEXTO EN LA TV",
            "zh": "在电视上输入文本"
        ],
        "hud_placeholder": [
            "ru": "Введите текст для отправки...",
            "en": "Enter text to send...",
            "fr": "Saisissez du texte à envoyer...",
            "it": "Inserisci il testo da inviare...",
            "de": "Text zum Senden eingeben...",
            "es": "Introduzca el texto para enviar...",
            "zh": "输入要发送的文本..."
        ],
        "hud_help": [
            "ru": "Enter — отправить • Esc — отмена • Поддержка RU / EN / FR / IT / DE / ES / ZH",
            "en": "Enter — send • Esc — cancel • Supports RU / EN / FR / IT / DE / ES / ZH",
            "fr": "Entrée — envoyer • Échap — annuler • Supporte RU / EN / FR / IT / DE / ES / ZH",
            "it": "Invio — invia • Esc — annulla • Supporta RU / EN / FR / IT / DE / ES / ZH",
            "de": "Eingabe — Senden • Esc — Abbrechen • Unterstützt RU / EN / FR / IT / DE / ES / ZH",
            "es": "Intro — enviar • Esc — cancelar • Admite RU / EN / FR / IT / DE / ES / ZH",
            "zh": "Enter — 发送 • Esc — 取消 • 支持 RU / EN / FR / IT / DE / ES / ZH"
        ],
        "denied_mic_title": [
            "ru": "Доступ к микрофону отклонен",
            "en": "Microphone Access Denied",
            "fr": "Accès au micro refusé",
            "it": "Accesso al microfono negato",
            "de": "Mikrofonzugriff verweigert",
            "es": "Acceso al micrófono denegado",
            "zh": "麦克风访问被拒绝"
        ],
        "denied_mic_text": [
            "ru": "Пожалуйста, разрешите доступ к Микрофону и Распознаванию речи для Pano в Системных настройках macOS в разделе Безопасность и Конфиденциальность.",
            "en": "Please allow Microphone and Speech Recognition access for Pano in macOS System Settings under Privacy & Security.",
            "fr": "Veuillez autoriser l'accès au microphone et à la reconnaissance vocale pour Pano dans les réglages système macOS sous Confidentialité et sécurité.",
            "it": "Autorizza l'accesso al microfono e al riconoscimento vocale per Pano nelle Impostazioni di sistema di macOS sotto Privacy e Sicurezza.",
            "de": "Bitte erlauben Sie den Zugriff auf das Mikrofon und die Spracherkennung für Pano in den macOS-Systemeinstellungen unter Datenschutz & Sicherheit.",
            "es": "Por favor, permita el acceso al micrófono y al reconocimiento de voz para Pano en la Configuración del sistema de macOS bajo Privacidad y Seguridad.",
            "zh": "请在 macOS 系统设置的“隐私与安全性”中，允许 Pano 访问麦克风和进行语音识别。"
        ],
        "err_recognition_request_failed": [
            "ru": "Не удалось создать запрос распознавания.",
            "en": "Could not create recognition request.",
            "fr": "Impossible de créer la demande de reconnaissance.",
            "it": "Impossibile creare la richiesta di riconoscimento.",
            "de": "Erkennungsanfrage konnte nicht erstellt werden.",
            "es": "No se pudo crear la solicitud de reconocimiento."
        ],
        "err_audio_engine_failed": [
            "ru": "Ошибка запуска аудиодвижка",
            "en": "Failed to start audio engine",
            "fr": "Échec du démarrage du moteur audio",
            "it": "Impossibile avviare il motore audio",
            "de": "Fehler beim Starten der Audio-Engine",
            "es": "Error al iniciar el motor de audio"
        ]
    ]
}

// Класс для живого распознавания речи с микрофона Mac на системной локали (автовыбор RU / EN / FR / IT / DE / ES)
class SpeechManager {
    private var speechRecognizer: SFSpeechRecognizer?
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
        
        let localeId: String
        switch Localization.currentLanguage {
        case "ru": localeId = "ru-RU"
        case "en": localeId = "en-US"
        case "fr": localeId = "fr-FR"
        case "it": localeId = "it-IT"
        case "de": localeId = "de-DE"
        case "es": localeId = "es-ES"
        case "zh": localeId = "zh-CN"
        default: localeId = "en-US"
        }
        
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: localeId))
        
        let inputNode = audioEngine.inputNode
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            onError?(Localization.get("err_recognition_request_failed"))
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
            onError?("\(Localization.get("err_audio_engine_failed")): \(error.localizedDescription)")
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
    var onImeUpdate: ((String) -> Void)?
    var onImeHide: (() -> Void)?
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
        } else if trimmed.hasPrefix("IME_UPDATE") {
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
            print("[Swift Socket] IME_UPDATE received, text: \"\(text)\"")
            onImeUpdate?(text)
        } else if trimmed == "IME_HIDE" {
            print("[Swift Socket] IME_HIDE received.")
            onImeHide?()
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
    
    // Приложения-браузеры, для которых используется непрерывное удержание стрелки (имитация пульта)
    let browserPackages: Set<String> = [
        "com.tcl.browser",        // BrowseHere
        "com.opera.browser",
        "com.phlox.tvwebbrowser", // TV Bro
    ]
    var isBrowserActive: Bool {
        return browserPackages.contains(currentAppPackage)
    }
    var scrollThreshold = 30.0
    var swipeThreshold = 50.0
    
    // Отслеживание тапа 3 пальцами (Home)
    var maxSimultaneousTouches = 0
    var threeFingerTouchStartTime: Date?
    
    // Непрерывное удержание стрелки (имитация зажатой кнопки физического пульта)
    var currentHoldDirection: String? = nil  // Текущая зажатая клавиша (nil = ничего не зажато)
    var holdIdleTimer: Timer? = nil          // Таймер отпускания при остановке пальца
    
    // Количество пальцев на трекпаде (для определения жеста: 1=навигация, 2=скролл, 3=Home)
    var currentTouchCount = 0
    var accumulatedScrollDeltaY = 0.0        // Накопление дельты для 2-пальцевого скролла в браузере
    let browserScrollThreshold = 15.0       // Порог срабатывания скролла в браузере
    
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
        
        // === Режим скроллинга: 2 пальца на трекпаде + браузер ===
        if currentTouchCount >= 2 && isBrowserActive {
            // При 2 пальцах в браузере вертикальная дельта используется для скролла страницы
            accumulatedScrollDeltaY += Double(event.deltaY)
            accumulatedX = 0.0
            accumulatedY = 0.0
            
            // Отпускаем зажатую стрелку навигации, если она была
            releaseHold()
            
            if abs(accumulatedScrollDeltaY) >= browserScrollThreshold {
                let now = Date()
                if now.timeIntervalSince(lastScrollKeyTime) >= 0.08 {
                    if accumulatedScrollDeltaY > 0 {
                        sendKey("KEYCODE_PAGE_DOWN")
                    } else {
                        sendKey("KEYCODE_PAGE_UP")
                    }
                    accumulatedScrollDeltaY = 0.0
                    lastScrollKeyTime = now
                    print("[KVM] Browser 2-finger scroll: \(accumulatedScrollDeltaY > 0 ? "PAGE_DOWN" : "PAGE_UP")")
                }
            }
            
            // Пропускаем обработку навигации и exit-порога ниже
            let scrollCenter: CGPoint
            switch activeEdge {
            case .right:
                scrollCenter = CGPoint(x: macWidth - (INITIAL_ZONE_WIDTH / 2.0), y: macHeight / 2.0)
            case .left:
                scrollCenter = CGPoint(x: INITIAL_ZONE_WIDTH / 2.0, y: macHeight / 2.0)
            case .top:
                scrollCenter = CGPoint(x: macWidth / 2.0, y: INITIAL_ZONE_WIDTH / 2.0)
            }
            CGWarpMouseCursorPosition(scrollCenter)
            return
        }
        
        // Сброс скролл-дельты при переходе к 1-пальцевой навигации
        accumulatedScrollDeltaY = 0.0
        
        // 1. Сначала обрабатываем горизонтальный свайп
        if abs(accumulatedX) >= swipeThreshold {
            let key = accumulatedX > 0 ? "KEYCODE_DPAD_RIGHT" : "KEYCODE_DPAD_LEFT"
            if isBrowserActive {
                holdNavKey(key)   // Браузер: непрерывное удержание как на пульте
            } else {
                sendNavKey(key)   // Лаунчер/YouTube: дискретные шаги
            }
            accumulatedX = 0.0
            accumulatedY = 0.0
        }
        
        // 2. Обрабатываем вертикальный свайп
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
        
        // 3. Динамический порог выхода из KVM обратно на Mac (всегда больше порога свайпа для исключения ложных выходов)
        let exitThreshold = max(120.0, swipeThreshold + 40.0)
        
        // Условия возврата на Mac на основе активной стороны KVM
        switch activeEdge {
        case .right:
            if accumulatedX <= -exitThreshold { // Движение влево для выхода
                exitTVMode()
                return
            }
        case .left:
            if accumulatedX >= exitThreshold { // Движение вправо для выхода
                exitTVMode()
                return
            }
        case .top:
            if accumulatedY >= exitThreshold { // Движение вниз для выхода (deltaY > 0)
                exitTVMode()
                return
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
        
        accumulatedScrollY += Double(event.deltaY)
        
        // В браузере порог скроллинга ниже, т.к. deltaY маленькие (1-4 за событие)
        let effectiveScrollThreshold = isBrowserActive ? 5.0 : scrollThreshold
        let maxAccumulated = effectiveScrollThreshold * 3.0
        if accumulatedScrollY > maxAccumulated {
            accumulatedScrollY = maxAccumulated
        } else if accumulatedScrollY < -maxAccumulated {
            accumulatedScrollY = -maxAccumulated
        }
        
        if abs(accumulatedScrollY) >= effectiveScrollThreshold {
            // Мягкий кулдаун отправки команд прокрутки списков на ТВ (80 мс)
            if now.timeIntervalSince(lastScrollKeyTime) >= 0.08 {
                if isBrowserActive {
                    // Браузер: PAGE_UP/PAGE_DOWN скроллит страницу (а не перемещает фокус)
                    if accumulatedScrollY > 0 {
                        sendKey("KEYCODE_PAGE_UP")
                        accumulatedScrollY -= effectiveScrollThreshold
                    } else {
                        sendKey("KEYCODE_PAGE_DOWN")
                        accumulatedScrollY += effectiveScrollThreshold
                    }
                } else {
                    // Лаунчер/YouTube: DPAD_UP/DOWN перемещает фокус по списку
                    if accumulatedScrollY > 0 {
                        sendKey("KEYCODE_DPAD_UP")
                        accumulatedScrollY -= scrollThreshold
                    } else {
                        sendKey("KEYCODE_DPAD_DOWN")
                        accumulatedScrollY += scrollThreshold
                    }
                }
                lastScrollKeyTime = now
            }
        }
    }
    
    // === Мультитач-жесты трекпада ===
    
    override func touchesBegan(with event: NSEvent) {
        guard isActive else { return }
        let touches = event.touches(matching: .touching, in: self)
        let count = touches.count
        currentTouchCount = count
        maxSimultaneousTouches = max(maxSimultaneousTouches, count)
        if count >= 3 && threeFingerTouchStartTime == nil {
            threeFingerTouchStartTime = Date()
        }
    }
    
    override func touchesEnded(with event: NSEvent) {
        guard isActive else {
            maxSimultaneousTouches = 0
            threeFingerTouchStartTime = nil
            return
        }
        let remaining = event.touches(matching: .touching, in: self)
        currentTouchCount = remaining.count
        if remaining.count == 0 {
            // Все пальцы подняты
            if maxSimultaneousTouches == 3, let start = threeFingerTouchStartTime {
                let duration = Date().timeIntervalSince(start)
                if duration < 0.4 { // Менее 400 мс — это тап, а не свайп
                    print("[KVM] Тап 3 пальцами: Home (KEYCODE_HOME)")
                    sendKey("KEYCODE_HOME")
                }
            }
            maxSimultaneousTouches = 0
            threeFingerTouchStartTime = nil
        }
    }
    
    override func touchesCancelled(with event: NSEvent) {
        maxSimultaneousTouches = 0
        threeFingerTouchStartTime = nil
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
    
    var nodeProcess: Process?
    
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
        return "192.168.31.67"
    }
    
    func startNodeBridge() {
        let bundlePath = Bundle.main.bundlePath
        let parentDir = (bundlePath as NSString).deletingLastPathComponent
        let bridgeScript = "\(parentDir)/tv_remote_bridge.js"
        let tvIP = getTVIP()
        
        print("[Swift] Starting background Node.js bridge for IP: \(tvIP)...")
        
        let process = Process()
        let nodePaths = ["/usr/local/bin/node", "/opt/homebrew/bin/node", "/usr/bin/node"]
        var chosenPath = "/usr/bin/env"
        var args = ["node", bridgeScript, tvIP]
        
        for path in nodePaths {
            if FileManager.default.fileExists(atPath: path) {
                chosenPath = path
                args = [bridgeScript, tvIP]
                break
            }
        }
        
        process.executableURL = URL(fileURLWithPath: chosenPath)
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: parentDir)
        
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        
        do {
            try process.run()
            self.nodeProcess = process
            print("[Swift] Successfully launched Node.js bridge subprocess (PID: \(process.processIdentifier))")
        } catch {
            print("[Swift Error] Failed to launch Node.js bridge: \(error)")
        }
    }
    
    func stopNodeBridge() {
        if let process = nodeProcess, process.isRunning {
            process.terminate()
            print("[Swift] Terminated background Node.js bridge.")
        }
    }
    
    // HUD-справка по жестам
    var helpOverlayWindow: NSWindow?
    var helpDismissTimer: Timer?
    
    func showHelpOverlay() {
        // Закрываем старый если есть
        hideHelpOverlay()
        
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let windowWidth: CGFloat = 340.0
        let windowHeight: CGFloat = 290.0
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
            ("🤟  Тап 3 пальцами", "Home"),
            ("⬅️  Свайп влево / Esc", "Выход на Mac"),
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
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[Swift] applicationDidFinishLaunching started. Initializing window...")
        
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
            kvmView.scrollThreshold = 30.0
        }
        
        // Загружаем сохраненный порог свайпов из UserDefaults
        if let savedSwipe = UserDefaults.standard.object(forKey: "KVM_SwipeThreshold") as? Double {
            kvmView.swipeThreshold = savedSwipe
        } else {
            kvmView.swipeThreshold = 50.0
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
        
        socketClient.onImeUpdate = { [weak self] text in
            DispatchQueue.main.async {
                // Обновляем текст в уже открытом HUD без повторного показа
                if let textField = self?.inputTextField, self?.inputWindow != nil {
                    textField.stringValue = text
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
        alert.messageText = Localization.get("unpair_title")
        alert.informativeText = Localization.get("unpair_text")
        alert.addButton(withTitle: Localization.get("forget_tv_btn"))
        alert.addButton(withTitle: Localization.get("cancel"))
        
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
        stopNodeBridge()
        NSApp.terminate(nil)
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        stopNodeBridge()
    }
    
    func updateStatusMenu(_ status: String) {
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
            
            // Проверяем наличие ранее сохраненного TLS-сертификата сопряжения
            let currentDir = FileManager.default.currentDirectoryPath
            let certPath = "\(currentDir)/.credentials/cert.json"
            let hasCert = FileManager.default.fileExists(atPath: certPath)
            
            if let button = self.statusItem.button {
                switch status {
                case "READY":
                    button.title = Localization.get("kvm_connected")
                    
                    // - Меню при активном подключении
                    menu.addItem(NSMenuItem(title: Localization.get("disconnect_tv"), action: #selector(self.disconnectKVM), keyEquivalent: "d"))
                    menu.addItem(NSMenuItem(title: Localization.get("type_text_tv"), action: #selector(self.manuallyTriggerTextInput), keyEquivalent: "t"))
                    menu.addItem(NSMenuItem(title: Localization.get("forget_tv"), action: #selector(self.unpairKVM), keyEquivalent: "u"))
                    
                case "NEED_PIN":
                    button.title = Localization.get("kvm_enter_pin")
                    
                    // - Меню при вводе PIN
                    menu.addItem(NSMenuItem(title: Localization.get("cancel_pairing"), action: #selector(self.disconnectKVM), keyEquivalent: "c"))
                    
                    self.promptForPIN { [weak self] pin in
                        self?.socketClient.send(cmd: "PIN \(pin)")
                    }
                    
                case "CONNECTING":
                    button.title = Localization.get("kvm_connecting")
                    
                    // - Меню при подключении
                    menu.addItem(NSMenuItem(title: Localization.get("cancel_connection"), action: #selector(self.disconnectKVM), keyEquivalent: "c"))
                    
                default: // - DISCONNECTED
                    button.title = Localization.get("kvm_disconnected")
                    
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
            let threshold = self.kvmView?.scrollThreshold ?? 30.0
            
            let scrollVeryFast = NSMenuItem(title: Localization.get("sens_very_fast"), action: #selector(self.setScrollVeryFast), keyEquivalent: "")
            scrollVeryFast.state = (threshold == 15.0) ? .on : .off
            scrollMenu.addItem(scrollVeryFast)
            
            let scrollFast = NSMenuItem(title: Localization.get("sens_fast"), action: #selector(self.setScrollFast), keyEquivalent: "")
            scrollFast.state = (threshold == 22.0) ? .on : .off
            scrollMenu.addItem(scrollFast)
            
            let scrollNormal = NSMenuItem(title: Localization.get("sens_medium"), action: #selector(self.setScrollNormal), keyEquivalent: "")
            scrollNormal.state = (threshold == 30.0) ? .on : .off
            scrollMenu.addItem(scrollNormal)
            
            let scrollSlow = NSMenuItem(title: Localization.get("sens_slow"), action: #selector(self.setScrollSlow), keyEquivalent: "")
            scrollSlow.state = (threshold == 45.0) ? .on : .off
            scrollMenu.addItem(scrollSlow)
            
            let scrollVerySlow = NSMenuItem(title: Localization.get("sens_very_slow"), action: #selector(self.setScrollVerySlow), keyEquivalent: "")
            scrollVerySlow.state = (threshold == 60.0) ? .on : .off
            scrollMenu.addItem(scrollVerySlow)
            
            let scrollMenuItem = NSMenuItem(title: Localization.get("scroll_sensitivity"), action: nil, keyEquivalent: "")
            scrollMenuItem.submenu = scrollMenu
            menu.addItem(scrollMenuItem)
            
            // - Настройка подменю с выбором плавности/чувствительности свайпов
            let swipeMenu = NSMenu()
            let swipeThreshold = self.kvmView?.swipeThreshold ?? 80.0
            
            let swipeVeryFast = NSMenuItem(title: Localization.get("sens_very_fast"), action: #selector(self.setSwipeVeryFast), keyEquivalent: "")
            swipeVeryFast.state = (swipeThreshold == 40.0) ? .on : .off
            swipeMenu.addItem(swipeVeryFast)
            
            let swipeFast = NSMenuItem(title: Localization.get("sens_fast"), action: #selector(self.setSwipeFast), keyEquivalent: "")
            swipeFast.state = (swipeThreshold == 60.0) ? .on : .off
            swipeMenu.addItem(swipeFast)
            
            let swipeNormal = NSMenuItem(title: Localization.get("sens_medium"), action: #selector(self.setSwipeNormal), keyEquivalent: "")
            swipeNormal.state = (swipeThreshold == 80.0) ? .on : .off
            swipeMenu.addItem(swipeNormal)
            
            let swipeSlow = NSMenuItem(title: Localization.get("sens_slow"), action: #selector(self.setSwipeSlow), keyEquivalent: "")
            swipeSlow.state = (swipeThreshold == 110.0) ? .on : .off
            swipeMenu.addItem(swipeSlow)
            
            let swipeVerySlow = NSMenuItem(title: Localization.get("sens_very_slow"), action: #selector(self.setSwipeVerySlow), keyEquivalent: "")
            swipeVerySlow.state = (swipeThreshold == 140.0) ? .on : .off
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
            
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: Localization.get("exit_kvm"), action: #selector(self.terminate), keyEquivalent: "q"))
            
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
        
        let titleLabel = NSTextField(labelWithString: Localization.get("hud_title"))
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
        textField.placeholderString = Localization.get("hud_placeholder")
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
        
        let helpLabel = NSTextField(labelWithString: Localization.get("hud_help"))
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

setbuf(stdout, nil)
setbuf(stderr, nil)

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
