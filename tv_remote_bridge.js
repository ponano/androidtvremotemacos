const fs = require('fs');
const path = require('path');
const os = require('os');
const net = require('net');
const { AndroidRemote, RemoteKeyCode, RemoteDirection } = require('androidtv-remote');
const { remoteMessageManager } = require('androidtv-remote/dist/remote/RemoteMessageManager');

// Глобальный перехватчик ошибок консоли для самодиагностики SSL/TLS сертификатов
const originalConsoleError = console.error;
console.error = function(...args) {
    originalConsoleError.apply(console, args);
    const msg = args.map(a => String(a || "")).join(" ");
    if (msg.toLowerCase().includes("certificate unknown") || msg.toLowerCase().includes("alert number 46")) {
        originalConsoleError("[Bridge] Self-Diagnostics (Console Intercept): TV explicitly rejected secure certificate (SSL Alert 46). Sending CERT_REJECTED status.");
        if (typeof sendStatus === "function") {
            sendStatus("CERT_REJECTED");
        }
    }
};

// Рантайм-перехватчик входящих Protobuf сообщений для синхронизации текстового ввода
let latestAppInfo = null;
let latestTextFieldStatus = null;

const originalParse = remoteMessageManager.parse;
remoteMessageManager.parse = function(buffer) {
    const message = originalParse.call(this, buffer);
    try {
        handleIncomingImeMessage(message);
    } catch (e) {
        console.error("[Bridge] Error in IME sync handler:", e.message);
    }
    return message;
};

function handleIncomingImeMessage(message) {
    if (!message) return;

    if (message.remoteImeKeyInject) {
        const ime = message.remoteImeKeyInject;
        
        if (ime.appInfo) {
            latestAppInfo = ime.appInfo;
            if (ime.appInfo.counter !== undefined && ime.appInfo.counter !== null) {
                if (ime.appInfo.counter !== imeSessionCounter) {
                    console.log(`[Bridge] New IME session started: ${ime.appInfo.counter} (previous: ${imeSessionCounter})`);
                    imeSessionCounter = ime.appInfo.counter;
                    latestSentFieldCounter = 0; // Reset stale transaction filter for new session
                }
            }
            if (ime.appInfo.appPackage) {
                console.log(`[Bridge] Active app package: ${ime.appInfo.appPackage}`);
                currentActiveApp = ime.appInfo.appPackage;
                if (activeSocket) {
                    activeSocket.write(`APP ${ime.appInfo.appPackage}\n`);
                }
            }
        }
        
        if (ime.textFieldStatus) {
            latestTextFieldStatus = ime.textFieldStatus;
            
            const tvFieldCounter = ime.textFieldStatus.counterField;
            if (tvFieldCounter !== undefined && tvFieldCounter !== null) {
                if (tvFieldCounter < latestSentFieldCounter) {
                    console.log(`[Bridge] TV counter decreased in KeyInject (${tvFieldCounter} < ${latestSentFieldCounter}). Resetting stale transaction filter.`);
                    latestSentFieldCounter = 0;
                }
                const isEcho = (tvFieldCounter === latestSentFieldCounter && latestSentFieldCounter > 0);
                localFieldCounter = tvFieldCounter;
                if (ime.textFieldStatus.value !== undefined && ime.textFieldStatus.value !== null) {
                    currentText = ime.textFieldStatus.value;
                    cursorPosition = ime.textFieldStatus.start !== undefined ? ime.textFieldStatus.start : currentText.length;
                }
                console.log(`[Bridge] Sync from TV (KeyInject): "${currentText}", cursorPosition: ${cursorPosition}, counterField: ${localFieldCounter}, sessionCounter: ${imeSessionCounter}`);
                
                // KeyInject — фоновая синхронизация буфера. НЕ вызываем HUD автоматически.
                // Браузеры (BrowseHere, etc.) спамят KeyInject при открытии, что ложно
                // активировало HUD и выбивало KVM из режима управления тачпадом.
                // HUD вызывается ТОЛЬКО из remoteImeShowRequest (явный запрос от пользователя).
                if (isHudActive && !isEcho && activeSocket) {
                    // Если HUD уже открыт, обновляем текст в реальном времени
                    const base64Val = Buffer.from(currentText || "").toString('base64');
                    activeSocket.write(`IME_UPDATE ${base64Val}\n`);
                }
            }
        }
    }

    if (message.remoteImeShowRequest) {
        console.log(`[Bridge] TV explicitly requested IME show (remoteImeShowRequest received).`);
        const status = message.remoteImeShowRequest.remoteTextFieldStatus;
        if (status) {
            latestTextFieldStatus = status;
            
            const tvFieldCounter = status.counterField;
            if (tvFieldCounter !== undefined && tvFieldCounter !== null) {
                if (tvFieldCounter < latestSentFieldCounter) {
                    console.log(`[Bridge] TV counter decreased in ShowRequest (${tvFieldCounter} < ${latestSentFieldCounter}). Resetting stale transaction filter.`);
                    latestSentFieldCounter = 0;
                }
                localFieldCounter = tvFieldCounter;
                if (status.value !== undefined && status.value !== null) {
                    currentText = status.value;
                    cursorPosition = status.start !== undefined ? status.start : currentText.length;
                }
                console.log(`[Bridge] Sync from TV (ShowRequest): "${currentText}", cursorPosition: ${cursorPosition}, counterField: ${localFieldCounter}, sessionCounter: ${imeSessionCounter}`);
            }
        }
        
        if (!isHudActive && imeSessionCounter !== lastDismissedSessionCounter) {
            console.log(`[Bridge] Auto-triggering Mac HUD from ShowRequest.`);
            triggerImeShow(currentText);
        }
    }

    if (message.remoteImeBatchEdit) {
        const batch = message.remoteImeBatchEdit;
        console.log(`[Bridge] TV emitted BatchEdit (ignored counters): imeCounter=${batch.imeCounter}, fieldCounter=${batch.fieldCounter}`);
    }
}

