import SwiftUI
import AppKit
import QuickLook
import QuickLookThumbnailing

// Lens item UX shared by the Items table and the Reclaim plan: the
// thumbnail fan, the loupe panel, and Quick Look. Findings themselves are
// ordinary AtlasItems; only these preview idioms are lens-specific.

/// A hovered fan's report: what it holds, which cover fronts, where it sits.
struct FanZoom {
    let samples: [String]
    let index: Int
    let anchor: Anchor<CGRect>
}

struct FanZoomKey: PreferenceKey {
    static let defaultValue: FanZoom? = nil
    static func reduce(value: inout FanZoom?, nextValue: () -> FanZoom?) {
        if let next = nextValue() { value = next }
    }
}

/// The loupe: a borderless, mouse-transparent child panel floating over
/// the app — a real window, so the grown covers overhang the sheet itself
/// and genuinely pop off the screen. Centered on the hovered fan; display
/// only, the mouse stays with the fan beneath.
struct FanZoomOverlay: ViewModifier {
    /// What the panel needs, comparable so view updates only bridge changes.
    struct Snap: Equatable {
        let samples: [String]
        let index: Int
        let rect: CGRect
    }

    func body(content: Content) -> some View {
        content.backgroundPreferenceValue(FanZoomKey.self) { zoom in
            GeometryReader { geo in
                // The anchor rect stays in this reader's local space, which
                // is exactly the grabber view's bounds; the loupe converts
                // from that view, so no coordinate-space guesswork survives.
                let snap = zoom.map { value in
                    Snap(samples: value.samples, index: value.index, rect: geo[value.anchor])
                }
                ViewGrabber { LoupeWindow.shared.host = $0 }
                    .onChange(of: snap) { _, next in
                        if let next {
                            LoupeWindow.shared.show(next)
                        } else {
                            LoupeWindow.shared.hide()
                        }
                    }
                    .onDisappear { LoupeWindow.shared.hide() }
            }
        }
    }
}

/// Hands the loupe the NSView whose bounds the anchor rects are measured
/// in, so screen conversion starts from ground truth.
private struct ViewGrabber: NSViewRepresentable {
    let onView: (NSView?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in onView(view) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { [weak view] in onView(view) }
    }
}

extension View {
    func fanZoomOverlay() -> some View { modifier(FanZoomOverlay()) }
}

/// The loupe's own window: borderless, transparent, non-activating, ordered
/// as a child of the sheet so it rides along and overhangs its edges.
@MainActor
final class LoupeWindow {
    static let shared = LoupeWindow()
    static let size = NSSize(width: 460, height: 250)

    private let model = LoupeModel()
    private var panel: NSPanel?
    private weak var parent: NSWindow?
    /// The view whose bounds the anchor rects are measured in (ViewGrabber).
    weak var host: NSView?

    func show(_ snap: FanZoomOverlay.Snap) {
        guard let host, let window = host.window else { return }
        let panel = ensurePanel()
        model.samples = snap.samples
        model.index = snap.index

        // snap.rect is top-left in the host view's bounds; flip within those
        // same bounds unless AppKit already flipped them, then out to screen.
        let rect = snap.rect
        let flipped = host.isFlipped ? rect : NSRect(
            x: rect.minX, y: host.bounds.height - rect.maxY,
            width: rect.width, height: rect.height
        )
        let screenRect = window.convertToScreen(host.convert(flipped, to: nil))
        var origin = NSPoint(
            x: screenRect.midX - Self.size.width / 2,
            y: screenRect.midY - Self.size.height / 2
        )
        if let visible = window.screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX), visible.maxX - Self.size.width)
            origin.y = min(max(origin.y, visible.minY), visible.maxY - Self.size.height)
        }
        panel.setFrameOrigin(origin)

        if panel.parent == nil {
            window.addChildWindow(panel, ordered: .above)
            parent = window
            panel.orderFront(nil)
            model.popped = false
            Task { @MainActor in model.popped = true }
        }
    }

    func hide() {
        guard let panel, panel.parent != nil else { return }
        model.popped = false
        parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.contentView = NSHostingView(rootView: LoupeRoot(model: model))
        self.panel = panel
        return panel
    }
}

@MainActor
final class LoupeModel: ObservableObject {
    @Published var samples: [String] = []
    @Published var index = 0
    @Published var popped = false
}

/// Stable root for the panel, so cover caches survive every scrub step;
/// the pop is the covers scaling up from the fan they left.
struct LoupeRoot: View {
    @ObservedObject var model: LoupeModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZoomFlow(samples: model.samples, index: model.index)
            .scaleEffect(model.popped ? 1 : 0.3)
            .opacity(model.popped ? 1 : 0)
            .animation(reduceMotion ? nil : BMotion.standard, value: model.popped)
            .frame(width: LoupeWindow.size.width, height: LoupeWindow.size.height)
    }
}

