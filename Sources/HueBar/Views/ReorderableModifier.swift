import AppKit
import os
import SwiftUI

private let logger = Logger(subsystem: "com.huebar", category: "DragReorder")

// MARK: - Full AppKit Drag-and-Drop View

/// NSView overlay that handles BOTH drag source and destination entirely in AppKit,
/// bypassing SwiftUI's broken drag-drop in MenuBarExtra panels.
///
/// **Why full AppKit?** The NSPanel used by MenuBarExtra doesn't register for dragged
/// types. SwiftUI's `.onDrop` and `.dropDestination` rely on the panel's registration
/// and silently fail. This view calls `registerForDraggedTypes` directly and also
/// handles drag initiation via `beginDraggingSession`, keeping everything in AppKit.
///
/// **Event forwarding:** Since this view sits on top of SwiftUI content, it intercepts
/// all mouse events. Normal clicks and horizontal drags (sliders) are forwarded to
/// the SwiftUI content beneath by temporarily hiding the overlay.
@MainActor
final class DragReorderNSView: NSView, NSDraggingSource {
    var itemId: String = ""
    var onDrop: ((String) -> Void)?

    private var mouseDownEvent: NSEvent?
    private var isDragging = false
    private var isForwardingEvents = false
    private var isHighlighted = false
    private let dragThreshold: CGFloat = 5

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.string])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            // Re-register to ensure the window knows about our drag types
            registerForDraggedTypes([.string])
            logger.debug("[\(self.itemId)] attached to window: \(String(describing: window.className))")
        }
    }

    // MARK: - Mouse Event Handling

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        isDragging = false
        isForwardingEvents = false
    }

    override func mouseDragged(with event: NSEvent) {
        if isForwardingEvents {
            // Already in forwarding mode (slider interaction) — keep forwarding
            forwardEvent(event)
            return
        }

        if isDragging { return }

        guard let startEvent = mouseDownEvent else { return }

        let start = startEvent.locationInWindow
        let current = event.locationInWindow
        let dx = current.x - start.x
        let dy = current.y - start.y
        let distance = sqrt(dx * dx + dy * dy)

        guard distance > dragThreshold else { return }

        // Heuristic: vertical drag = reorder, horizontal drag = slider/content
        if abs(dy) >= abs(dx) {
            isDragging = true
            startDragSession(event: startEvent)
        } else {
            // Horizontal — forward to SwiftUI (slider, etc.)
            isForwardingEvents = true
            if let md = mouseDownEvent {
                forwardEvent(md)
            }
            forwardEvent(event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer { resetMouseState() }

        if isForwardingEvents {
            forwardEvent(event)
        } else if !isDragging, let md = mouseDownEvent {
            // Simple click — forward mouseDown + mouseUp pair
            forwardEvent(md)
            forwardEvent(event)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        // Forward right-click for context menus
        forwardEvent(event)
    }

    override func rightMouseUp(with event: NSEvent) {
        forwardEvent(event)
    }

    override func scrollWheel(with event: NSEvent) {
        // Forward scroll events to the ScrollView beneath
        forwardEvent(event)
    }

    /// Forward an event to the SwiftUI content by temporarily hiding this overlay
    /// so that the window's hitTest finds the view beneath us.
    private func forwardEvent(_ event: NSEvent) {
        isHidden = true
        window?.sendEvent(event)
        isHidden = false
    }

    private func resetMouseState() {
        mouseDownEvent = nil
        isDragging = false
        isForwardingEvents = false
    }

    // MARK: - Drag Source

    private func startDragSession(event: NSEvent) {
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(itemId, forType: .string)

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        draggingItem.setDraggingFrame(bounds, contents: dragSnapshot())

        logger.info("[\(self.itemId)] starting drag session")
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    // SAFETY: Called on the main thread during drag sessions. Only returns
    // a constant value so no synchronization is needed.
    nonisolated func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }

    nonisolated func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        MainActor.assumeIsolated {
            logger.info("[\(self.itemId)] drag session ended, operation=\(String(describing: operation))")
            resetMouseState()
        }
    }

    private func dragSnapshot() -> NSImage {
        let size = bounds.size
        guard size.width > 0, size.height > 0 else {
            return NSImage(size: NSSize(width: 100, height: 40))
        }
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.controlAccentColor.withAlphaComponent(0.15).setFill()
        let rect = bounds.insetBy(dx: 16, dy: 0)
        NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14).fill()
        image.unlockFocus()
        return image
    }

    // MARK: - Drag Destination (NSDraggingDestination)

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let types = sender.draggingPasteboard.types?.map(\.rawValue) ?? []
        logger.info("[\(self.itemId)] draggingEntered, pasteboard types: \(types)")

        guard let draggedId = readDraggedId(from: sender) else {
            logger.debug("[\(self.itemId)] draggingEntered: no valid ID on pasteboard")
            return []
        }
        logger.info("[\(self.itemId)] draggingEntered from '\(draggedId)' — accepting .move")
        isHighlighted = true
        needsDisplay = true
        return .move
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard readDraggedId(from: sender) != nil else { return [] }
        return .move
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        logger.debug("[\(self.itemId)] draggingExited")
        isHighlighted = false
        needsDisplay = true
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        defer {
            isHighlighted = false
            needsDisplay = true
        }
        guard let draggedId = readDraggedId(from: sender) else {
            logger.error("[\(self.itemId)] performDragOperation: failed to read dragged ID")
            return false
        }
        logger.info("[\(self.itemId)] performDragOperation: moving '\(draggedId)' → '\(self.itemId)'")
        onDrop?(draggedId)
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isHighlighted else { return }
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
        // Try direct string read
        if let str = pb.string(forType: .string), str != itemId {
            return str
        }
        // Fallback: readObjects (handles NSItemProvider-based drags)
        if let objects = pb.readObjects(forClasses: [NSString.self]),
           let str = objects.first as? String, str != itemId {
            return str
        }
        return nil
    }
}

// MARK: - NSViewRepresentable Bridge

struct DragReorderRepresentable: NSViewRepresentable {
    let itemId: String
    let onDrop: (String) -> Void

    func makeNSView(context: Context) -> DragReorderNSView {
        let view = DragReorderNSView()
        view.itemId = itemId
        view.onDrop = onDrop
        return view
    }

    func updateNSView(_ nsView: DragReorderNSView, context: Context) {
        nsView.itemId = itemId
        nsView.onDrop = onDrop
    }
}

// MARK: - View Modifier

extension View {
    /// Makes a row reorderable via AppKit drag-and-drop.
    ///
    /// Handles both drag source (`beginDraggingSession`) and destination
    /// (`registerForDraggedTypes`) entirely in AppKit, bypassing SwiftUI's
    /// broken drop handling in MenuBarExtra panels. Normal clicks, slider
    /// drags, and scroll events are forwarded to the SwiftUI content beneath.
    func reorderable(id: String, onMove: @escaping (String, String) -> Void) -> some View {
        self.overlay(
            DragReorderRepresentable(itemId: id, onDrop: { draggedId in
                onMove(draggedId, id)
            })
        )
    }
}
