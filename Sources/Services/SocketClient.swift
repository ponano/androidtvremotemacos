import Cocoa
import Foundation
import AppKit
import Network
import ServiceManagement
import Speech
import AVFoundation
import Darwin

class SocketClient {
    var connection: NWConnection?
    var queue = DispatchQueue(label: "KVM_SocketQueue")
    var onStatusChange: ((String) -> Void)?
    var onImeShow: ((String) -> Void)?
    var onImeUpdate: ((String) -> Void)?
    var onImeHide: (() -> Void)?
    var onAppChange: ((String) -> Void)?
    private var isReconnecting = false
    
    func connect() {
        queue.async { [weak self] in
            self?._connect()
        }
    }
    
    private func _connect() {
        // Очищаем старое подключение если есть
        if let old = connection {
            old.stateUpdateHandler = nil
            old.cancel()
            connection = nil
        }
        
        print("[Swift Socket] connect() called, starting NWConnection to 127.0.0.1:12345...")
        let host = NWEndpoint.Host("127.0.0.1")
        let port = NWEndpoint.Port(integerLiteral: 12345)
        
        let newConnection = NWConnection(host: host, port: port, using: .tcp)
        connection = newConnection
        isReconnecting = false
        
        newConnection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("[Swift Socket] Connected to local TV KVM bridge.")
                self?.receive()
            case .failed(let error):
                print("[Swift Socket] Connection failed: \(error). Reconnecting...")
                self?.scheduleReconnect()
            case .waiting(let error):
                print("[Swift Socket] Connection waiting: \(error). Retrying in 1 second...")
                self?.scheduleReconnect()
            case .cancelled:
                print("[Swift Socket] Connection cancelled.")
            default:
                break
            }
        }
        newConnection.start(queue: queue)
    }
    
    func disconnect() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.isReconnecting = false
            if let conn = self.connection {
                conn.stateUpdateHandler = nil
                conn.cancel()
                self.connection = nil
            }
        }
    }
    
    private func scheduleReconnect() {
        guard !isReconnecting else { return }
        isReconnecting = true
        
        // Safety check: dispatch timer on Main thread, then safely cancel & connect on queue
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            self.queue.async {
                if let conn = self.connection {
                    conn.stateUpdateHandler = nil
                    conn.cancel()
                    self.connection = nil
                }
                self._connect()
            }
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


