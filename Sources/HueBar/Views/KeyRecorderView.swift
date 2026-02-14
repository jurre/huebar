import AppKit
import SwiftUI

struct KeyRecorderView: NSViewRepresentable {
    var keyCode: UInt32?
    var modifierFlags: UInt32?
    var onRecorded: (UInt32, UInt32) -> Void

    func makeNSView(context: Context) -> KeyRecorderNSView {
        let view = KeyRecorderNSView()
        view.onRecorded = onRecorded
        view.currentKeyCode = keyCode
        view.currentModifierFlags = modifierFlags
        return view
    }

    func updateNSView(_ nsView: KeyRecorderNSView, context: Context) {
        nsView.onRecorded = onRecorded
        nsView.currentKeyCode = keyCode
        nsView.currentModifierFlags = modifierFlags
        nsView.needsDisplay = true
    }
}

final class KeyRecorderNSView: NSView {
    var onRecorded: ((UInt32, UInt32) -> Void)?
    var currentKeyCode: UInt32?
    var currentModifierFlags: UInt32?
    private var isRecording = false
    private var monitor: Any?

    override var acceptsFirstResponder: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 140, height: 24)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)

        if isRecording {
            NSColor.controlAccentColor.withAlphaComponent(0.15).setFill()
        } else {
            NSColor.controlBackgroundColor.setFill()
        }
        path.fill()

        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = 1
        path.stroke()

        let text: String
        if isRecording {
            text = "Press shortcut…"
        } else if let keyCode = currentKeyCode, let mods = currentModifierFlags {
            let binding = HotkeyBinding(
                targetType: .room, targetId: "", targetName: "",
                keyCode: keyCode, modifierFlags: mods
            )
            text = binding.displayString
        } else {
            text = "Click to record"
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: isRecording ? NSColor.controlAccentColor : NSColor.labelColor,
        ]
        let attrString = NSAttributedString(string: text, attributes: attrs)
        let size = attrString.size()
        let point = NSPoint(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2
        )
        attrString.draw(at: point)
    }

    override func mouseDown(with event: NSEvent) {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func recordKeyEvent(_ event: NSEvent) {
        guard isRecording else { return }
        let keyCode = UInt32(event.keyCode)
        let mods = HotkeyBinding.carbonModifiers(from: event.modifierFlags)
        // Escape cancels recording
        if keyCode == 0x35 && mods == 0 {
            stopRecording()
            return
        }
        currentKeyCode = keyCode
        currentModifierFlags = mods
        onRecorded?(keyCode, mods)
        stopRecording()
    }

    override func keyDown(with event: NSEvent) {
        recordKeyEvent(event)
    }

    private func startRecording() {
        isRecording = true
        window?.makeFirstResponder(self)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isRecording else { return event }
            self.recordKeyEvent(event)
            return nil
        }
        needsDisplay = true
    }

    private func stopRecording() {
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        needsDisplay = true
    }
}
