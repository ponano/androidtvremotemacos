import Cocoa
import Foundation
import AppKit
import Network
import ServiceManagement
import Speech
import AVFoundation
import Darwin

class TextInputWindow: NSWindow {
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return true }
    
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == 53 { // Escape
            if let delegate = NSApp.delegate as? AppDelegate {
                delegate.dismissInputWindow(cancelled: true)
                return true
            }
        }
        if event.keyCode == 36 || event.keyCode == 76 { // Enter
            if let delegate = NSApp.delegate as? AppDelegate {
                delegate.submitText()
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

