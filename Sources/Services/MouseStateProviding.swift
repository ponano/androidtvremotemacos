import Cocoa
import Foundation
import AppKit
import Network
import ServiceManagement
import Speech
import AVFoundation
import Darwin

protocol MouseStateProviding {
    var pressedMouseButtons: Int { get }
}

class DefaultMouseStateProvider: MouseStateProviding {
    var pressedMouseButtons: Int {
        return NSEvent.pressedMouseButtons
    }
}