const host = process.argv[2];
if (!host) {
    console.error("[Bridge] Error: Please specify the Android TV IP address as an argument.");
    console.error("Usage: node tv_remote_bridge.js <TV_IP>");
    process.exit(1);
}

const isTesting = process.env.TV_KVM_TESTING === 'true';
const credentialsDir = isTesting 
    ? path.join(__dirname, '.credentials') 
    : path.join(os.homedir(), '.tv_kvm_credentials');
const certPath = path.join(credentialsDir, 'cert.json');

let cert = {};
if (fs.existsSync(certPath)) {
    try {
        cert = JSON.parse(fs.readFileSync(certPath, 'utf8'));
        console.log("[Bridge] Loaded saved TLS pairing certificate.");
    } catch (e) {
        console.error("[Bridge] Failed to read saved certificate:", e.message);
    }
}

let options = {
    pairing_port: 6467,
    remote_port: 6466,
    name: 'mac-tv-kvm',
    cert: cert
};

function setupAndroidRemote(remoteInstance) {
    let currentRemoteManager = null;
    Object.defineProperty(remoteInstance, 'remoteManager', {
        get() {
            return currentRemoteManager;
        },
        set(val) {
            currentRemoteManager = val;
            if (val) {
                console.log("[Bridge] New RemoteManager instance detected! Subscribing to events.");
                val.on('close', (hasError) => {
                    console.log("[Bridge] RemoteManager emitted close event (hasError:", hasError, ")");
                    reconnectTV();
                });
                val.on('error', (err) => {
                    console.error("[Bridge] RemoteManager emitted error event:", err.message || err);
                    reconnectTV();
                });
            }
        },
        configurable: true,
        enumerable: true
    });
}

let androidRemote = new AndroidRemote(host, options);
setupAndroidRemote(androidRemote);
let status = "DISCONNECTED"; // "DISCONNECTED", "NEED_PIN", "CONNECTING", "READY"
let activeSocket = null;

let currentText = "";
let cursorPosition = 0;
let imeSessionCounter = 1; // Tracks appInfo.counter (TV session ID)
let localFieldCounter = 1; // Tracks textFieldStatus.counterField (TV field edit ID)
let latestSentFieldCounter = 0; // Tracks the latest field counter sent to TV to avoid stale race conditions
let isHudActive = false; // Tracks whether the macOS input HUD is currently active
let lastDismissedSessionCounter = 0; // Tracks the ID of the text session dismissed by the user on Mac

function triggerImeShow(text) {
    if (activeSocket) {
        const base64Val = Buffer.from(text || "").toString('base64');
        activeSocket.write(`IME_SHOW ${base64Val}\n`);
        isHudActive = true;
    }
}

