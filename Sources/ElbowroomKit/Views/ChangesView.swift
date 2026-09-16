import SwiftUI

/// Changes: a weekly bar timeline of growth and shrink per owner,
/// 12 weeks retained, each bar expandable to its events. No badges, no
/// notifications; this quiet screen is the reopen habit.
public struct ChangesView: View {
    @Environment(AppModel.self) private var model
    @State private var expanded: Date?

    public init() {}

    public var body: some View {
        let bars = model.changeLog.weekBars()
        let hasAny = bars.contains { $0.grew > 0 || $0.shrank > 0 || !$0.events.isEmpty }
        return ScrollView {
            VStack(alignment: .leading, spacing: BSpace.xl) {
                Text(Copy.viewChanges)
                    .font(BFont.title)
                    .foregroundStyle(BColor.ink)
                if hasAny {
                    timeline(bars)
                    if let week = expanded, let bar = bars.first(where: { $0.id == week }) {
                        weekDetail(bar)
                    }
                } else {
                    EmptyStateView(Copy.kibiChangesQuiet, symbol: "clock")
                        .frame(height: 300)
                }
            }
            .padding(BSpace.xxl)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(BColor.bg)
    }

    private func timeline(_ bars: [WeekBar]) -> some View {
        let maxMagnitude = max(bars.map { max($0.grew, $0.shrank) }.max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: BSpace.m) {
        HStack(alignment: .center, spacing: BSpace.m) {
            ForEach(bars) { bar in
                VStack(spacing: 2) {
                    UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 4)
                        .fill(BColor.tierRebuild)
                        .frame(width: 22, height: barHeight(bar.grew, maxMagnitude))
                    Rectangle().fill(BColor.ink.opacity(0.25)).frame(width: 26, height: 1)
                    UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 4, bottomTrailingRadius: 4, topTrailingRadius: 0)
                        .fill(BColor.tierRegen)
                        .frame(width: 22, height: barHeight(bar.shrank, maxMagnitude))
                    Text(weekLabel(bar.id))
                        .font(.system(size: 9))
                        .foregroundStyle(BColor.inkSoft)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(BMotion.light) {
                        expanded = expanded == bar.id ? nil : bar.id
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Week of \(weekLabel(bar.id)). Grew \(ByteFormat.string(bar.grew)), shrank \(ByteFormat.string(bar.shrank)).")
                .accessibilityAddTraits(.isButton)
            }
        }
        .frame(height: 190, alignment: .center)
        HStack(spacing: BSpace.l) {
            legendKey(color: BColor.tierRebuild, label: Loc.t("grew"))
            legendKey(color: BColor.tierRegen, label: Loc.t("freed"))
        }
        }
    }

    private func legendKey(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(label)
                .font(BFont.meta)
                .foregroundStyle(BColor.inkSoft)
        }
    }

    private func barHeight(_ bytes: Int64, _ maxBytes: Int64) -> CGFloat {
        let h = 70 * CGFloat(bytes) / CGFloat(maxBytes)
        return bytes > 0 ? max(3, h) : 0
    }

    private func weekLabel(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "M/d"
        return df.string(from: date)
    }

    private func weekDetail(_ bar: WeekBar) -> some View {
        VStack(alignment: .leading, spacing: BSpace.s) {
            ForEach(Array(bar.topOwnerDeltas.enumerated()), id: \.offset) { _, delta in
                HStack(spacing: 6) {
                    Image(systemName: delta.delta > 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(delta.delta > 0 ? BColor.tierRebuild : BColor.tierRegen)
                    Text("\(delta.owner) \(delta.delta > 0 ? "+" : "−")\(ByteFormat.string(abs(delta.delta)))")
                        .font(BFont.body)
                        .foregroundStyle(BColor.ink)
                }
            }
            ForEach(bar.events) { event in
                HStack(spacing: 6) {
                    Circle().fill(BColor.brand).frame(width: 5, height: 5)
                    Text(event.text)
                        .font(BFont.meta)
                        .foregroundStyle(BColor.inkSoft)
                    Text(event.date.formatted(.dateTime.month(.abbreviated).day()))
                        .font(BFont.meta)
                        .foregroundStyle(BColor.inkSoft.opacity(0.7))
                }
            }
        }
        .bCard()
    }
}
