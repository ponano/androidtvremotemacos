import Cocoa
import Foundation

// Перечисление уровней логирования
public enum LogLevel: String {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}

public class Logger {
    public static let shared = Logger()
    
    private let fileQueue = DispatchQueue(label: "com.pano.logger.serial")
    private var fileHandle: FileHandle?
    private let logPath: String
    
    private init() {
        let homeDir = NSHomeDirectory()
        let logsDir = homeDir + "/Library/Logs/tv_kvm"
        self.logPath = logsDir + "/swift.log"
        
        do {
            // Создаем папку для логов, если она не существует
            if !FileManager.default.fileExists(atPath: logsDir) {
                try FileManager.default.createDirectory(atPath: logsDir, withIntermediateDirectories: true, attributes: nil)
            }
            
            // Создаем файл лога, если его нет
            if !FileManager.default.fileExists(atPath: logPath) {
                FileManager.default.createFile(atPath: logPath, contents: nil, attributes: nil)
            }
            
            // Открываем FileHandle для записи в конец файла
            if let handle = FileHandle(forWritingAtPath: logPath) {
                handle.seekToEndOfFile()
                self.fileHandle = handle
            } else {
                Swift.print("[Logger Error] Failed to open FileHandle for: \(logPath)")
            }
        } catch {
            Swift.print("[Logger Error] Failed to initialize logs directory: \(error.localizedDescription)")
        }
    }
    
    deinit {
        fileHandle?.closeFile()
    }
    
    /// Основная функция логирования
    public func log(_ level: LogLevel, _ message: String, component: String = "Swift") {
        let timestamp = getTimestamp()
        let formatted = "[\(timestamp)] [\(level.rawValue)] [\(component)] \(message)\n"
        
        // Дублируем вывод в консоль, чтобы интеграционные тесты продолжали видеть stdout
        Swift.print(formatted, terminator: "")
        
        // Записываем асинхронно в файл лога через сериализованную очередь
        fileQueue.async { [weak self] in
            guard let self = self, let handle = self.fileHandle else { return }
            if let data = formatted.data(using: .utf8) {
                handle.write(data)
                // Синхронизируем запись на диск, чтобы логи не потерялись при сбое
                handle.synchronizeFile()
            }
        }
    }
    
    private func getTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }
}

// === Удобные глобальные обертки для логирования ===
public func logDebug(_ msg: String, component: String = "Swift") {
    Logger.shared.log(.debug, msg, component: component)
}

public func logInfo(_ msg: String, component: String = "Swift") {
    Logger.shared.log(.info, msg, component: component)
}

public func logWarning(_ msg: String, component: String = "Swift") {
    Logger.shared.log(.warning, msg, component: component)
}

public func logError(_ msg: String, component: String = "Swift") {
    Logger.shared.log(.error, msg, component: component)
}

// === Переопределение глобальной функции print для Swift ===
// Позволяет автоматически перехватывать все стандартные вызовы print во всем приложении Pano
public func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    let message = items.map { "\($0)" }.joined(separator: separator)
    
    // Эвристическое определение уровня лога на базе содержимого сообщения
    let level: LogLevel
    let lowerMsg = message.lowercased()
    
    if lowerMsg.contains("error") || lowerMsg.contains("fail") || lowerMsg.contains("провален") {
        level = .error
    } else if lowerMsg.contains("warning") || lowerMsg.contains("⚠️") || lowerMsg.contains("conflict") || lowerMsg.contains("unreachable") {
        level = .warning
    } else if lowerMsg.contains("touch") || lowerMsg.contains("mousemoved") || lowerMsg.contains("delta") || lowerMsg.contains("accumulated") || lowerMsg.contains("touchesbegan") || lowerMsg.contains("touchesended") {
        level = .debug
    } else {
        level = .info
    }
    
    // Передаем в логгер
    Logger.shared.log(level, message, component: "Swift")
}
