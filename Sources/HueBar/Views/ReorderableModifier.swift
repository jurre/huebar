import AppKit
import os
import SwiftUI

private let logger = Logger(subsystem: "com.huebar", category: "DragReorder")

// MARK: - Reorder Manager

/// Shared registry of all reorderable views, enabling cross-view communication
/// during mouse-tracked reorder operations. This bypasses AppKit's drag-and-drop
/// infrastructure entirely, which doesn't work in MenuBarExtra panels.
@MainActor
final class ReorderManager {
    static let shared = ReorderManager()
    private var views: [String: WeakViewRef] = [:]
    var activeDragSourceId: String?

    private struct WeakViewRef {
        weak var view: DragReorderNSView?
    }

    func register(_ view: DragReorderNSView, id: String) {
        views[id] = WeakViewRef(view: view)
    }

    func unregister(id: String) {
        views.removeValue(forKey: id)
    }

    /// Find the reorderable view whose frame contains the given window-coordinate point.
    func viewAt(windowPoint: NSPoint, excluding: String) -> DragReorderNSView? {
        for (id, ref) in views {
            guard id != excluding, let view = ref.view, view.window != nil else { continue }
            let localPoint = view.convert(windowPoint, from: nil)
            if view.bounds.contains(localPoint) {
                return view
            }
        }
        return nil
    }

    func clearHighlights() {
        for (_, ref) in views {
            ref.view?.setHighlighted(false)
            ref.view?.setDragSource(false)
        }
    }
}

// MARK: - Reorderable NSView

/// NSView overlay that implements custom mouse-tracked reordering.
///
/// Instead of using AppKit's NSDraggingSource/NSDraggingDestination (which don't work
/// in MenuBarExtra panels), this tracks mouse events directly:
/// - Vertical drag → enter reorder mode, highlight target row, reorder on mouseUp
/// - Horizontal drag → forward to SwiftUI (slider interaction)
/// - Click → forward to SwiftUI (buttons, toggles, navigation)
/// - Right-click → forward to SwiftUI (context menus)
/// - Scroll → forward to SwiftUI (ScrollView)
@MainActor
final class DragReorderNSView: NSView {
    var itemId: String = ""
    var onDrop: ((String) -> Void)?

    private var mouseDownEvent: NSEvent?
    private var isReordering = false
    private var isForwardingEvents = false
    private var isHighlighted = false
    private var isDragSource = false
    private var currentTargetId: String?
    private let dragThreshold: CGFloat = 8

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            ReorderManager.shared.register(self, id: itemId)
            logger.info("[\(self.itemId, privacy: .public)] registered, frame=\(self.frame.debugDescription, privacy: .public)")
        }
    }

    override func removeFromSuperview() {
        ReorderManager.shared.unregister(id: itemId)
        super.removeFromSuperview()
    }

    func setHighlighted(_ highlighted: Bool) {
        guard isHighlighted != highlighted else { return }
        isHighlighted = highlighted
        needsDisplay = true
    }

    func setDragSource(_ active: Bool) {
        guard isDragSource != active else { return }
        isDragSource = active
        // Dim the source row to show what's being dragged
        superview?.alphaValue = active ? 0.4 : 1.0
    }

    // MARK: - Mouse Event Handling

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        isReordering = false
        isForwardingEvents = false
        currentTargetId = nil
    }

    override func mouseDragged(with event: NSEvent) {
        if isForwardingEvents {
            forwardEvent(event)
            return
        }

        if isReordering {
            updateReorderTarget(event)
            return
        }

        guard let startEvent = mouseDownEvent else { return }

        let start = startEvent.locationInWindow
        let current = event.locationInWindow
        let dx = current.x - start.x
        let dy = current.y - start.y
        let distance = sqrt(dx * dx + dy * dy)

        guard distance > dragThreshold else { return }

        if abs(dy) >= abs(dx) {
            // Vertical drag → reorder mode
            isReordering = true
            logger.info("[\(self.itemId, privacy: .public)] entering reorder mode")
            setDragSource(true)
            NSCursor.closedHand.push()
            updateReorderTarget(event)
        } else {
            // Horizontal drag → slider/content interaction
            isForwardingEvents = true
            if let md = mouseDownEvent {
                forwardEvent(md)
            }
            forwardEvent(event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer { resetState() }

        if isReordering {
            NSCursor.pop()
            setDragSource(false)
            ReorderManager.shared.clearHighlights()
            if let targetId = currentTargetId {
                logger.info("[\(self.itemId, privacy: .public)] reorder drop → \(targetId, privacy: .public)")
                onDrop?(targetId)
            }
        } else if isForwardingEvents {
            forwardEvent(event)
        } else if let md = mouseDownEvent {
            // Simple click — forward both events
            forwardEvent(md)
            forwardEvent(event)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        forwardEvent(event)
    }

    override func rightMouseUp(with event: NSEvent) {
        forwardEvent(event)
    }

    override func scrollWheel(with event: NSEvent) {
        forwardEvent(event)
    }

    // MARK: - Reorder Tracking

    private func updateReorderTarget(_ event: NSEvent) {
        let manager = ReorderManager.shared

        if let targetView = manager.viewAt(windowPoint: event.locationInWindow, excluding: itemId) {
            if currentTargetId != targetView.itemId {
                // New target — update highlights
                manager.clearHighlights()
                targetView.setHighlighted(true)
                currentTargetId = targetView.itemId
            }
        } else {
            // No target under cursor
            manager.clearHighlights()
            currentTargetId = nil
        }
    }

    // MARK: - Event Forwarding

    /// Static guard to prevent infinite recursion when forwarding events.
    /// Without this, window.sendEvent can dispatch back to another DragReorderNSView,
    /// which forwards again, causing a stack overflow.
    private static var isForwardingEvent = false

    /// Forward an event to the SwiftUI content by temporarily hiding this overlay.
    private func forwardEvent(_ event: NSEvent) {
        guard !Self.isForwardingEvent else { return }
        Self.isForwardingEvent = true
        isHidden = true
        window?.sendEvent(event)
        isHidden = false
        Self.isForwardingEvent = false
    }

    private func resetState() {
        mouseDownEvent = nil
        isReordering = false
        isForwardingEvents = false
        currentTargetId = nil
    }

    // MARK: - Drawing

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
    /// Makes a row reorderable via custom mouse-tracked drag-and-drop.
    ///
    /// This bypasses AppKit's NSDraggingSource/NSDraggingDestination entirely
    /// (which don't work in MenuBarExtra panels) and instead uses direct mouse
    /// event tracking with a shared view registry for cross-row communication.
    func reorderable(id: String, onMove: @escaping (String, String) -> Void) -> some View {
        self.overlay(
            DragReorderRepresentable(itemId: id, onDrop: { draggedId in
                onMove(draggedId, id)
            })
        )
    }
}