function sendImeText(text) {
    if (status !== "READY" || !androidRemote.remoteManager || !androidRemote.remoteManager.client) {
        console.warn("[Bridge] Cannot send IME text: remote not ready.");
        return;
    }
    
    // Использовать точные счетчики от ТВ
    let fieldCounter = localFieldCounter;
    let currentSession = imeSessionCounter;
    
    // Длина предыдущего текста, который мы хотим полностью заменить
    let oldTextLength = currentText.length;
    
    // Сразу локально обновляем буфер
    currentText = text;
    cursorPosition = text.length;
    
    // Сохраняем отправленный индекс транзакции во избежание гонки состояний
    latestSentFieldCounter = fieldCounter;
    
    // Инкрементируем localFieldCounter локально, так как мы отправляем новый эдит,
    // который изменит состояние на стороне ТВ.
    localFieldCounter++;
    
    try {
        // 1. Формируем чистый пакет RemoteImeBatchEdit по спецификации V2 (для нативных приложений)
        const batchPayload = {
            remoteImeBatchEdit: {
                imeCounter: currentSession,
                fieldCounter: fieldCounter,
                editInfo: [{
                    insert: 0,
                    textFieldStatus: {
                        start: 0,
                        end: oldTextLength,
                        value: text
                    }
                }]
            }
        };
        const batchPacket = remoteMessageManager.create(batchPayload);
        androidRemote.remoteManager.client.write(batchPacket);
        
        // 2. Формируем и отправляем пакет RemoteImeKeyInject (для WebView и браузеров, таких как BrowseHere)
        const activeApp = (latestAppInfo && latestAppInfo.appPackage) ? latestAppInfo.appPackage : "com.tcl.browser";
        const keyInjectPayload = {
            remoteImeKeyInject: {
                appInfo: {
                    appPackage: activeApp,
                    counter: currentSession
                },
                textFieldStatus: {
                    counterField: fieldCounter,
                    value: text,
                    start: text.length,
                    end: text.length
                }
            }
        };
        const keyInjectPacket = remoteMessageManager.create(keyInjectPayload);
        androidRemote.remoteManager.client.write(keyInjectPacket);
        
        console.log(`[Bridge] Injected BOTH BatchEdit and KeyInject for text: "${text}" (imeCounter: ${currentSession}, fieldCounter: ${fieldCounter})`);
    } catch (e) {
        console.error("[Bridge] Failed to send IME packets:", e.message);
    }
}

// Список приложений-браузеров, в которых InputDispatcher блокирует RemoteKeyInject
// из-за конфликта с активным IME-соединением (адресная строка WebView).
const BROWSER_PACKAGES = new Set([
    'com.tcl.browser',      // BrowseHere
    'com.opera.browser',
    'com.phlox.tvwebbrowser', // TV Bro
]);

// DPAD-клавиши, для которых применяется workaround при браузере
const BROWSER_WORKAROUND_KEYS = new Set([
    'KEYCODE_DPAD_UP', 'KEYCODE_DPAD_DOWN', 'KEYCODE_DPAD_LEFT', 'KEYCODE_DPAD_RIGHT',
    'KEYCODE_DPAD_CENTER', 'KEYCODE_ENTER',
    'KEYCODE_PAGE_UP', 'KEYCODE_PAGE_DOWN', 'KEYCODE_TAB'
]);

// Текущее активное приложение на ТВ (обновляется из remoteImeKeyInject.appInfo)
let currentActiveApp = '';

// Троттлинг применяется ТОЛЬКО к трекпаду в браузере (клавиатура не затрагивается)
let lastBrowserTrackpadTime = 0;
const BROWSER_TRACKPAD_THROTTLE_MS = 120;