/// The loupe's cover-flow: the fronted photo at 180 pt facing forward,
/// a neighbor either side banked away; scrubbing glides covers through.
struct ZoomFlow: View {
    let samples: [String]
    let index: Int
    @State private var thumbs: [String: NSImage] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ForEach(window, id: \.path) { card in
                cover(card.path, side: card.slot == 0 ? 180 : 124)
                    .rotation3DEffect(
                        .degrees(reduceMotion ? 0 : Double(card.slot) * -35),
                        axis: (x: 0, y: 1, z: 0), perspective: 0.55
                    )
                    .offset(x: CGFloat(card.slot) * 118)
                    .zIndex(card.slot == 0 ? 2 : 1)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : BMotion.light, value: index)
        .task(id: index) { preload() }
        .accessibilityHidden(true)
    }

    private var window: [(path: String, slot: Int)] {
        guard !samples.isEmpty else { return [] }
        return ((index - 1)...(index + 1)).compactMap { j in
            samples.indices.contains(j) ? (samples[j], j - index) : nil
        }
    }

    @ViewBuilder
    private func cover(_ path: String, side: CGFloat) -> some View {
        Group {
            if let image = thumbs[path] {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(BColor.soil)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(BColor.surface, lineWidth: 2))
        .shadow(color: BColor.ink.opacity(0.3), radius: 14, y: 8)
    }

    private func preload() {
        for j in (index - 2)...(index + 2) where samples.indices.contains(j) {
            let path = samples[j]
            guard thumbs[path] == nil else { continue }
            let request = QLThumbnailGenerator.Request(
                fileAt: URL(fileURLWithPath: path),
                size: CGSize(width: 180, height: 180), scale: 2, representationTypes: .thumbnail
            )
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
                guard let rep else { return }
                Task { @MainActor in thumbs[path] = rep.nsImage }
            }
        }
    }
}

/// The contact sheet: three real thumbnails fanned like prints. Hovering
/// raises the loupe above the row (FanZoomOverlay) and dragging across the
/// fan scrubs the pile, so two thousand photos read in two seconds.
/// Thumbnails render locally via Quick Look.
struct MediaFan: View {
    let samples: [String]
    @State private var thumbs: [String: NSImage] = [:]
    @State private var frontIndex = 0
    @State private var hovering = false
    /// The photo under Quick Look; arrows in the system panel walk the pile.
    @State private var preview: URL?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A little horizontal grace beyond the 74 pt frame keeps the scrub alive.
    private let reach: CGFloat = 12

    var body: some View {
        ZStack {
            ForEach(window, id: \.path) { card in
                thumbnail(card.path, lifted: hovering && card.slot == 0)
                    .rotationEffect(.degrees(Double(card.slot) * 4))
                    .offset(x: CGFloat(card.slot) * 5 - 3)
                    .zIndex(3 - Double(card.slot))
                    .transition(.opacity)
            }
        }
        .frame(width: 38, height: 34)
        .contentShape(Rectangle().inset(by: -reach))
        .anchorPreference(key: FanZoomKey.self, value: .bounds) { anchor in
            hovering ? FanZoom(samples: samples, index: frontIndex, anchor: anchor) : nil
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let p):
                guard !samples.isEmpty else { return }
                if !hovering {
                    setAnimated { hovering = true }
                }
                let width = 38 + reach * 2
                let index = min(samples.count - 1, max(0, Int((p.x + reach) / width * CGFloat(samples.count))))
                if index != frontIndex {
                    setAnimated { frontIndex = index }
                    // The resting fan must never come back black: the prints
                    // for wherever the scrub lands load at fan size too.
                    for j in index...(index + 2) where samples.indices.contains(j) {
                        load(samples[j])
                    }
                }
            case .ended:
                setAnimated { hovering = false }
            }
        }
        // Click opens the fronted photo in Quick Look, the same panel as
        // spacebar in Finder; its arrow keys cycle the pile.
        .onTapGesture {
            guard samples.indices.contains(frontIndex) else { return }
            preview = URL(fileURLWithPath: samples[frontIndex])
        }
        .quickLookPreview($preview, in: samples.map { URL(fileURLWithPath: $0) })
        .task {
            for path in samples.prefix(3) { load(path) }
        }
        .accessibilityHidden(true)
    }

    private func setAnimated(_ change: () -> Void) {
        if reduceMotion { change() } else { withAnimation(BMotion.light, change) }
    }

    private var window: [(path: String, slot: Int)] {
        guard !samples.isEmpty else { return [] }
        return (frontIndex...(frontIndex + 2)).compactMap { j in
            samples.indices.contains(j) ? (samples[j], j - frontIndex) : nil
        }
    }

    @ViewBuilder
    private func thumbnail(_ path: String, lifted: Bool) -> some View {
        Group {
            if let image = thumbs[path] {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(BColor.soil)
            }
        }
        .frame(width: 30, height: 30)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(BColor.surface, lineWidth: 1.5))
        .scaleEffect(lifted ? 1.08 : 1)
        .shadow(color: BColor.ink.opacity(lifted ? 0.25 : 0.15), radius: lifted ? 5 : 2, y: lifted ? 3 : 1)
    }

    private func load(_ path: String) {
        guard thumbs[path] == nil else { return }
        let request = QLThumbnailGenerator.Request(
            fileAt: URL(fileURLWithPath: path),
            size: CGSize(width: 84, height: 84), scale: 2, representationTypes: .thumbnail
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
            guard let rep else { return }
            Task { @MainActor in thumbs[path] = rep.nsImage }
        }
    }
}
