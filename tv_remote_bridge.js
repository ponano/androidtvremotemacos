const fs = require('fs');
const path = require('path');
const net = require('net');
const { AndroidRemote, RemoteKeyCode, RemoteDirection } = require('androidtv-remote');
const { remoteMessageManager } = require('androidtv-remote/dist/remote/RemoteMessageManager');

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
                if (activeSocket) {
                    activeSocket.write(`APP ${ime.appInfo.appPackage}\n`);
                }
                // Автовызов IME_SHOW на Mac при старте текстовой сессии в сторонних приложениях (не лаунчерах)
                if (!ime.appInfo.appPackage.includes("launcher")) {
                    console.log(`[Bridge] Auto-triggering IME_SHOW for active app: ${ime.appInfo.appPackage}`);
                    if (activeSocket) {
                        const base64Val = Buffer.from(currentText || "").toString('base64');
                        activeSocket.write(`IME_SHOW ${base64Val}\n`);
                    }
                }
            }
        }
        
        if (ime.textFieldStatus) {
            latestTextFieldStatus = ime.textFieldStatus;
            
            const tvFieldCounter = ime.textFieldStatus.counterField;
            if (tvFieldCounter !== undefined && tvFieldCounter !== null) {
                if (tvFieldCounter < latestSentFieldCounter) {
                    console.log(`[Bridge] Ignored stale remoteImeKeyInject status (TV counter: ${tvFieldCounter}, latest sent: ${latestSentFieldCounter})`);
                } else {
                    localFieldCounter = tvFieldCounter;
                    if (ime.textFieldStatus.value !== undefined && ime.textFieldStatus.value !== null) {
                        currentText = ime.textFieldStatus.value;
                        cursorPosition = ime.textFieldStatus.start !== undefined ? ime.textFieldStatus.start : currentText.length;
                    }
                    console.log(`[Bridge] Sync from TV (KeyInject): "${currentText}", cursorPosition: ${cursorPosition}, counterField: ${localFieldCounter}, sessionCounter: ${imeSessionCounter}`);
                    if (activeSocket) {
                        const base64Val = Buffer.from(currentText || "").toString('base64');
                        activeSocket.write(`IME_SHOW ${base64Val}\n`);
                    }
                }
            }
        }
    }

    if (message.remoteImeShowRequest) {
        const status = message.remoteImeShowRequest.remoteTextFieldStatus;
        if (status) {
            latestTextFieldStatus = status;
            
            const tvFieldCounter = status.counterField;
            if (tvFieldCounter !== undefined && tvFieldCounter !== null) {
                if (tvFieldCounter < latestSentFieldCounter) {
                    console.log(`[Bridge] Ignored stale remoteImeShowRequest status (TV counter: ${tvFieldCounter}, latest sent: ${latestSentFieldCounter})`);
                } else {
                    localFieldCounter = tvFieldCounter;
                    if (status.value !== undefined && status.value !== null) {
                        currentText = status.value;
                        cursorPosition = status.start !== undefined ? status.start : currentText.length;
                    }
                    console.log(`[Bridge] Sync from TV (ShowRequest): "${currentText}", cursorPosition: ${cursorPosition}, counterField: ${localFieldCounter}, sessionCounter: ${imeSessionCounter}`);
                    if (activeSocket) {
                        const base64Val = Buffer.from(currentText || "").toString('base64');
                        activeSocket.write(`IME_SHOW ${base64Val}\n`);
                    }
                }
            }
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

const credentialsDir = path.join(__dirname, '.credentials');
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

let androidRemote = new AndroidRemote(host, options);
let status = "DISCONNECTED"; // "DISCONNECTED", "NEED_PIN", "CONNECTING", "READY"
let activeSocket = null;

let currentText = "";
let cursorPosition = 0;
let imeSessionCounter = 1; // Tracks appInfo.counter (TV session ID)
let localFieldCounter = 1; // Tracks textFieldStatus.counterField (TV field edit ID)
let latestSentFieldCounter = 0; // Tracks the latest field counter sent to TV to avoid stale race conditions

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
        // Формируем чистый пакет RemoteImeBatchEdit по спецификации V2
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
        
        console.log(`[Bridge] Injected BatchEdit for text: "${text}" (replaced 0..${oldTextLength}), imeCounter: ${currentSession}, fieldCounter: ${fieldCounter}`);
    } catch (e) {
        console.error("[Bridge] Failed to send IME packets:", e.message);
    }
}

function sendKeyDirect(keyName) {
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
        androidRemote.sendKey(keyCode, RemoteDirection.SHORT);
    } else {
        console.warn("[Bridge] Cannot send key:", keyName);
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
            console.log("[Bridge] Saved secure TLS pairing certificate to .credentials/cert.json");
        }
    } catch (e) {
        console.error("[Bridge] Error saving pairing certificate:", e.message);
    }
});

let reconnectTimeout = null;
let disconnectsHistory = [];

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
    
    reconnectTimeout = setTimeout(() => {
        console.log("[Bridge] Reconnecting to Android TV...");
        androidRemote.start().then(() => {
            console.log("[Bridge] New start() call successfully resolved connection!");
            // При успешном соединении сбрасываем историю дисконнектов
            disconnectsHistory = [];
        }).catch((err) => {
            console.error("[Bridge] Reconnect start() failed:", err.message || err);
            reconnectTV();
        });
    }, 3000);
}

androidRemote.on('unpaired', () => {
    console.log("[Bridge] TV indicated connection is unpaired.");
    status = "DISCONNECTED";
    sendStatus(status);
});

androidRemote.on('error', (err) => {
    console.error("[Bridge] Connection error:", err.message || err);
    reconnectTV();
});

if (androidRemote.remoteManager) {
    androidRemote.remoteManager.on('close', (hasError) => {
        console.log("[Bridge] RemoteManager emitted close event (hasError:", hasError, ")");
        reconnectTV();
    });
}

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
        console.log("[Bridge] Local IME text buffer reset.");
    } else if (cmd.startsWith("KEY ")) {
        const keyName = cmd.substring(4).trim();
        
        if (keyName === "KEYCODE_DEL") {
            if (cursorPosition > 0) {
                const newText = currentText.slice(0, cursorPosition - 1) + currentText.slice(cursorPosition);
                sendImeText(newText);
            } else {
                // Если буфер пуст, на всякий случай пересылаем DEL на ТВ
                sendKeyDirect(keyName);
            }
        } else if (keyName === "KEYCODE_DPAD_LEFT") {
            if (cursorPosition > 0) {
                cursorPosition--;
            }
            sendKeyDirect(keyName);
        } else if (keyName === "KEYCODE_DPAD_RIGHT") {
            if (cursorPosition < currentText.length) {
                cursorPosition++;
            }
            sendKeyDirect(keyName);
        } else if (keyName === "KEYCODE_ENTER") {
            currentText = "";
            cursorPosition = 0;
            sendKeyDirect(keyName);
        } else {
            sendKeyDirect(keyName);
        }
    } else if (cmd === "CONNECT") {
        if (status === "DISCONNECTED" || status === "CONNECTING") {
            status = "CONNECTING";
            sendStatus(status);
            reconnectTV();
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
setInterval(() => {
    if (status === "READY") {
        const client = androidRemote.remoteManager ? androidRemote.remoteManager.client : null;
        if (!client || client.destroyed || client.readyState !== "open") {
            console.log("[Bridge] Heartbeat: Google TV connection lost (socket closed).");
            reconnectTV();
        }
    }
}, 2000);
