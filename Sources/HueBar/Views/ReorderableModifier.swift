import AppKit
import SwiftUI

// MARK: - AppKit Drop Target

/// NSView that registers for drag types at the AppKit level,
/// working around SwiftUI's broken drop handling in MenuBarExtra panels.
/// The panel's NSPanel doesn't register for dragged types, but individual
/// NSViews can register themselves and receive drag destination events.
@MainActor
final class DropTargetNSView: NSView {
    var itemId: String = ""
    var onDrop: ((String) -> Void)?
    private var isTargeted = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.string])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Allow normal mouse events (clicks, toggles, sliders) to pass through
    // to the SwiftUI content beneath this overlay. Drag destination events
    // use a separate dispatch path and are NOT affected by hitTest.
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard readDraggedId(from: sender) != nil else { return [] }
        isTargeted = true
        needsDisplay = true
        return .move
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard readDraggedId(from: sender) != nil else { return [] }
        return .move
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        isTargeted = false
        needsDisplay = true
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        defer {
            isTargeted = false
            needsDisplay = true
        }
        guard let draggedId = readDraggedId(from: sender) else { return false }
        onDrop?(draggedId)
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isTargeted else { return }
        // Draw a rounded highlight matching the card's corner radius and horizontal padding
        NSColor.controlAccentColor.withAlphaComponent(0.25).setFill()
        let cardRect = bounds.insetBy(dx: 16, dy: 0)
        let path = NSBezierPath(roundedRect: cardRect, xRadius: 14, yRadius: 14)
        path.fill()
        NSColor.controlAccentColor.setStroke()
        path.lineWidth = 2
        path.stroke()
    }

    private func readDraggedId(from sender: any NSDraggingInfo) -> String? {
        let pb = sender.draggingPasteboard
        guard let objects = pb.readObjects(forClasses: [NSString.self]),
              let draggedId = objects.first as? String,
              draggedId != itemId else {
            return nil
        }
        return draggedId
    }
}

// MARK: - NSViewRepresentable Bridge

struct DropTargetRepresentable: NSViewRepresentable {
    let itemId: String
    let onDrop: (String) -> Void

    func makeNSView(context: Context) -> DropTargetNSView {
        let view = DropTargetNSView()
        view.itemId = itemId
        view.onDrop = onDrop
        return view
    }

    func updateNSView(_ nsView: DropTargetNSView, context: Context) {
        nsView.itemId = itemId
        nsView.onDrop = onDrop
    }
}

// MARK: - View Modifier

extension View {
    /// Makes a row reorderable via drag-and-drop using AppKit's drag destination API.
    /// SwiftUI's built-in `.onDrop`/`.dropDestination` don't work in MenuBarExtra panels
    /// because the NSPanel doesn't register for dragged types. This modifier uses an
    /// AppKit NSView overlay that registers itself directly, bypassing the limitation.
    func reorderable(id: String, onMove: @escaping (String, String) -> Void) -> some View {
        self
            .onDrag { NSItemProvider(object: id as NSString) }
            .overlay(
                DropTargetRepresentable(itemId: id, onDrop: { draggedId in
                    onMove(draggedId, id)
                })
            )
    }
}
