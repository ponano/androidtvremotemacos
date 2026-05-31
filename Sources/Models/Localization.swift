import Cocoa
import Foundation
import AppKit
import Network
import ServiceManagement
import Speech
import AVFoundation
import Darwin

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
        "invalid_ip_title": [
            "ru": "Неверный формат IP",
            "en": "Invalid IP Format",
            "fr": "Format IP invalide",
            "it": "Formato IP non valido",
            "de": "Ungültiges IP-Format",
            "es": "Formato de IP no válido",
            "zh": "IP 格式无效"
        ],
        "invalid_ip_message": [
            "ru": "Введенный текст не является корректным IPv4-адресом.\n\nПожалуйста, введите адрес в формате: 192.168.1.50\n\nСпециальные символы и инъекции кода запрещены из соображений безопасности.",
            "en": "The entered text is not a valid IPv4 address.\n\nPlease enter the address in the format: 192.168.1.50\n\nSpecial characters and code injections are forbidden for security reasons.",
            "fr": "Le texte saisi n'est pas une adresse IPv4 valide.\n\nVeuillez saisir l'adresse au format: 192.168.1.50\n\nLes caractères spéciaux et les injections de code sont interdits pour des raisons de sécurité.",
            "it": "Il testo inserito non è un indirizzo IPv4 valido.\n\nInserisci l'indirizzo nel formato: 192.168.1.50\n\nI caratteri speciali e le iniezioni di codice sono vietati per motivi di sicurezza.",
            "de": "Der eingegebene Text ist keine gültige IPv4-Adresse.\n\nBitte geben Sie die Adresse im Format ein: 192.168.1.50\n\nSonderzeichen und Code-Injections sind aus Sicherheitsgründen verboten.",
            "es": "El texto introducido no es una dirección IPv4 válida.\n\nPor favor, introduzca la dirección en el formato: 192.168.1.50\n\nLos caracteres especiales y las inyecciones de código están prohibidos por razones de seguridad.",
            "zh": "输入的文本不是有效的 IPv4 地址。\n\n请按以下格式输入地址：192.168.1.50\n\n出于安全原因，禁止输入特殊字符和代码注入。"
        ],
        "manual_ip_title": [
            "ru": "Телевизор не найден",
            "en": "TV Not Found",
            "fr": "TV non trouvée",
            "it": "TV non trovata",
            "de": "TV nicht gefunden",
            "es": "TV no encontrada",
            "zh": "未找到电视"
        ],
        "manual_ip_message": [
            "ru": "Не удалось автоматически обнаружить телевизор в вашей Wi-Fi сети.\n\nПожалуйста, введите IP-адрес телевизора вручную:\n\n(Посмотреть адрес можно в меню телевизора: Настройки ➔ Сеть и Интернет ➔ имя вашего подключения)",
            "en": "Could not automatically discover the TV in your Wi-Fi network.\n\nPlease enter the TV IP address manually:\n\n(You can find the address in the TV menu: Settings ➔ Network & Internet ➔ name of your connection)",
            "fr": "Impossible de découvrir automatiquement la TV sur votre réseau Wi-Fi.\n\nVeuillez saisir l'adresse IP de la TV manuellement:\n\n(Vous pouvez trouver l'adresse dans le menu de la TV: Paramètres ➔ Réseau et Internet ➔ nom de votre connexion)",
            "it": "Impossibile rilevare automaticamente la TV nella rete Wi-Fi.\n\nInserisci l'indirizzo IP della TV manualmente:\n\n(Puoi trovare l'indirizzo nel menu della TV: Impostazioni ➔ Rete e Internet ➔ nome della tua connessione)",
            "de": "Der Fernseher konnte in Ihrem Wi-Fi-Netzwerk nicht automatisch gefunden werden.\n\nBitte geben Sie die IP-Adresse des Fernsehers manuell ein:\n\n(Sie finden die Adresse im TV-Menü: Einstellungen ➔ Netzwerk & Internet ➔ Name Ihrer Verbindung)",
            "es": "No se pudo descubrir automáticamente la TV en su red Wi-Fi.\n\nPor favor, introduzca la dirección IP de la TV manualmente:\n\n(Puede encontrar la dirección en el menú de la TV: Ajustes ➔ Red e Internet ➔ nombre de su conexión)",
            "zh": "无法在您的 Wi-Fi 网络中自动发现电视。\n\n请手动输入电视的 IP 地址：\n\n（您可以在电视菜单中找到该地址：设置 ➔ 网络 and 互联网 ➔ 您的连接名称）"
        ],
        "connect": [
            "ru": "Подключиться",
            "en": "Connect",
            "fr": "Connecter",
            "it": "Connetti",
            "de": "Verbinden",
            "es": "Conectar",
            "zh": "连接"
        ],
        "searching_tv": [
            "ru": "🔍 Поиск телевизора в сети...",
            "en": "🔍 Searching for TV on network...",
            "fr": "🔍 Recherche de la TV sur le réseau...",
            "it": "🔍 Ricerca della TV nella rete...",
            "de": "🔍 Suche nach TV im Netzwerk...",
            "es": "🔍 Buscando TV en la red...",
            "zh": "🔍 正在局域网中搜索电视..."
        ],
        "language": [
            "ru": "Язык интерфейса",
            "en": "Interface Language",
            "fr": "Langue de l'interface",
            "it": "Lingua dell'interfaccia",
            "de": "Oberflächensprache",
            "es": "Idioma de la interfaz",
            "zh": "界面语言"
        ],
        "cert_rejected_title": [
            "ru": "Ошибка безопасности",
            "en": "Security Certificate Error",
            "fr": "Erreur de certificat de sécurité",
            "it": "Errore del certificato di sicurezza",
            "de": "Sicherheitszertifikat-Fehler",
            "es": "Error de certificado de seguridad",
            "zh": "安全证书错误"
        ],
        "cert_rejected_text": [
            "ru": "Телевизор отклонил сертификат подключения. Возможно, сопряжение было разорвано на ТВ, или срок его действия истек.\n\nХотите запустить процесс сопряжения заново?",
            "en": "The TV rejected the connection certificate. The pairing may have been removed on the TV, or the certificate has expired.\n\nWould you like to start the pairing process again?",
            "fr": "La TV a rejeté le certificat de connexion. L'association a peut-être été supprimée sur la TV, ou le certificat a expiré.\n\nSouhaitez-vous relancer le processus d'association ?",
            "it": "La TV ha rifiutato il certificato di connessione. L'associazione potrebbe essere stata rimossa sulla TV o il certificato è scaduto.\n\nVuoi avviare nuovamente il processo di associazione?",
            "de": "Der TV hat das Verbindungszertifikat abgelehnt. Möglicherweise wurde die Kopplung auf dem TV aufgehoben, oder das Zertifikat ist abgelaufen.\n\nMöchten Sie den Kopplungsprozess erneut starten?",
            "es": "La TV rechazó el certificado de conexión. Es posible que se haya eliminado la vinculación en la TV o que el certificado haya expirado.\n\n¿Le gustaría iniciar el proceso de vinculación de nuevo?",
            "zh": "电视拒绝了连接证书。可能是电视上的配对已被删除，或者证书已过期。\n\n您想重新启动配对过程吗？"
        ],
        "cert_rejected_repair": [
            "ru": "Сопрячь заново",
            "en": "Re-pair TV",
            "fr": "Associer à nouveau",
            "it": "Associa di nuovo",
            "de": "Erneut koppeln",
            "es": "Vincular de nuevo",
            "zh": "重新配对"
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
        ],
        "guide_title": [
            "ru": "Добро пожаловать в Pano!",
            "en": "Welcome to Pano!",
            "fr": "Bienvenue dans Pano !",
            "it": "Benvenuto in Pano!",
            "de": "Willkommen bei Pano!",
            "es": "¡Bienvenido a Pano!",
            "zh": "欢迎使用 Pano！"
        ],
        "guide_subtitle": [
            "ru": "Управляйте Android TV прямо с трекпада Mac",
            "en": "Control your Android TV directly from your Mac trackpad",
            "fr": "Contrôlez votre Android TV directement depuis le trackpad de votre Mac",
            "it": "Controlla la tua Android TV direttamente dal trackpad del Mac",
            "de": "Steuern Sie Ihren Android TV direkt über das Mac-Trackpad",
            "es": "Controla tu Android TV directamente desde el trackpad de tu Mac",
            "zh": "直接通过 Mac 触控板控制你的 Android TV"
        ],
        "guide_how_title": [
            "ru": "Как это работает",
            "en": "How It Works",
            "fr": "Comment ça marche",
            "it": "Come funziona",
            "de": "So funktioniert es",
            "es": "Cómo funciona",
            "zh": "工作原理"
        ],
        "guide_how_text": [
            "ru": "Переместите курсор к краю экрана (по умолчанию — правый) для перехода в режим TV. Управляйте телевизором жестами трекпада, как пультом.",
            "en": "Move your cursor to the screen edge (default: right) to enter TV mode. Control the TV with trackpad gestures, like a remote.",
            "fr": "Déplacez le curseur vers le bord de l'écran (par défaut : droite) pour passer en mode TV. Contrôlez la TV avec les gestes du trackpad.",
            "it": "Sposta il cursore verso il bordo dello schermo (predefinito: destro) per entrare in modalità TV. Controlla la TV con i gesti del trackpad.",
            "de": "Bewegen Sie den Cursor zum Bildschirmrand (Standard: rechts), um den TV-Modus zu aktivieren. Steuern Sie den TV mit Trackpad-Gesten.",
            "es": "Mueve el cursor al borde de la pantalla (por defecto: derecho) para entrar en el modo TV. Controla la TV con gestos del trackpad.",
            "zh": "将光标移动到屏幕边缘（默认：右侧）进入电视模式。使用触控板手势控制电视，如同遥控器。"
        ],
        "guide_gestures_title": [
            "ru": "Жесты управления",
            "en": "Control Gestures",
            "fr": "Gestes de contrôle",
            "it": "Gesti di controllo",
            "de": "Steuergesten",
            "es": "Gestos de control",
            "zh": "控制手势"
        ],
        "guide_g1_action": [
            "ru": "Свайп 1 пальцем",
            "en": "1-finger swipe",
            "fr": "Glisser à 1 doigt",
            "it": "Scorrimento a 1 dito",
            "de": "1-Finger-Wischen",
            "es": "Deslizar con 1 dedo",
            "zh": "单指轻扫"
        ],
        "guide_g1_desc": [
            "ru": "Навигация (стрелки)",
            "en": "Navigation (arrows)",
            "fr": "Navigation (flèches)",
            "it": "Navigazione (frecce)",
            "de": "Navigation (Pfeile)",
            "es": "Navegación (flechas)",
            "zh": "导航（方向键）"
        ],
        "guide_g2_action": [
            "ru": "Клик (короткий)",
            "en": "Click (short)",
            "fr": "Clic (court)",
            "it": "Clic (breve)",
            "de": "Klick (kurz)",
            "es": "Clic (corto)",
            "zh": "单击（短按）"
        ],
        "guide_g2_desc": [
            "ru": "Выбор / OK",
            "en": "Select / OK",
            "fr": "Sélectionner / OK",
            "it": "Seleziona / OK",
            "de": "Auswählen / OK",
            "es": "Seleccionar / OK",
            "zh": "选择 / 确认"
        ],
        "guide_g3_action": [
            "ru": "Клик (зажать ≥1с)",
            "en": "Click (hold ≥1s)",
            "fr": "Clic (maintenir ≥1s)",
            "it": "Clic (tenere ≥1s)",
            "de": "Klick (halten ≥1s)",
            "es": "Clic (mantener ≥1s)",
            "zh": "长按（≥1秒）"
        ],
        "guide_g3_desc": [
            "ru": "Режим скроллинга",
            "en": "Scrolling mode",
            "fr": "Mode défilement",
            "it": "Modalità scorrimento",
            "de": "Scroll-Modus",
            "es": "Modo desplazamiento",
            "zh": "滚动模式"
        ],
        "guide_g4_action": [
            "ru": "Клик 2 пальцами",
            "en": "2-finger click",
            "fr": "Clic à 2 doigts",
            "it": "Clic a 2 dita",
            "de": "2-Finger-Klick",
            "es": "Clic con 2 dedos",
            "zh": "双指点按"
        ],
        "guide_g4_desc": [
            "ru": "Назад",
            "en": "Back",
            "fr": "Retour",
            "it": "Indietro",
            "de": "Zurück",
            "es": "Atrás",
            "zh": "返回"
        ],
        "guide_g5_action": [
            "ru": "Тап 3 пальцами",
            "en": "3-finger tap",
            "fr": "Tap à 3 doigts",
            "it": "Tap a 3 dita",
            "de": "3-Finger-Tap",
            "es": "Tocar con 3 dedos",
            "zh": "三指轻触"
        ],
        "guide_g5_desc": [
            "ru": "Home",
            "en": "Home",
            "fr": "Accueil",
            "it": "Home",
            "de": "Home",
            "es": "Inicio",
            "zh": "主屏幕"
        ],
        "guide_g6_action": [
            "ru": "Свайп 3 пальцами влево / Esc",
            "en": "3-finger swipe left / Esc",
            "fr": "Balayage à 3 doigts vers la gauche / Échap",
            "it": "Scorrere con 3 dita a sinistra / Esc",
            "de": "3-Finger-Swipe nach links / Esc",
            "es": "Deslizar con 3 dedos a la izquierda / Esc",
            "zh": "三指左轻扫 / Esc"
        ],
        "guide_g6_desc": [
            "ru": "Выход на Mac",
            "en": "Return to Mac",
            "fr": "Retour au Mac",
            "it": "Torna al Mac",
            "de": "Zurück zum Mac",
            "es": "Volver al Mac",
            "zh": "返回 Mac"
        ],
        "guide_g7_action": [
            "ru": "Скролл 2 пальцами",
            "en": "2-finger scroll",
            "fr": "Défilement à 2 doigts",
            "it": "Scorrimento a 2 dita",
            "de": "2-Finger-Scroll",
            "es": "Desplazar con 2 dedos",
            "zh": "双指滚动"
        ],
        "guide_g7_desc": [
            "ru": "Громкость ТВ",
            "en": "TV Volume",
            "fr": "Volume de la TV",
            "it": "Volume della TV",
            "de": "TV-Lautstärke",
            "es": "Volumen de la TV",
            "zh": "电视音量"
        ],
        "guide_tip": [
            "ru": "💡 Используйте Ctrl+Shift+T для ввода текста на ТВ",
            "en": "💡 Use Ctrl+Shift+T to type text on the TV",
            "fr": "💡 Utilisez Ctrl+Shift+T pour saisir du texte sur la TV",
            "it": "💡 Usa Ctrl+Shift+T per digitare testo sulla TV",
            "de": "💡 Drücken Sie Strg+Umschalt+T, um Text auf dem TV einzugeben",
            "es": "💡 Usa Ctrl+Shift+T para escribir texto en la TV",
            "zh": "💡 使用 Ctrl+Shift+T 在电视上输入文字"
        ],
        "guide_dont_show": [
            "ru": "Не показывать при запуске",
            "en": "Don't show on startup",
            "fr": "Ne plus afficher au démarrage",
            "it": "Non mostrare all'avvio",
            "de": "Beim Start nicht anzeigen",
            "es": "No mostrar al iniciar",
            "zh": "启动时不再显示"
        ],
        "guide_start_btn": [
            "ru": "Начать",
            "en": "Get Started",
            "fr": "Commencer",
            "it": "Inizia",
            "de": "Los geht's",
            "es": "Empezar",
            "zh": "开始使用"
        ],
        "guide_menu_item": [
            "ru": "📖 Инструкция",
            "en": "📖 User Guide",
            "fr": "📖 Guide d'utilisation",
            "it": "📖 Guida utente",
            "de": "📖 Benutzerhandbuch",
            "es": "📖 Guía de usuario",
            "zh": "📖 使用指南"
        ],
        "launch_at_login": [
            "ru": "Запускать при входе в систему",
            "en": "Launch at Login",
            "fr": "Lancer au démarrage",
            "it": "Avvia al login",
            "de": "Beim Login starten",
            "es": "Iniciar al iniciar sesión",
            "zh": "登录时启动"
        ],
        "show_logs": [
            "ru": "📂 Открыть папку логов",
            "en": "📂 Open Logs Folder",
            "fr": "📂 Ouvrir le dossier des journaux",
            "it": "📂 Apri la cartella dei log",
            "de": "📂 Protokollordner öffnen",
            "es": "📂 Abrir carpeta de registros",
            "zh": "📂 打开日志文件夹"
        ],
        // === Устойчивое поведение ===
        "tv_not_found": [
            "ru": "📵 ТВ не найден",
            "en": "📵 TV not found",
            "fr": "📵 TV introuvable",
            "it": "📵 TV non trovato",
            "de": "📵 TV nicht gefunden",
            "es": "📵 TV no encontrado",
            "zh": "📵 未找到电视"
        ],
        "tv_waiting": [
            "ru": "Ожидание ТВ...",
            "en": "Waiting for TV...",
            "fr": "En attente du TV...",
            "it": "In attesa del TV...",
            "de": "Warte auf TV...",
            "es": "Esperando TV...",
            "zh": "等待电视..."
        ],
        "bridge_stopped": [
            "ru": "⚠️ Мост остановлен",
            "en": "⚠️ Bridge stopped",
            "fr": "⚠️ Pont arrêté",
            "it": "⚠️ Ponte arrestato",
            "de": "⚠️ Bridge gestoppt",
            "es": "⚠️ Puente detenido",
            "zh": "⚠️ 桥接已停止"
        ],
        "bridge_restart_failed": [
            "ru": "Не удалось перезапустить мост. Перезапустите приложение.",
            "en": "Failed to restart bridge. Please restart the app.",
            "fr": "Échec du redémarrage du pont. Veuillez relancer l'app.",
            "it": "Impossibile riavviare il ponte. Riavvia l'app.",
            "de": "Bridge-Neustart fehlgeschlagen. Bitte App neu starten.",
            "es": "No se pudo reiniciar el puente. Reinicie la app.",
            "zh": "桥接重启失败，请重新启动应用。"
        ],
        "reconnect_now": [
            "ru": "🔄 Переподключить сейчас",
            "en": "🔄 Reconnect now",
            "fr": "🔄 Reconnecter maintenant",
            "it": "🔄 Riconnetti ora",
            "de": "🔄 Jetzt neu verbinden",
            "es": "🔄 Reconectar ahora",
            "zh": "🔄 立即重新连接"
        ],
        "tv_unreachable_hint": [
            "ru": "Убедитесь, что ТВ включен и в одной Wi-Fi сети",
            "en": "Make sure the TV is on and on the same Wi-Fi network",
            "fr": "Vérifiez que le TV est allumé et sur le même réseau Wi-Fi",
            "it": "Assicurati che il TV sia acceso e sulla stessa rete Wi-Fi",
            "de": "Stellen Sie sicher, dass der TV eingeschaltet und im selben WLAN ist",
            "es": "Asegúrese de que el TV esté encendido y en la misma red Wi-Fi",
            "zh": "请确保电视已开启并连接到同一Wi-Fi网络"
        ]
    ]
}

// Класс для живого распознавания речи с микрофона Mac на системной локали (автовыбор RU / EN / FR / IT / DE / ES)
