import Cocoa
import Foundation
import AppKit
import Network
import ServiceManagement
import Speech
import AVFoundation
import Darwin

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
        
        // Unconditionally stop engine and remove old taps before starting to ensure clean state
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        
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
        
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeId))
        speechRecognizer = recognizer
        
        guard let recognizer = recognizer, recognizer.isAvailable else {
            onError?("Распознавание речи недоступно для языка \(localeId) или Siri отключена.")
            return
        }
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // Safely check format parameters before installTap to avoid crashes
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            onError?("Ошибка формата аудиовхода: неподходящее устройство или частота дискретизации.")
            return
        }
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            onError?(Localization.get("err_recognition_request_failed"))
            return
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer: AVAudioPCMBuffer, when: AVAudioTime) in
            self.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
            isRecording = true
            onStateChange?(true)
            
            recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
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
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        recognitionTask?.cancel()
        recognitionTask = nil
        
        if isRecording {
            isRecording = false
            onStateChange?(false)
        }
    }
}

// Премиальная круглая кнопка с эффектом красного неонового свечения при записи