function sendKeyDirect(keyName, isTrackpad) {
    let keyCode = null;
    if (/^\d+$/.test(keyName)) {
        const val = parseInt(keyName);
        const foundKey = Object.keys(RemoteKeyCode).find(k => RemoteKeyCode[k] === val);
        if (foundKey) {
            keyCode = RemoteKeyCode[foundKey];
        }
    } else {
        if (RemoteKeyCode[keyName] !== undefined) {
            keyCode = RemoteKeyCode[keyName];
        }
    }

    if (keyCode !== null && status === "READY") {
        // Эвристика: при нажатии Home сбрасываем контекст активного приложения
        if (keyName === 'KEYCODE_HOME') {
            console.log(`[Bridge] Home key detected, resetting currentActiveApp from "${currentActiveApp}" to ""`);
            currentActiveApp = '';
        }

        // Browser workaround: START_LONG + 70 мс + END_LONG
        // Применяется ТОЛЬКО для навигационных клавиш от ТРЕКПАДА в БРАУЗЕРЕ.
        // WebView BrowseHere требует ненулевое удержание кнопки для регистрации DPAD-события.
        // Клавиатура и все остальные приложения всегда получают мгновенный SHORT.
        if (isTrackpad && BROWSER_PACKAGES.has(currentActiveApp) && BROWSER_WORKAROUND_KEYS.has(keyName)) {
            const now = Date.now();
            if (now - lastBrowserTrackpadTime < BROWSER_TRACKPAD_THROTTLE_MS) {
                return; // Защита от перегрузки uinput-буфера ТВ
            }
            lastBrowserTrackpadTime = now;

            console.log(`[Bridge] sendKeyDirect (Trackpad+Browser): ${keyName} START_LONG (code=${keyCode})`);
            androidRemote.sendKey(keyCode, RemoteDirection.START_LONG);
            
            setTimeout(() => {
                if (status === "READY") {
                    console.log(`[Bridge] sendKeyDirect (Trackpad+Browser): ${keyName} END_LONG (code=${keyCode})`);
                    androidRemote.sendKey(keyCode, RemoteDirection.END_LONG);
                }
            }, 70);
            return;
        }

        console.log(`[Bridge] sendKeyDirect: ${keyName} (code=${keyCode}), trackpad=${!!isTrackpad}, activeApp="${currentActiveApp}"`);
        androidRemote.sendKey(keyCode, RemoteDirection.SHORT);
    } else {
        console.warn("[Bridge] Cannot send key:", keyName, "status:", status, "keyCode:", keyCode);
    }
}

// Send status line to local TCP socket
function sendStatus(currentStatus) {
    if (activeSocket) {
        activeSocket.write(`STATUS ${currentStatus}\n`);
    }
}

// Set up remote event listeners
androidRemote.on('secret', () => {
    console.log("[Bridge] PIN code verification required. Check the TV screen.");
    status = "NEED_PIN";
    sendStatus(status);
});

androidRemote.on('ready', () => {
    console.log("[Bridge] Google TV connection established and secure!");
    status = "READY";
    sendStatus(status);

    // Save cert on successful pairing so we don't prompt again
    try {
        const newCert = androidRemote.getCertificate();
        if (newCert && (!options.cert || JSON.stringify(newCert) !== JSON.stringify(options.cert))) {
            if (!fs.existsSync(credentialsDir)) {
                fs.mkdirSync(credentialsDir, { recursive: true });
                fs.chmodSync(credentialsDir, 0o700);
            }
            fs.writeFileSync(certPath, JSON.stringify(newCert), 'utf8');
            fs.chmodSync(certPath, 0o600);
            options.cert = newCert;
            console.log("[Bridge] Saved secure TLS pairing certificate to " + certPath);
        }
    } catch (e) {
        console.error("[Bridge] Error saving pairing certificate:", e.message);
    }
});

let reconnectTimeout = null;
let disconnectsHistory = [];

// Экспоненциальный backoff для переподключения к ТВ
const RECONNECT_DELAYS = [3000, 5000, 10000, 15000, 30000]; // 3с → 5с → 10с → 15с → 30с
let reconnectAttempt = 0;
let tvUnreachableNotified = false; // Отправлен ли TV_UNREACHABLE Swift-клиенту

function recordDisconnect() {
    const now = Date.now();
    disconnectsHistory.push(now);
    // Оставляем только дисконнекты за последние 20 секунд
    disconnectsHistory = disconnectsHistory.filter(t => now - t < 20000);
    
    if (disconnectsHistory.length >= 3) {
        console.warn("[Bridge] Connection conflict detected! 3 disconnects in 20 seconds.");
        status = "DISCONNECTED";
        sendStatus("CONFLICT");
        
        if (reconnectTimeout) {
            clearTimeout(reconnectTimeout);
            reconnectTimeout = null;
        }
        try {
            androidRemote.stop();
        } catch(e) {}
        return true; // Конфликт обнаружен
    }
    return false;
}

