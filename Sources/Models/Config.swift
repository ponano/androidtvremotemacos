import Cocoa
import Foundation
import AppKit
import Network
import ServiceManagement
import Speech
import AVFoundation
import Darwin

// ==========================================
// Ширина триггерной зоны захвата на краю экрана (окно больше не расширяется, исключая пересечение полей)
struct Config {
    static let INITIAL_ZONE_WIDTH = 8.0
}
// ==========================================

// Класс динамической локализации на 6 языков (автоматическое определение при запуске)
