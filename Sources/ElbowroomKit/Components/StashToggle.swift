import SwiftUI

/// StashToggle: 64×28 track, labels `Internal / Stash` outside the track,
/// knob carries a 2 pt progress ring during moves, disabled shows its reason
/// on hover. The tooltip states reversibility outright.
public struct StashToggle: View {
    let isStashed: Bool
    let progress: Double?      // nil = idle
    let disabledReason: String?
    let action: () -> Void

    public init(isStashed: Bool, progress: Double?, disabledReason: String?, action: @escaping () -> Void) {
        self.isStashed = isStashed
        self.progress = progress
        self.disabledReason = disabledReason
        self.action = action
    }

    private var busy: Bool { progress != nil }

    public var body: some View {
        HStack(spacing: BSpace.s) {
            Text(Copy.toggleInternal)
                .font(BFont.meta)
                .foregroundStyle(isStashed ? BColor.inkSoft : BColor.ink)
            track
            Text(Copy.toggleStash)
                .font(BFont.meta)
                .foregroundStyle(isStashed ? BColor.ink : BColor.inkSoft)
        }
        .opacity(disabledReason == nil ? 1 : 0.5)
        .help(disabledReason ?? Copy.toggleTooltip)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Offload toggle, \(isStashed ? "offloaded" : "local")")
        .accessibilityAddTraits(.isButton)
    }

    private var track: some View {
        ZStack(alignment: isStashed ? .trailing : .leading) {
            Capsule()
                .fill(isStashed ? BColor.brand.opacity(0.35) : BColor.soil)
                .overlay(Capsule().strokeBorder(BColor.line, lineWidth: 1))
            knob
                .padding(2)
        }
        .frame(width: 64, height: 28)
        .contentShape(Capsule())
        .onTapGesture {
            guard disabledReason == nil, !busy else { return }
            action()
        }
        .animation(BMotion.standard, value: isStashed)
    }

    private var knob: some View {
        ZStack {
            Circle()
                .fill(BColor.surface)
                .overlay(Circle().strokeBorder(BColor.line, lineWidth: 1))
            if let progress {
                Circle()
                    .trim(from: 0, to: max(0.03, progress))
                    .stroke(BColor.brand, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(2)
                    .animation(.linear(duration: 0.2), value: progress)
            } else {
                Image(systemName: isStashed ? "externaldrive.fill" : "internaldrive")
                    .font(.system(size: 10))
                    .foregroundStyle(isStashed ? BColor.brand : BColor.inkSoft)
            }
        }
        .frame(width: 24, height: 24)
    }
}