function reconnectTV() {
    if (status === "DISCONNECTED") {
        return;
    }
    
    // Проверяем конфликт перед попыткой реконнекта
    if (recordDisconnect()) {
        return;
    }
    
    if (reconnectTimeout) {
        clearTimeout(reconnectTimeout);
    }
    
    console.log("[Bridge] Reconnection triggered. Clean stopping first...");
    try {
        androidRemote.stop();
    } catch(e) {}
    
    status = "CONNECTING";
    sendStatus(status);
    
    // Экспоненциальный backoff: берём задержку из массива (или максимальную)
    const delay = RECONNECT_DELAYS[Math.min(reconnectAttempt, RECONNECT_DELAYS.length - 1)];
    reconnectAttempt++;
    console.log(`[Bridge] Reconnect attempt #${reconnectAttempt}, delay: ${delay}ms`);
    
    reconnectTimeout = setTimeout(() => {
        console.log("[Bridge] Reconnecting to Android TV...");
        androidRemote.start().then(() => {
            console.log("[Bridge] New start() call successfully resolved connection!");
            // При успешном соединении сбрасываем backoff и историю
            reconnectAttempt = 0;
            tvUnreachableNotified = false;
            disconnectsHistory = [];
        }).catch((err) => {
            console.error("[Bridge] Reconnect start() failed:", err.message || err);
            // После первого неудачного подключения — отправляем TV_UNREACHABLE
            if (!tvUnreachableNotified) {
                tvUnreachableNotified = true;
                sendStatus("TV_UNREACHABLE");
            }
            reconnectTV();
        });
    }, delay);
}

androidRemote.on('unpaired', () => {
    console.log("[Bridge] TV indicated connection is unpaired.");
    status = "DISCONNECTED";
    sendStatus(status);
});

androidRemote.on('error', (err) => {
    const errMsg = String(err.message || err);
    console.error("[Bridge] Connection error:", errMsg);
    
    // Самодиагностика: проверка на отклонение сертификата безопасности телевизором (SSL Alert 46)
    if (errMsg.toLowerCase().includes("certificate unknown") || errMsg.toLowerCase().includes("alert number 46")) {
        console.warn("[Bridge] Self-Diagnostics: TV explicitly rejected secure certificate (SSL Alert 46). Sending CERT_REJECTED status.");
        status = "DISCONNECTED";
        sendStatus("CERT_REJECTED");
        return; // Останавливаем бесконечный цикл переподключения с недействительным сертификатом
    }
    
    reconnectTV();
});
// Start local TCP Server binding strictly to loopback 127.0.0.1
const server = net.createServer((socket) => {
    console.log("[Bridge] macOS Swift client connected.");
    activeSocket = socket;

    // Send the current status immediately upon connection
    sendStatus(status);

    let buffer = "";
    socket.on('data', (data) => {
        buffer += data.toString();
        let lines = buffer.split('\n');
        buffer = lines.pop(); // Hold onto incomplete last line

        for (let line of lines) {
            handleCommand(line.trim());
        }
    });

    socket.on('close', () => {
        console.log("[Bridge] macOS Swift client disconnected.");
        if (activeSocket === socket) {
            activeSocket = null;
            isHudActive = false;
        }
    });

    socket.on('error', (err) => {
        console.error("[Bridge] TCP socket error:", err.message);
    });
});

