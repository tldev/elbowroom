import AppKit
import SwiftUI

/// The strip legend's own little window: borderless, non-activating, and
/// mouse-transparent, so the card can hang below the strip without being
/// clipped by the window edge or painted over by later siblings (the
/// onboarding dots). Pattern after GrantHelperPanel. Clamps to the screen,
/// not the window; rides as a child window so it follows window moves.
@MainActor
public final class LegendPanel {
    public static let shared = LegendPanel()
    private var panel: NSPanel?
    private var hosting: NSHostingView<AnyView>?

    private init() {}

    /// Show the card, or move and re-render it if already up. `topLeft` is
    /// the card's top-left corner in screen coordinates (AppKit, y up).
    public func show(card: AnyView, topLeft: NSPoint, over window: NSWindow?) {
        let host: NSHostingView<AnyView>
        if let existing = hosting {
            existing.rootView = card
            host = existing
        } else {
            host = NSHostingView(rootView: card)
            hosting = host
        }
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)

        let p: NSPanel
        if let existing = panel {
            p = existing
        } else {
            p = NSPanel(
                contentRect: host.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered, defer: false
            )
            p.isFloatingPanel = true
            p.backgroundColor = .clear
            p.isOpaque = false
            p.hasShadow = true
            // Legend only; it never takes the mouse.
            p.ignoresMouseEvents = true
            // Tooltip rules: no fade, no slide; it is simply there.
            p.animationBehavior = .none
            p.contentView = host
            panel = p
        }
        p.setContentSize(size)

        let bounds = (window?.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let x = min(max(bounds.minX + 8, topLeft.x), bounds.maxX - size.width - 8)
        let y = max(bounds.minY + 8, topLeft.y - size.height)
        p.setFrameOrigin(NSPoint(x: x, y: y))

        if p.parent == nil, let window {
            window.addChildWindow(p, ordered: .above)
        }
        p.orderFront(nil)
    }

    public func hide() {
        if let panel {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
        panel = nil
        hosting = nil
    }
}

/// Hands the hosting NSWindow to SwiftUI code that needs screen coordinates.
struct HostWindowReader: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> WindowProbeView {
        let view = WindowProbeView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ view: WindowProbeView, context: Context) {}

    final class WindowProbeView: NSView {
        var onWindow: ((NSWindow?) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindow?(window)
        }
    }
}
