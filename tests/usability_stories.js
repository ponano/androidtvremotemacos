const fs = require('fs');
const path = require('path');
const net = require('net');
const assert = require('assert');

// ============================================================================
// 1. ИНТЕЛЛЕКТУАЛЬНЫЙ МОК ДЛЯ БИБЛИОТЕКИ androidtv-remote
// ============================================================================
const mockEvents = {};
let mockRemoteInstance = null;

class MockAndroidRemote {
    constructor(host, options) {
        this.host = host;
        this.options = options;
        this.listeners = {};
        this.hasStarted = false;
        this.remoteManager = {
            client: {
                write: (packet) => {
                    // Парсим и сохраняем сгенерированный пакет
                    // В нашем случае это JS объект или Buffer
                    if (Buffer.isBuffer(packet)) {
                        try {
                            const parsed = JSON.parse(packet.toString());
                            MockAndroidRemote.createdPackets.push(parsed);
                        } catch(e) {
                            MockAndroidRemote.createdPackets.push(packet);
                        }
                    } else {
                        MockAndroidRemote.createdPackets.push(packet);
                    }
                }
            }
        };
        mockRemoteInstance = this;
    }

    on(event, cb) {
        if (!this.listeners[event]) {
            this.listeners[event] = [];
        }
        this.listeners[event].push(cb);
    }

    emit(event, ...args) {
        if (this.listeners[event]) {
            this.listeners[event].forEach(cb => cb(...args));
        }
    }

    async start() {
        this.hasStarted = true;
        return true;
    }

    stop() {
        this.hasStarted = false;
    }

    sendKey(code, direction) {
        MockAndroidRemote.sentKeys.push({ code, direction });
    }

    sendCode(pin) {
        MockAndroidRemote.sentPin = pin;
    }

    getCertificate() {
        return { cert: "mock_test_certificate_pem_data" };
    }
}

MockAndroidRemote.sentKeys = [];
MockAndroidRemote.sentPin = null;

// Перехватываем require в Node.js
const moduleAlias = require('module');
const originalRequire = moduleAlias.prototype.require;
moduleAlias.prototype.require = function(requirePath) {
    if (requirePath === 'androidtv-remote') {
        return {
            AndroidRemote: MockAndroidRemote,
            RemoteKeyCode: {
                KEYCODE_A: 29,
                KEYCODE_DEL: 67,
                KEYCODE_DPAD_UP: 19,
                KEYCODE_DPAD_DOWN: 20,
                KEYCODE_DPAD_LEFT: 21,
                KEYCODE_DPAD_RIGHT: 22,
                KEYCODE_ENTER: 66,
                KEYCODE_VOLUME_UP: 24,
                KEYCODE_VOLUME_DOWN: 25,
                KEYCODE_HOME: 3
            },
            RemoteDirection: {
                SHORT: 3,
                START_LONG: 1,
                END_LONG: 2
            }
        };
    }
    if (requirePath === 'androidtv-remote/dist/remote/RemoteMessageManager') {
        return {
            remoteMessageManager: {
                parse: jestFn => jestFn,
                create: (payload) => {
                    MockAndroidRemote.createdPackets.push(payload);
                    return Buffer.from(JSON.stringify(payload));
                }
            }
        };
    }
    return originalRequire.apply(this, arguments);
};

MockAndroidRemote.createdPackets = [];

// ============================================================================
// 2. ПОДГОТОВКА СРЕДЫ ДЛЯ ЗАПУСКА tv_remote_bridge.js
// ============================================================================
// Мокаем аргументы командной строки
process.argv = ['node', 'tv_remote_bridge.js', '127.0.0.1'];

// Удаляем сертификаты из предыдущих тестов, чтобы проверить полный цикл
const certDir = path.join(__dirname, '../.credentials');
const certPath = path.join(certDir, 'cert.json');
if (fs.existsSync(certPath)) {
    try { fs.unlinkSync(certPath); } catch(e) {}
}

// Запускаем бэкенд-мост
console.log("🚀 Запуск KVM TCP моста в тестовом режиме...");
require('../tv_remote_bridge.js');

