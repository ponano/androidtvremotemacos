import Cocoa
import Foundation
import AppKit
import Network
import ServiceManagement
import Speech
import AVFoundation
import Darwin

class MicButton: NSButton {
    var isRecording = false {
        didSet {
            needsDisplay = true
            if isRecording {
                startPulseAnimation()
            } else {
                stopPulseAnimation()
            }
        }
    }
    
    private var pulseScale: CGFloat = 1.0
    private var pulseTimer: Timer?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
        self.layer?.masksToBounds = false
        self.title = ""
        self.isBordered = false
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func draw(_ dirtyRect: NSRect) {
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) / 2.0 - 4.0
        
        let path = NSBezierPath()
        path.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        
        if isRecording {
            let gradient = NSGradient(starting: NSColor(red: 0.95, green: 0.2, blue: 0.3, alpha: 0.9),
                                      ending: NSColor(red: 0.8, green: 0.05, blue: 0.15, alpha: 0.95))
            gradient?.draw(in: path, angle: 90)
            
            NSGraphicsContext.current?.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor(red: 0.95, green: 0.2, blue: 0.3, alpha: 0.6 * CGFloat(pulseScale))
            shadow.shadowBlurRadius = 8.0 * pulseScale
            shadow.shadowOffset = NSSize(width: 0, height: 0)
            shadow.set()
            
            let ringPath = NSBezierPath()
            let ringRadius = radius + 3.0 * pulseScale
            ringPath.appendArc(withCenter: center, radius: ringRadius, startAngle: 0, endAngle: 360)
            NSColor(red: 0.95, green: 0.2, blue: 0.3, alpha: 0.8 * (1.5 - pulseScale)).setStroke()
            ringPath.lineWidth = 1.5
            ringPath.stroke()
            
            NSGraphicsContext.current?.restoreGraphicsState()
        } else {
            NSColor(red: 0.15, green: 0.15, blue: 0.2, alpha: 0.6).setFill()
            path.fill()
            
            NSColor(red: 0.35, green: 0.35, blue: 0.45, alpha: 0.4).setStroke()
            path.lineWidth = 1.0
            path.stroke()
        }
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        
        let fontSize: CGFloat = isRecording ? 18.0 : 16.0
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize),
            .paragraphStyle: paragraphStyle,
            .foregroundColor: NSColor.white
        ]
        
        let glyph = "🎙"
        let size = glyph.size(withAttributes: attributes)
        let rect = NSRect(x: center.x - size.width / 2.0, y: center.y - size.height / 2.0 - 1.0, width: size.width, height: size.height)
        glyph.draw(in: rect, withAttributes: attributes)
    }
    
    private func startPulseAnimation() {
        pulseTimer?.invalidate()
        pulseScale = 1.0
        
        var growing = true
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if growing {
                self.pulseScale += 0.05
                if self.pulseScale >= 1.3 {
                    growing = false
                }
            } else {
                self.pulseScale -= 0.05
                if self.pulseScale <= 0.9 {
                    growing = true
                }
            }
            self.needsDisplay = true
        }
    }
    
    private func stopPulseAnimation() {
        pulseTimer?.invalidate()
        pulseTimer = nil
        pulseScale = 1.0
        needsDisplay = true
    }
}

