import Cocoa
import Foundation
import AppKit
import Network
import ServiceManagement
import Speech
import AVFoundation
import Darwin

class StyledTextFieldContainer: NSView {
    var isFocused = false {
        didSet {
            needsDisplay = true
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), xRadius: 8, yRadius: 8)
        
        // Премиальный темный полупрозрачный фон (slate dark translucent)
        NSColor(red: 0.08, green: 0.08, blue: 0.1, alpha: 0.85).setFill()
        path.fill()
        
        if isFocused {
            // Элегантная неоновая бирюзово-синяя рамка фокуса
            NSColor(red: 0.15, green: 0.55, blue: 0.95, alpha: 0.95).setStroke()
            path.lineWidth = 2.0
            
            NSGraphicsContext.current?.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor(red: 0.15, green: 0.55, blue: 0.95, alpha: 0.3)
            shadow.shadowBlurRadius = 6.0
            shadow.shadowOffset = NSSize(width: 0, height: 0)
            shadow.set()
            path.stroke()
            NSGraphicsContext.current?.restoreGraphicsState()
        } else {
            // Мягкая неактивная рамка
            NSColor(red: 0.25, green: 0.25, blue: 0.3, alpha: 0.4).setStroke()
            path.lineWidth = 1.0
            path.stroke()
        }
    }
}