// ============================================================================
// 3. АВТОМАТИЧЕСКИЕ ТЕСТЫ ЮЗЕРСТОРИ (USABILITY STORIES)
// ============================================================================
async function runTests() {
    console.log("\n================ ЗАПУСК АВТОТЕСТОВ ЮЗЕРСТОРИ ================");

    const client = net.connect({ port: 12345, host: '127.0.0.1' });
    let receivedBuffer = "";
    let statusResolver = null;
    const statusHistory = [];

    client.on('data', (data) => {
        receivedBuffer += data.toString();
        let lines = receivedBuffer.split('\n');
        receivedBuffer = lines.pop();

        for (let line of lines) {
            const trimmed = line.trim();
            if (trimmed.startsWith("STATUS ")) {
                const status = trimmed.replace("STATUS ", "");
                console.log(`   [Сокет] Получен статус от моста: ${status}`);
                statusHistory.push(status);
                if (statusResolver) {
                    statusResolver(status);
                }
            }
        }
    });

    const waitForStatus = (expectedStatus) => {
        if (expectedStatus && statusHistory.includes(expectedStatus)) {
            return Promise.resolve(expectedStatus);
        }
        return new Promise(resolve => {
            const checkAndResolve = (status) => {
                if (!expectedStatus || status === expectedStatus) {
                    resolve(status);
                } else {
                    statusResolver = checkAndResolve;
                }
            };
            statusResolver = checkAndResolve;
        });
    };

    try {
        // --------------------------------------------------------------------
        // User Story 1: Сопряжение устройств и генерация TLS-сертификата
        // --------------------------------------------------------------------
        console.log("\n👤 [User Story 1] Первое сопряжение телевизора и Mac");
        
        // Симулируем, что телевизор попросил ввести PIN (эмитируем событие 'secret')
        console.log("   -> Телевизор генерирует PIN-код и отправляет событие 'secret'");
        mockRemoteInstance.emit('secret');
        
        let status = await waitForStatus("NEED_PIN");
        assert.strictEqual(status, "NEED_PIN", "Мост должен переключиться в NEED_PIN");
        console.log("   ✅ Успешно: На Mac отображен статус ввода PIN");

        // Пользователь вводит PIN на Mac (отправляем по TCP "PIN 123456")
        console.log("   -> Пользователь вводит PIN '777888' в окно на Mac");
        client.write("PIN 777888\n");
        await new Promise(r => setTimeout(r, 100));
        assert.strictEqual(MockAndroidRemote.sentPin, "777888", "PIN-код должен быть доставлен в библиотеку ТВ");
        console.log("   ✅ Успешно: PIN отправлен в зашифрованный TLS-канал");

        // Эмулируем успешное сопряжение
        console.log("   -> Телевизор подтверждает правильность кода PIN");
        
        // Устанавливаем remoteManager, чтобы вызвать сеттер в tv_remote_bridge.js
        mockRemoteInstance.remoteManager = {
            client: {
                write: (packet) => {
                    if (Buffer.isBuffer(packet)) {
                        try {
                            const parsed = JSON.parse(packet.toString());
                            MockAndroidRemote.createdPackets.push(parsed);
                        } catch(e) {
                            MockAndroidRemote.createdPackets.push(packet);
                        }
                    } else {
                        MockAndroidRemote.createdPackets.push(packet);
                    }
                }
            },
            on: (event, cb) => {
                // Поддержка подписки на события 'close' / 'error' для RemoteManager
                mockRemoteInstance.listeners[event] = mockRemoteInstance.listeners[event] || [];
                mockRemoteInstance.listeners[event].push(cb);
            }
        };
        
        mockRemoteInstance.emit('ready');
        status = await waitForStatus("READY");
        assert.strictEqual(status, "READY", "Мост должен перейти в статус READY");
        console.log("   ✅ Успешно: Соединение установлено (🟢 Connected)");

        // Проверяем запись сертификата
        assert.ok(fs.existsSync(certPath), "Сертификат сопряжения должен быть записан на диск");
        const savedCert = JSON.parse(fs.readFileSync(certPath, 'utf8'));
        assert.strictEqual(savedCert.cert, "mock_test_certificate_pem_data", "Содержимое сертификата должно совпадать с выданным ТВ");
        console.log("   ✅ Успешно: Сертификат сохранен для автоподключения");

        // --------------------------------------------------------------------
        // User Story 2: Навигация жестами трекпада
        // --------------------------------------------------------------------
        console.log("\n👤 [User Story 2] Навигация свайпами по трекпаду");
        
        MockAndroidRemote.sentKeys = [];
        console.log("   -> Симулируем свайп Вверх (TRACKPAD KEYCODE_DPAD_UP)");
        client.write("TRACKPAD KEYCODE_DPAD_UP\n");
        await new Promise(r => setTimeout(r, 100));
        
        assert.strictEqual(MockAndroidRemote.sentKeys.length, 1, "Команда должна отправиться");
        assert.strictEqual(MockAndroidRemote.sentKeys[0].code, 19, "Код кнопки должен быть 19 (DPAD_UP)");
        console.log("   ✅ Успешно: Свайп трекпада транслирован в команду ТВ");

        // --------------------------------------------------------------------
        // User Story 3: Быстрый аппаратный и IME ввод текста (EN/RU)
        // --------------------------------------------------------------------
        console.log("\n👤 [User Story 3] Аппаратный набор букв и фолбэк ввода");
        
        MockAndroidRemote.sentKeys = [];
        console.log("   -> Пользователь нажимает аппаратную клавишу 'A' на Mac");
        client.write("KEY KEYCODE_A\n");
        await new Promise(r => setTimeout(r, 100));
        assert.strictEqual(MockAndroidRemote.sentKeys[0].code, 29, "Код кнопки должен быть 29 (KEYCODE_A)");
        console.log("   ✅ Успешно: Клавиша клавиатуры эмулирована напрямую на ТВ");

        MockAndroidRemote.createdPackets = [];
        const testText = "Привет!";
        const base64Text = Buffer.from(testText).toString('base64');
        console.log(`   -> Пользователь вводит строку "${testText}" через HUD моста`);
        client.write(`SET_TEXT ${base64Text}\n`);
        await new Promise(r => setTimeout(r, 150));

        // Мост должен отправить BatchEdit и KeyInject
        const hasBatchEdit = MockAndroidRemote.createdPackets.some(p => p.remoteImeBatchEdit);
        const hasKeyInject = MockAndroidRemote.createdPackets.some(p => p.remoteImeKeyInject);
        assert.ok(hasBatchEdit, "Пакет BatchEdit должен быть сгенерирован");
        assert.ok(hasKeyInject, "Пакет KeyInject должен быть сгенерирован");
        console.log("   ✅ Успешно: Текст передан одновременно через BatchEdit и KeyInject (IME)");

        // --------------------------------------------------------------------
        // User Story 4: Защита от конфликта одновременного управления
        // --------------------------------------------------------------------
        console.log("\n👤 [User Story 4] Защита от конфликта подключений (Conflict Intercept)");
        
        // Симулируем, что кто-то перехватил управление (3 дисконнекта подряд)
        console.log("   -> Происходит 3 обрыва связи с ТВ за короткое время...");
        mockRemoteInstance.emit('error', new Error("Connection reset"));
        await new Promise(r => setTimeout(r, 50));
        mockRemoteInstance.emit('error', new Error("Connection reset"));
        await new Promise(r => setTimeout(r, 50));
        mockRemoteInstance.emit('error', new Error("Connection reset"));
        
        status = await waitForStatus("CONFLICT");
        assert.strictEqual(status, "CONFLICT", "Мост должен сообщить CONFLICT для предотвращения спама в сеть");
        console.log("   ✅ Успешно: Защита от конфликта активирована (статус CONFLICT)");

        // ====================================================================
        // ЗАКРЫТИЕ КЛИЕНТА И ЗАВЕРШЕНИЕ
        // ====================================================================
        client.destroy();
        console.log("\n=============================================================");
        console.log("🎉 ВСЕ ТЕСТЫ ЮЗЕРСТОРИ ПРОЙДЕНЫ УСПЕШНО (100% OK)");
        console.log("=============================================================");
        process.exit(0);

    } catch (err) {
        console.error("\n❌ ОШИБКА ПРИ ВЫПОЛНЕНИИ ТЕСТА:");
        console.error(err);
        client.destroy();
        process.exit(1);
    }
}

// Задержка перед стартом, чтобы TCP сервер моста успел привязаться к порту
setTimeout(runTests, 1000);
