const fs = require('fs');
const path = require('path');
const net = require('net');
const { AndroidRemote, RemoteKeyCode, RemoteDirection } = require('androidtv-remote');

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

androidRemote.on('unpaired', () => {
    console.log("[Bridge] TV indicated connection is unpaired. Deleting credentials...");
    status = "DISCONNECTED";
    sendStatus(status);
    if (fs.existsSync(certPath)) {
        try {
            fs.unlinkSync(certPath);
        } catch(e) {}
    }
    options.cert = {};
});

androidRemote.on('error', (err) => {
    console.error("[Bridge] Connection error:", err.message || err);
    status = "DISCONNECTED";
    sendStatus(status);
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
    } else if (cmd.startsWith("KEY ")) {
        const keyName = cmd.substring(4).trim();
        let keyCode = null;

        // Map keycode name or number
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
            console.warn("[Bridge] Cannot send key. Code invalid or connection not ready. Key:", keyName, "Status:", status);
        }
    } else if (cmd === "CONNECT") {
        if (status === "DISCONNECTED") {
            console.log("[Bridge] Starting pairing/connection handshake...");
            status = "CONNECTING";
            sendStatus(status);
            androidRemote.start().catch((err) => {
                console.error("[Bridge] Failed to start remote:", err);
                status = "DISCONNECTED";
                sendStatus(status);
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
