import AppKit
import SwiftUI
import Testing
@testable import HueBar

@Suite("Panel layout", .serialized)
@MainActor
struct PanelLayoutTests {
    @Test func navigationOverlapsOutgoingAndIncomingScreens() {
        let host = NSHostingView(rootView:
            MenuPanel(maxHeight: 550) {
                Color.clear.frame(height: 300)
                Color.clear.frame(height: 550)
            }
        )

        #expect(abs(host.fittingSize.height - 550) < 1)
    }

    @Test func navigationKeepsShortListsContentSized() {
        let host = NSHostingView(rootView:
            MenuPanel(maxHeight: 550) {
                Color.clear.frame(height: 100)
            }
        )

        #expect(abs(host.fittingSize.height - 100) < 1)
    }

    @Test func longListKeepsScrollableViewportInsideCap() throws {
        var geometry: ScrollGeometry?
        let host = NSHostingView(rootView:
            FittingScrollView(maxHeight: 550) {
                Color.clear.frame(height: 900)
            }
            .defaultScrollAnchor(.bottom)
            .onScrollGeometryChange(for: ScrollGeometry.self) { $0 } action: { _, value in
                geometry = value
            }
            .frame(width: 300)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 550),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        let metrics = try #require(geometry)
        #expect(abs(metrics.containerSize.height - 550) < 1)
        #expect(abs(metrics.contentSize.height - 900) < 1)
        #expect(abs(metrics.contentOffset.y - 350) < 1)
    }

    @Test(arguments: [CGFloat(0), 1, 100, 506, 550, 900])
    func scrollFitsContentOnFirstLayout(contentHeight: CGFloat) {
        let host = NSHostingView(rootView:
            FittingScrollView(maxHeight: 550) {
                Color.clear.frame(height: contentHeight)
            }
            .frame(width: 300)
        )

        #expect(abs(host.fittingSize.height - min(contentHeight, 550)) < 1)
    }

    @Test(arguments: [CGFloat(0), 1, 100, 500, 900])
    func headerAndListSharePanelCap(contentHeight: CGFloat) {
        let host = NSHostingView(rootView:
            VStack(spacing: 0) {
                Color.clear.frame(height: 50)
                FittingScrollView(maxHeight: 500) {
                    Color.clear.frame(height: contentHeight)
                }
            }
            .frame(width: 300)
            .frame(maxHeight: 550)
            .fixedSize(horizontal: false, vertical: true)
        )

        #expect(abs(host.fittingSize.height - min(contentHeight + 50, 550)) < 1)
    }
}
