import SwiftUI
import AppKit

/// Onboarding runs in a borderless-feeling, fixed 720×560 window; the
/// main app restores normal resizable chrome (minimums). One window, two
/// dress codes.
public struct WindowChrome: NSViewRepresentable {
    let onboarding: Bool

    public init(onboarding: Bool) {
        self.onboarding = onboarding
    }

    public func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { apply(to: view.window) }
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { apply(to: nsView.window) }
    }

    private func apply(to window: NSWindow?) {
        guard let window else { return }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        if onboarding {
            if window.styleMask.contains(.resizable) {
                window.styleMask.remove(.resizable)
                window.setContentSize(NSSize(width: 720, height: 560))
                window.center()
            }
            window.standardWindowButton(.zoomButton)?.isEnabled = false
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        } else {
            if !window.styleMask.contains(.resizable) {
                window.styleMask.insert(.resizable)
                window.setContentSize(NSSize(width: 1080, height: 720))
                window.center()
            }
            window.standardWindowButton(.zoomButton)?.isEnabled = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        }
    }
}
