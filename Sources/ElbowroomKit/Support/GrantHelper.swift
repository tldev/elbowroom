import AppKit
import SwiftUI

/// B3: while the user is in System Settings turning on Full Disk Access,
/// a small floating card docks beside the Settings window and offers the app
/// itself as a drag source, so adding Elbowroom to the list is one drag instead
/// of a hunt through a file picker. It follows the Settings window and
/// vanishes when Settings does. Pattern after jaywcjlove/PermissionFlow,
/// built in-house to stay dependency-free.
@MainActor
public final class GrantHelperPanel {
    public static let shared = GrantHelperPanel()
    private var panel: NSPanel?
    private var tracker: Timer?
    private var showTask: Task<Void, Never>?

    private init() {}

    /// Delay lets System Settings open and take its frame first.
    public func show(after delay: TimeInterval = 0.9) {
        showTask?.cancel()
        showTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.reveal()
        }
    }

    public func hide() {
        showTask?.cancel()
        showTask = nil
        tracker?.invalidate()
        tracker = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func reveal() {
        guard panel == nil else { return }
        let host = NSHostingView(rootView: GrantHelperCard())
        host.frame = NSRect(x: 0, y: 0, width: 252, height: 168)
        let p = NSPanel(
            contentRect: host.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        p.isFloatingPanel = true
        p.level = .floating
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = host
        panel = p
        position()
        p.orderFrontRegardless()
        tracker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            Task { @MainActor in GrantHelperPanel.shared.position() }
        }
    }

    /// Dock at the Settings window's trailing edge; on a tight screen, its
    /// leading edge. Keep the last spot while the window is momentarily
    /// unfindable; leave when Settings quits.
    private func position() {
        guard let panel else { return }
        guard settingsIsRunning else { hide(); return }
        guard let frame = settingsWindowFrame() else { return }
        let screen = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
        var x = frame.maxX + 14
        if x + panel.frame.width > screen.maxX {
            x = frame.minX - panel.frame.width - 14
        }
        let y = frame.midY - panel.frame.height / 2
        panel.setFrameOrigin(NSPoint(x: max(screen.minX, x), y: min(max(screen.minY, y), screen.maxY - panel.frame.height)))
    }

    private var settingsIsRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").isEmpty
    }

    /// Window Server frame lookup: frames need no permission (titles would).
    private func settingsWindowFrame() -> NSRect? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        let frames: [CGRect] = list.compactMap { info in
            guard (info[kCGWindowOwnerPID as String] as? Int) == Int(app.processIdentifier),
                  (info[kCGWindowLayer as String] as? Int ?? 1) == 0,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: dict)
            else { return nil }
            return rect
        }
        guard let cg = frames.max(by: { $0.width * $0.height < $1.width * $1.height }) else { return nil }
        // CG coordinates hang from the primary screen's top-left, y down;
        // AppKit's rise from its bottom-left, y up.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(x: cg.minX, y: primaryHeight - cg.maxY, width: cg.width, height: cg.height)
    }
}

private struct GrantHelperCard: View {
    var body: some View {
        VStack(spacing: BSpace.m) {
            DraggableAppIcon()
                .frame(width: 72, height: 72)
            Text(Copy.b3DragHint)
                .font(BFont.meta)
                .foregroundStyle(BColor.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(BSpace.l)
        .frame(width: 252, height: 168)
        .background(BColor.surface, in: RoundedRectangle(cornerRadius: BRadius.card))
        .overlay(RoundedRectangle(cornerRadius: BRadius.card).strokeBorder(BColor.line, lineWidth: 1))
    }
}

private struct DraggableAppIcon: NSViewRepresentable {
    func makeNSView(context: Context) -> AppIconDragView { AppIconDragView() }
    func updateNSView(_ view: AppIconDragView, context: Context) {}
}

/// A real drag source vending the app bundle's file URL, exactly what the
/// Full Disk Access list accepts on drop.
final class AppIconDragView: NSImageView, NSDraggingSource {
    init() {
        super.init(frame: .zero)
        image = NSApp.applicationIconImage
        imageScaling = .scaleProportionallyUpOrDown
        unregisterDraggedTypes()
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    override func mouseDragged(with event: NSEvent) {
        let item = NSDraggingItem(pasteboardWriter: Bundle.main.bundleURL as NSURL)
        item.setDraggingFrame(bounds, contents: NSApp.applicationIconImage)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }
}
