import Cocoa
import Foundation
import AppKit
import Network
import ServiceManagement
import Speech
import AVFoundation
import Darwin

class FocusTextField: NSTextField {
    var onFocusChange: ((Bool) -> Void)?
    
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            onFocusChange?(true)
        }
        return result
    }
    
    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result {
            onFocusChange?(false)
        }
        return result
    }
}

