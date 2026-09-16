import AppKit
import SwiftUI

/// B3: while the user is in System Settings turning on Full Disk Access,
/// a small floating card docks beside the Settings window and offers the app
/// itself as a drag source, so adding Elbowroom to the list is one drag instead
/// of a hunt through a file picker. It follows the Settings window, flips to
/// a green Granted state the moment the switch lands, and vanishes when
/// Settings does. Pattern after jaywcjlove/PermissionFlow, built in-house to
/// stay dependency-free.
@MainActor
public final class GrantHelperPanel {
    public static let shared = GrantHelperPanel()
    private var panel: NSPanel?
    private var tracker: Timer?
    private var showTask: Task<Void, Never>?
    /// Set once System Settings has actually been seen running, so a slow
    /// launch never reads as "Settings quit, take the card away".
    private var sawSettings = false
    private let state = GrantHelperState()

    private init() {}

    /// Delay lets System Settings open and take its frame first.
    /// `onRelaunch`, when given, puts a relaunch button on the card: the
    /// App Management switch applies at launch, and this panel is the only
    /// surface that can offer it without a modal blocking the quit.
    public func show(after delay: TimeInterval = 0.9, onRelaunch: (() -> Void)? = nil) {
        state.onRelaunch = onRelaunch
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
        sawSettings = false
        state.granted = false
        state.onRelaunch = nil
    }

    /// The switch landed: show the green check for a beat, then leave. The
    /// B3 screen carries the flow from here.
    public func markGranted() {
        guard panel != nil, !state.granted else { return }
        state.granted = true
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            self?.hide()
        }
    }

    private func reveal() {
        guard panel == nil else { return }
        let host = NSHostingView(rootView: GrantHelperCard(state: state))
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
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
        // Somewhere sensible first: if Settings is still launching, the card
        // waits mid-screen instead of flashing in the bottom-left corner.
        let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
        p.setFrameOrigin(NSPoint(
            x: visible.maxX - size.width - 40,
            y: visible.midY - size.height / 2
        ))
        position()
        p.orderFrontRegardless()
        tracker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            Task { @MainActor in GrantHelperPanel.shared.position() }
        }
    }

    /// Dock at the Settings window's trailing edge, top-aligned with the
    /// permission list; on a tight screen, its leading edge. Keep the last
    /// spot while the window is momentarily unfindable; leave when Settings
    /// quits.
    private func position() {
        guard let panel else { return }
        // Settings can still be launching when the first tick lands, so
        // absence only means "leave" once it has actually been seen.
        if settingsIsRunning {
            sawSettings = true
        } else {
            if sawSettings { hide() }
            return
        }
        guard let frame = settingsWindowFrame() else { return }
        let screen = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
        var x = frame.maxX + 14
        var settingsIsLeftOfCard = true
        if x + panel.frame.width > screen.maxX {
            x = frame.minX - panel.frame.width - 14
            settingsIsLeftOfCard = false
        }
        // The nudge arrow points at the permission list, wherever the card
        // landed relative to it.
        state.arrowPointsLeft = settingsIsLeftOfCard
        let y = frame.maxY - panel.frame.height - 56
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

@MainActor
public final class GrantHelperState: ObservableObject {
    @Published public var granted = false
    /// Which way the nudge arrow points: toward the Settings window, which
    /// sits left of the card in the normal docking, right on tight screens.
    @Published public var arrowPointsLeft = true
    /// Set for grants macOS applies only at launch, so the card can offer
    /// the relaunch itself.
    @Published public var onRelaunch: (() -> Void)?
    public init() {}
}

/// The card itself: live status up top, the app as a real drag source on a
/// lifted tile, a nudging arrow while waiting, and the one instruction.
public struct GrantHelperCard: View {
    @ObservedObject var state: GrantHelperState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var nudge = false

    public init(state: GrantHelperState) {
        self.state = state
    }

    public var body: some View {
        VStack(spacing: BSpace.m) {
            HStack(spacing: 6) {
                Image(systemName: state.granted ? "checkmark.circle.fill" : "arrow.right.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(state.granted ? BColor.ok : BColor.tierManaged)
                Text(state.granted ? Copy.fdaGranted : Copy.b3WaitTitle)
                    .font(BFont.meta.weight(.medium))
                    .foregroundStyle(BColor.inkSoft)
            }
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(BColor.soil)
                    .frame(width: 96, height: 96)
                DraggableAppIcon()
                    .frame(width: 64, height: 64)
            }
            if !state.granted {
                let direction: CGFloat = state.arrowPointsLeft ? -1 : 1
                Image(systemName: state.arrowPointsLeft ? "arrow.left" : "arrow.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(BColor.brand)
                    .offset(x: (nudge ? 4 : -2) * direction)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                        value: nudge
                    )
                    .onAppear { nudge = true }
                    .accessibilityHidden(true)
            }
            Text(state.granted ? Copy.b3AlreadyOn : Copy.b3DragHint)
                .font(BFont.meta)
                .foregroundStyle(BColor.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let onRelaunch = state.onRelaunch, !state.granted {
                Button(Copy.b3Relaunch) { onRelaunch() }
                    .buttonStyle(SecondarySmallButtonStyle())
                    .accessibilityLabel(Copy.b3Relaunch)
            }
        }
        .padding(BSpace.l)
        .frame(width: 252)
        .background(BColor.surface, in: RoundedRectangle(cornerRadius: BRadius.card))
        .overlay(RoundedRectangle(cornerRadius: BRadius.card).strokeBorder(BColor.line, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(state.granted ? Copy.b3AlreadyOn : Copy.b3DragHint)
    }
}

private struct DraggableAppIcon: NSViewRepresentable {
    func makeNSView(context: Context) -> AppIconDragView { AppIconDragView() }
    func updateNSView(_ view: AppIconDragView, context: Context) {}
}

/// A real drag source vending the app bundle's file URL, exactly what the
/// Full Disk Access list accepts on drop. The fixed intrinsic size keeps the
/// hosting layout honest; without it, NSImageView reports the icon's full
/// 1024 pt and swallows the card.
final class AppIconDragView: NSImageView, NSDraggingSource {
    init() {
        super.init(frame: .zero)
        image = NSApp.applicationIconImage
        imageScaling = .scaleProportionallyUpOrDown
        unregisterDraggedTypes()
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    override var intrinsicContentSize: NSSize { NSSize(width: 64, height: 64) }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDragged(with event: NSEvent) {
        let item = NSDraggingItem(pasteboardWriter: Bundle.main.bundleURL as NSURL)
        item.setDraggingFrame(bounds, contents: NSApp.applicationIconImage)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }
}