function handleCommand(cmd) {
    if (!cmd) return;
    console.log("[Bridge] Processing command from Swift:", cmd);

    if (cmd.startsWith("PIN ")) {
        const pin = cmd.substring(4).trim();
        console.log("[Bridge] Injecting pairing PIN code:", pin);
        androidRemote.sendCode(pin);
    } else if (cmd.startsWith("SET_TEXT")) {
        const base64Text = cmd.substring(8).trim();
        if (base64Text === "") {
            console.log("[Bridge] Local IME text buffer cleared (empty SET_TEXT).");
            sendImeText("");
        } else {
            try {
                const text = Buffer.from(base64Text, 'base64').toString('utf8');
                sendImeText(text);
            } catch (e) {
                console.error("[Bridge] Failed to decode Base64 SET_TEXT:", e.message);
            }
        }
    } else if (cmd.startsWith("CHAR ")) {
        const base64Char = cmd.substring(5).trim();
        try {
            const char = Buffer.from(base64Char, 'base64').toString('utf8');
            // Вставляем символ в позицию курсора
            const newText = currentText.slice(0, cursorPosition) + char + currentText.slice(cursorPosition);
            sendImeText(newText);
        } catch (e) {
            console.error("[Bridge] Failed to decode Base64 CHAR:", e.message);
        }
    } else if (cmd === "RESET") {
        currentText = "";
        cursorPosition = 0;
        latestSentFieldCounter = 0;
        isHudActive = false;
        lastDismissedSessionCounter = imeSessionCounter;
        console.log("[Bridge] Local IME text buffer reset (HUD closed).");
    } else if (cmd.startsWith("KEY ") || cmd.startsWith("TRACKPAD ")) {
        const isTrackpad = cmd.startsWith("TRACKPAD ");
        const keyName = cmd.substring(isTrackpad ? 9 : 4).trim();
        
        if (keyName === "KEYCODE_DEL") {
            if (cursorPosition > 0) {
                const newText = currentText.slice(0, cursorPosition - 1) + currentText.slice(cursorPosition);
                sendImeText(newText);
            } else {
                // Если буфер пуст, на всякий случай пересылаем DEL на ТВ
                sendKeyDirect(keyName, isTrackpad);
            }
        } else if (keyName === "KEYCODE_DPAD_LEFT") {
            if (cursorPosition > 0) {
                cursorPosition--;
            }
            sendKeyDirect(keyName, isTrackpad);
        } else if (keyName === "KEYCODE_DPAD_RIGHT") {
            if (cursorPosition < currentText.length) {
                cursorPosition++;
            }
            sendKeyDirect(keyName, isTrackpad);
        } else if (keyName === "KEYCODE_ENTER") {
            currentText = "";
            cursorPosition = 0;
            sendKeyDirect(keyName, isTrackpad);
        } else {
            sendKeyDirect(keyName, isTrackpad);
        }
    } else if (cmd.startsWith("HOLD_START ")) {
        // Непрерывное удержание стрелки: имитация зажатой кнопки физического пульта
        const keyName = cmd.substring(11).trim();
        const keyCode = RemoteKeyCode[keyName];
        if (keyCode !== undefined && status === "READY") {
            console.log(`[Bridge] HOLD_START: ${keyName} (code=${keyCode}), activeApp="${currentActiveApp}"`);
            androidRemote.sendKey(keyCode, RemoteDirection.START_LONG);
        }
    } else if (cmd.startsWith("HOLD_END ")) {
        // Отпускание зажатой стрелки
        const keyName = cmd.substring(9).trim();
        const keyCode = RemoteKeyCode[keyName];
        if (keyCode !== undefined && status === "READY") {
            console.log(`[Bridge] HOLD_END: ${keyName} (code=${keyCode})`);
            androidRemote.sendKey(keyCode, RemoteDirection.END_LONG);
        }
    } else if (cmd === "CONNECT") {
        if (status === "DISCONNECTED" || status === "CONNECTING") {
            // Сброс состояния реконнекта и конфликтов при ручном подключении
            reconnectAttempt = 0;
            tvUnreachableNotified = false;
            disconnectsHistory = [];
            if (reconnectTimeout) {
                clearTimeout(reconnectTimeout);
                reconnectTimeout = null;
            }
            
            status = "CONNECTING";
            sendStatus(status);
            
            // Прямое подключение без задержки (в отличие от reconnectTV с backoff)
            console.log("[Bridge] Direct CONNECT: starting androidRemote.start()...");
            try {
                androidRemote.stop();
            } catch(e) {}
            androidRemote = new AndroidRemote(host, options);
            setupAndroidRemote(androidRemote);
            
            // Переподписываемся на события нового экземпляра
            androidRemote.on('secret', () => {
                console.log("[Bridge] PIN code verification required. Check the TV screen.");
                status = "NEED_PIN";
                sendStatus(status);
            });
            androidRemote.on('ready', () => {
                console.log("[Bridge] Google TV connection established and secure!");
                status = "READY";
                sendStatus(status);
                try {
                    const newCert = androidRemote.getCertificate();
                    if (newCert && (!options.cert || JSON.stringify(newCert) !== JSON.stringify(options.cert))) {
                        if (!fs.existsSync(credentialsDir)) {
                            fs.mkdirSync(credentialsDir, { recursive: true });
                            fs.chmodSync(credentialsDir, 0o700);
                        }
                        fs.writeFileSync(certPath, JSON.stringify(newCert), 'utf8');
                        fs.chmodSync(certPath, 0o600);
                        options.cert = newCert;
                        console.log("[Bridge] Saved secure TLS pairing certificate to " + certPath);
                    }
                } catch (e) {
                    console.error("[Bridge] Error saving pairing certificate:", e.message);
                }
            });
            androidRemote.on('unpaired', () => {
                console.log("[Bridge] TV indicated connection is unpaired.");
                status = "DISCONNECTED";
                sendStatus(status);
            });
            androidRemote.on('error', (err) => {
                console.error("[Bridge] Connection error:", err.message || err);
                reconnectTV();
            });
            androidRemote.start().then(() => {
                console.log("[Bridge] Direct CONNECT: start() resolved successfully!");
                reconnectAttempt = 0;
                tvUnreachableNotified = false;
                disconnectsHistory = [];
            }).catch((err) => {
                console.error("[Bridge] Direct CONNECT failed:", err.message || err);
                if (!tvUnreachableNotified) {
                    tvUnreachableNotified = true;
                    sendStatus("TV_UNREACHABLE");
                }
            });
        }
    } else if (cmd === "DISCONNECT") {
        console.log("[Bridge] Stopping Google TV remote...");
        androidRemote.stop();
        status = "DISCONNECTED";
        sendStatus(status);
    } else if (cmd === "UNPAIR") {
        console.log("[Bridge] Unpairing and deleting credentials...");
        if (fs.existsSync(certPath)) {
            try {
                fs.unlinkSync(certPath);
                console.log("[Bridge] Deleted cert.json successfully.");
            } catch (e) {
                console.error("[Bridge] Failed to delete cert.json:", e.message);
            }
        }
        androidRemote.stop();
        status = "DISCONNECTED";
        sendStatus(status);
        options.cert = {};
    }
}

