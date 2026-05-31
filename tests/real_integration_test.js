const net = require('net');

// Сброс цвета терминала
const NC = '\033[0m';
const GREEN = '\033[0;32m';
const RED = '\033[0;31m';
const BLUE = '\033[0;34m';
const YELLOW = '\033[1;33m';

console.log("==========================================================");
console.log(" 📺 ИНТЕГРАЦИОННЫЙ ТЕСТ НА РЕАЛЬНОМ ОКРУЖЕНИИ (Pano KVM)");
console.log("==========================================================");
console.log(" Этот скрипт автоматически инициирует подключение к ТВ");
console.log(" и отправит настоящие команды после установления связи.\n");

let connectionEstablished = false;

const client = net.connect({ port: 12345, host: '127.0.0.1' }, () => {
    console.log(`${GREEN}✅ Соединение с локальным TCP мостом установлено!${NC}`);
    console.log(`${YELLOW}🔄 Инициируем подключение моста к вашему ТВ (CONNECT)...${NC}`);
    client.write("CONNECT\n");
});

client.on('error', (err) => {
    console.error(`\n${RED}❌ Ошибка подключения к мосту: ${err.message}${NC}`);
    console.log(`${YELLOW}Убедитесь, что KVM-мост запущен (bash run_kvm.sh) и работает.${NC}`);
    process.exit(1);
});

let receivedBuffer = "";
client.on('data', (data) => {
    receivedBuffer += data.toString();
    const lines = receivedBuffer.split('\n');
    receivedBuffer = lines.pop();

    for (let line of lines) {
        const trimmed = line.trim();
        if (trimmed) {
            console.log(`   [Мост ➔ Swift] ${trimmed}`);
        }

        if (trimmed === "STATUS READY") {
            if (!connectionEstablished) {
                connectionEstablished = true;
                console.log(`\n${GREEN}🟢 ТВ подключен и готов к работе! Запуск сценария...${NC}`);
                runTestScenario();
            }
        } else if (trimmed === "STATUS NEED_PIN") {
            console.log(`\n${YELLOW}⚠️  ТРЕБУЕТСЯ СОПРЯЖЕНИЕ: Пожалуйста, посмотрите на экран вашего ТВ, найдите 6-значный PIN-код и введите его в появившемся окне на Mac-клиенте!${NC}`);
        } else if (trimmed === "STATUS CONFLICT") {
            console.log(`\n${RED}🛑 КОНФЛИКТ: Обнаружен конфликт подключений к ТВ. Переподключение заблокировано.${NC}`);
            client.destroy();
            process.exit(1);
        }
    }
});

function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

async function runTestScenario() {
    try {
        console.log(`\n${BLUE}👉 ШАГ 1: Возврат на домашний экран (KEYCODE_HOME)...${NC}`);
        console.log("   Отправка: KEY KEYCODE_HOME");
        client.write("KEY KEYCODE_HOME\n");
        await sleep(2500);

        console.log(`\n${BLUE}👉 ШАГ 2: Перемещение фокуса вправо (TRACKPAD KEYCODE_DPAD_RIGHT)...${NC}`);
        console.log("   Отправка: TRACKPAD KEYCODE_DPAD_RIGHT");
        client.write("TRACKPAD KEYCODE_DPAD_RIGHT\n");
        await sleep(2000);

        console.log(`\n${BLUE}👉 ШАГ 3: Перемещение фокуса вниз (TRACKPAD KEYCODE_DPAD_DOWN)...${NC}`);
        console.log("   Отправка: TRACKPAD KEYCODE_DPAD_DOWN");
        client.write("TRACKPAD KEYCODE_DPAD_DOWN\n");
        await sleep(2000);

        console.log(`\n${BLUE}👉 ШАГ 4: Открытие глобального поиска на ТВ...${NC}`);
        console.log("   Отправка: KEY KEYCODE_SEARCH");
        client.write("KEY KEYCODE_SEARCH\n");
        await sleep(2500);

        const textToInject = "Pano KVM";
        console.log(`\n${BLUE}👉 ШАГ 5: Эмуляция ввода текста в строку поиска ("${textToInject}")...${NC}`);
        const base64Text = Buffer.from(textToInject).toString('base64');
        console.log(`   Отправка: SET_TEXT ${base64Text}`);
        client.write(`SET_TEXT ${base64Text}\n`);
        await sleep(3000);

        console.log(`\n${BLUE}👉 ШАГ 6: Нажатие кнопки Подтверждения (KEYCODE_ENTER)...${NC}`);
        console.log("   Отправка: KEY KEYCODE_ENTER");
        client.write("KEY KEYCODE_ENTER\n");
        await sleep(2000);

        console.log(`\n${GREEN}==========================================================`);
        console.log(" 🎉 СЦЕНАРИЙ ИНТЕГРАЦИОННОГО ТЕСТА ЗАВЕРШЕН!");
        console.log(" Если ваш телевизор отреагировал на все шаги —");
        console.log(" KVM-мост Pano работает на 100% корректно в реальности!");
        console.log(`==========================================================${NC}\n`);
        
        client.destroy();
        process.exit(0);

    } catch (e) {
        console.error(`${RED}❌ Ошибка во время выполнения сценария: ${e.message}${NC}`);
        client.destroy();
        process.exit(1);
    }
}
