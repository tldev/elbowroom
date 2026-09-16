import SwiftUI

/// The Disk Strip: a 28 pt full-width bar of the boot volume tinted by tier
/// proportion, free space at the right edge, live headroom figure at the left.
/// Visible in every view. Hovering shows a legend card near the cursor;
/// clicking a tier band opens Items filtered to that tier; the headroom
/// figure opens the current Reclaim plan. Nothing else on the strip reacts
/// to clicks, so a miss never summons a window.
/// Marks: solid tier fills separated by 2 pt surface gaps; text stays in ink.
/// Slivers keep a floor width and magnify under the cursor (StripLayout).
public struct DiskStrip: View {
    @Environment(AppModel.self) private var model
    @State private var hover = false
    @State private var labelHover = false
    @State private var hoverSegment: Int?
    @State private var mouseX: CGFloat?
    @State private var mouseBarX: CGFloat?
    @State private var cardVisible = false
    /// Snapshot/test hook: renders the legend card without a real hover.
    private let pinBreakdown: Bool

    public init(pinBreakdown: Bool = false) {
        self.pinBreakdown = pinBreakdown
    }

    private let cardWidth: CGFloat = 240

    public var body: some View {
        HStack(spacing: BSpace.m) {
            headroomLabel
            bar
            freeLabelOutside
        }
        .frame(height: 28)
        .padding(.horizontal, BSpace.l)
        .contentShape(Rectangle())
        .onHover { h in
            hover = h
            if !h { hoverSegment = nil }
        }
        .onContinuousHover(coordinateSpace: .local) { phase in
            if case .active(let p) = phase { mouseX = p.x }
        }
        // Tooltip rules: a short dwell, then it is simply there. No fade, no
        // slide; a mouse passing through to the content never flashes it.
        .task(id: hover) {
            if hover {
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }
                cardVisible = true
            } else {
                cardVisible = false
            }
        }
        .overlay(alignment: .topLeading) {
            if (cardVisible || pinBreakdown) && !model.stripSegments.isEmpty {
                GeometryReader { geo in
                    breakdownCard
                        .offset(x: cardX(in: geo.size.width), y: 34)
                }
                .allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.headroom(ByteFormat.string(model.headroomBytes)))
        .accessibilityValue(compositionLine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { openPlan() }
    }

    private var headroomLabel: some View {
        HStack(spacing: 5) {
            Text(ByteFormat.string(model.headroomBytes))
                .font(BFont.rounded(13, .bold))
                .foregroundStyle(BColor.ink)
                .underline(labelHover)
                .contentTransition(.numericText(value: Double(model.headroomBytes)))
            Text(Copy.safelyReclaimable)
                .font(BFont.meta)
                .foregroundStyle(BColor.inkSoft)
        }
        .fixedSize()
        .contentShape(Rectangle())
        .onHover { labelHover = $0 }
        .onTapGesture { openPlan() }
        .help(Copy.planTitle)
    }

    private var bar: some View {
        GeometryReader { geo in
            let trackH: CGFloat = 8
            let segments = model.stripSegments
            let marks = currentMarks(barWidth: geo.size.width)
            ZStack(alignment: .topLeading) {
                // Track: the whole volume; what stays uncovered is free space.
                Capsule()
                    .fill(BColor.soil)
                ForEach(marks, id: \.index) { mark in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(segments[mark.index].tier?.color ?? BColor.faint)
                        .brightness(hoverSegment == mark.index ? 0.09 : 0)
                        .frame(width: mark.width, height: trackH - 2)
                        .offset(x: 2 + mark.x, y: 1)
                }
            }
            .frame(height: trackH)
            .frame(maxHeight: .infinity, alignment: .center)
            // One hit surface for the whole 28 pt bar; hover and taps resolve
            // through the same layout the marks were drawn with.
            .contentShape(Rectangle())
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let p):
                    mouseBarX = p.x
                    hoverSegment = StripLayout.hit(currentMarks(barWidth: geo.size.width), at: p.x - 2)
                case .ended:
                    mouseBarX = nil
                    hoverSegment = nil
                }
            }
            .gesture(SpatialTapGesture().onEnded { value in
                let hit = StripLayout.hit(currentMarks(barWidth: geo.size.width), at: value.location.x - 2)
                guard let hit, hit >= 0 else { return }
                if let tier = segments[hit].tier {
                    model.focusLedger(tier: tier)
                } else {
                    // The gray band's verb: look closer.
                    model.openLenses()
                }
            })
        }
        .animation(BMotion.standard, value: model.headroomBytes)
    }

    /// "461 GB free of 1 TB", quiet, outside the track (Warm Instrument).
    @ViewBuilder
    var freeLabelOutside: some View {
        if let disk = model.result?.disk {
            Text(Copy.freeOfTotal(ByteFormat.string(disk.available), ByteFormat.string(disk.totalCapacity)))
                .font(BFont.meta)
                .foregroundStyle(BColor.inkSoft)
                .fixedSize()
        }
    }

    /// Mark layout for the current mouse position: proportional widths with
    /// the sliver floor and cursor magnifier (StripLayout).
    private func currentMarks(barWidth: CGFloat) -> [StripLayout.Mark] {
        let total = max(model.result?.disk.totalCapacity ?? 1, 1)
        let available = barWidth - 8
        guard available > 0 else { return [] }
        let naturals = model.stripSegments.map {
            available * CGFloat($0.bytes) / CGFloat(total)
        }
        return StripLayout.marks(natural: naturals, mouseX: mouseBarX.map { $0 - 2 })
    }

    private func openPlan() {
        let plan = model.items.filter {
            !$0.isStashed && ($0.entry.tier == .regenerable || $0.entry.tier == .rebuildable)
        }
        model.openReclaimPlan(items: plan.sorted { $0.bytes > $1.bytes })
    }

    // MARK: Legend card

    /// Sits just under the strip, trailing the cursor like a tooltip and
    /// clamped to the window. Legend only; it never takes the mouse.
    private func cardX(in width: CGFloat) -> CGFloat {
        let x = (mouseX ?? BSpace.l) + 12
        return min(max(BSpace.l, x), width - cardWidth - BSpace.l)
    }

    /// The breakdown behind the strip: one row per mark plus free space,
    /// hovered mark's row lit.
    private var breakdownCard: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(model.stripSegments.enumerated()), id: \.offset) { i, segment in
                breakdownRow(
                    swatch: segment.tier?.color ?? BColor.inkSoft.opacity(0.45),
                    label: segment.tier?.label ?? Copy.everythingElse,
                    bytes: segment.bytes,
                    lit: hoverSegment == i
                )
                // The gray band is a door: named findings preview here,
                // and the hint says it opens.
                if segment.tier == nil {
                    if model.lensIdentifiedBytes > 0 {
                        Text(Copy.lensIdentified(ByteFormat.string(model.lensIdentifiedBytes)))
                            .font(BFont.meta)
                            .foregroundStyle(BColor.inkSoft)
                            .padding(.leading, 22)
                    }
                    Text(Copy.lensHint)
                        .font(BFont.meta)
                        .foregroundStyle(BColor.inkSoft.opacity(0.8))
                        .padding(.leading, 22)
                        .padding(.bottom, 2)
                }
            }
            if let disk = model.result?.disk {
                breakdownRow(
                    swatch: BColor.soil, stroked: true,
                    label: Copy.freeLabel, bytes: disk.available,
                    lit: hoverSegment == StripLayout.freeIndex
                )
            }
        }
        .padding(BSpace.s)
        .frame(width: cardWidth)
        .background(BColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: BRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BRadius.card, style: .continuous)
                .strokeBorder(BColor.line, lineWidth: 1)
        )
        .shadow(color: BColor.ink.opacity(0.1), radius: 16, y: 6)
        .accessibilityHidden(true)
    }

    private func breakdownRow(swatch: Color, stroked: Bool = false, label: String, bytes: Int64, lit: Bool) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3)
                .fill(swatch)
                .overlay {
                    if stroked {
                        RoundedRectangle(cornerRadius: 3).strokeBorder(BColor.line, lineWidth: 1)
                    }
                }
                .frame(width: 10, height: 10)
            Text(label)
                .font(.system(size: 12, weight: lit ? .semibold : .regular))
                .foregroundStyle(BColor.ink)
            Spacer(minLength: BSpace.m)
            Text(ByteFormat.string(bytes))
                .font(BFont.rounded(12, .medium))
                .foregroundStyle(BColor.ink)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(lit ? BColor.soil : .clear, in: RoundedRectangle(cornerRadius: 4))
    }

    /// VoiceOver's copy of the legend, one line.
    private var compositionLine: String {
        var parts: [String] = []
        for segment in model.stripSegments {
            parts.append("\(segment.tier?.label ?? Copy.everythingElse) \(ByteFormat.string(segment.bytes))")
        }
        if let free = model.result?.disk.available {
            parts.append(Copy.freeAmount(ByteFormat.string(free)))
        }
        return parts.joined(separator: " · ")
    }
}