// Bind TCP server strictly to local loopback 127.0.0.1 on port 12345
server.listen(12345, "127.0.0.1", () => {
    console.log("[Bridge] Local TCP server running on 127.0.0.1:12345");
});

// Периодическая проверка статуса соединения (Heartbeat) каждые 2 секунды.
// Сверхлегкий процесс, не нагружающий процессор Mac (0% CPU).
const heartbeatInterval = setInterval(() => {
    if (status === "READY") {
        const client = androidRemote.remoteManager ? androidRemote.remoteManager.client : null;
        if (!client || client.destroyed || client.readyState !== "open") {
            console.log("[Bridge] Heartbeat: Google TV connection lost (socket closed).");
            reconnectTV();
        }
    }
}, 2000);

// Graceful shutdown: освобождаем порт 12345 и закрываем соединение с ТВ
function gracefulShutdown(signal) {
    console.log(`[Bridge] Received ${signal}. Shutting down gracefully...`);
    
    // Останавливаем heartbeat
    if (heartbeatInterval) {
        clearInterval(heartbeatInterval);
    }
    
    // Отменяем таймер реконнекта
    if (reconnectTimeout) {
        clearTimeout(reconnectTimeout);
        reconnectTimeout = null;
    }
    
    // Закрываем соединение с ТВ
    try {
        androidRemote.stop();
    } catch(e) {}
    
    // Закрываем TCP-клиент
    if (activeSocket) {
        try {
            activeSocket.destroy();
        } catch(e) {}
        activeSocket = null;
    }
    
    // Закрываем TCP-сервер (освобождаем порт 12345)
    server.close(() => {
        console.log("[Bridge] TCP server closed. Port 12345 freed.");
        process.exit(0);
    });
    
    // Принудительный выход через 3 секунды если server.close() зависнет
    setTimeout(() => {
        console.log("[Bridge] Forced exit after timeout.");
        process.exit(1);
    }, 3000).unref();
}

process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT', () => gracefulShutdown('SIGINT'));
process.on('SIGHUP', () => gracefulShutdown('SIGHUP'));

// Перехват необработанных ошибок для предотвращения крашей моста
process.on('uncaughtException', (err) => {
    console.error("[Bridge] UNCAUGHT EXCEPTION (bridge stays alive):", err.message || err);
});

process.on('unhandledRejection', (reason) => {
    console.error("[Bridge] UNHANDLED REJECTION (bridge stays alive):", reason);
});
