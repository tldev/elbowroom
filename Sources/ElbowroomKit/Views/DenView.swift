import SwiftUI

/// The Den (Warm Instrument): a two-column briefing. Main: the hero
/// card (ready-to-reclaim number, its verb, and the reclaimable composition),
/// the biggest wins as add-to-plan rows, and the door to the map. Side:
/// what is changing, the drive, update readiness, and the all-time count.
public struct DenView: View {
    @Environment(AppModel.self) private var model

    public init() {}

    public var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 20) {
                    heroCard
                    if model.isCrisis {
                        crisisCard
                    }
                    biggestWins
                    everythingElseCard
                }
                .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 14) {
                    thisWeekCard
                    updateCard
                    allTimeCard
                }
                .frame(width: 300)
            }
            .padding(BSpace.xl)
            .frame(maxWidth: 1140, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(BColor.bg)
    }

    // MARK: Hero

    private var heroCard: some View {
        let composition = reclaimComposition
        let total = max(composition.reduce(0) { $0 + $1.bytes }, 1)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: BSpace.l) {
                VStack(alignment: .leading, spacing: 6) {
                    if model.scanning {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(Copy.scanningVerify)
                                .font(BFont.meta)
                                .foregroundStyle(BColor.inkSoft)
                        }
                    } else {
                        Text(Copy.readyToReclaim.uppercased())
                            .font(.system(size: 12, weight: .semibold))
                            .kerning(0.7)
                            .foregroundStyle(BColor.inkSoft)
                    }
                    ByteCounter(bytes: model.solidReclaimable, size: 52)
                    Text(Copy.heroExplainer)
                        .font(BFont.body)
                        .foregroundStyle(BColor.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 380, alignment: .leading)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: BSpace.s) {
                    PrimaryButton(Copy.reclaimPrimary(ByteFormat.string(model.solidReclaimable))) {
                        let plan = model.items.filter {
                            $0.entry.tier == .regenerable || $0.entry.tier == .rebuildable
                        }
                        model.openReclaimPlan(items: plan.sorted { $0.bytes > $1.bytes })
                    }
                }
            }
            // The reclaimable composition, tier by tier.
            HStack(spacing: 2) {
                ForEach(composition, id: \.tier) { part in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(part.tier.color)
                        .frame(width: nil, height: 10)
                        .frame(maxWidth: max(4, 600 * CGFloat(part.bytes) / CGFloat(total)))
                }
            }
            .frame(height: 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .padding(.top, 20)
            HStack(spacing: 20) {
                ForEach(composition, id: \.tier) { part in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(part.tier.color)
                            .frame(width: 8, height: 8)
                        Text("\(part.tier.label) · \(ByteFormat.string(part.bytes))")
                            .font(.system(size: 12.5))
                            .foregroundStyle(BColor.inkSoft)
                    }
                }
            }
            .padding(.top, 12)
        }
        .bCard()
    }

    private var reclaimComposition: [(tier: Tier, bytes: Int64)] {
        var byTier: [Tier: Int64] = [:]
        for item in model.items {
            switch item.entry.tier {
            case .regenerable, .rebuildable:
                byTier[item.entry.tier, default: 0] += item.bytes
            default: break
            }
        }
        return Tier.allCases.compactMap { tier in
            byTier[tier].map { (tier, $0) }
        }
    }

    /// Crisis pins a pre-composed plan card first.
    private var crisisCard: some View {
        let plan = model.crisisPlan()
        let total = plan.reduce(Int64(0)) { $0 + $1.bytes }
        return HStack(spacing: BSpace.l) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Copy.b5Crisis)
                    .font(BFont.body.weight(.semibold))
                    .foregroundStyle(BColor.ink)
                Text(Copy.b5CrisisDoor(ByteFormat.string(total)))
                    .font(BFont.meta)
                    .foregroundStyle(BColor.inkSoft)
            }
            Spacer()
            Button(Copy.trayReclaim) { model.openReclaimPlan(items: plan) }
                .buttonStyle(SecondarySmallButtonStyle())
        }
        .bCard()
    }

    // MARK: Biggest wins

    @ViewBuilder
    private var biggestWins: some View {
        let suggestions = model.suggestions
        let hidden = model.hiddenSuggestionCount
        if suggestions.isEmpty && hidden == 0 && !model.isCrisis {
            EmptyStateView(Copy.kibiDenTidy)
                .frame(height: 200)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Copy.biggestWins)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(BColor.ink)
                    Spacer()
                    Button("\(Copy.allStorageItems) →") {
                        model.ledgerTierFilter = nil
                        model.view = .ledger
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(BColor.brand)
                }
                .padding(.horizontal, 4)
                VStack(spacing: 0) {
                    ForEach(Array(suggestions.prefix(5).enumerated()), id: \.element.id) { index, s in
                        if index > 0 { Divider().overlay(BColor.hair) }
                        SuggestionCard(suggestion: s)
                    }
                }
                .background(BColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: BRadius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: BRadius.card, style: .continuous).strokeBorder(BColor.hair, lineWidth: 1))
                if hidden > 0 {
                    HStack(spacing: BSpace.s) {
                        Text(Copy.hiddenSuggestions(hidden))
                            .font(BFont.meta)
                            .foregroundStyle(BColor.inkSoft)
                        Button(Copy.showHidden) {
                            withAnimation(BMotion.light) { model.showHiddenSuggestions() }
                        }
                        .buttonStyle(.plain)
                        .font(BFont.meta.weight(.medium))
                        .foregroundStyle(BColor.brand)
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
    }

    /// The gray band's front door: dashed, quiet, routes to the map.
    private var everythingElseCard: some View {
        Button {
            model.view = .crossSection
        } label: {
            HStack(spacing: BSpace.m) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(BColor.inkSoft)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(Copy.everythingElse) · \(ByteFormat.string(model.everythingElseBytes))")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(BColor.ink)
                    Text(model.remainingStorageExplanation)
                        .font(BFont.body)
                        .foregroundStyle(BColor.inkSoft)
                        .lineLimit(2)
                }
                .help(Copy.remainingStorageDetail)
                Spacer()
                Text("\(Copy.openMapLink) →")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(BColor.brand)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .overlay(
                RoundedRectangle(cornerRadius: BRadius.card, style: .continuous)
                    .strokeBorder(BColor.line, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            )
            .contentShape(RoundedRectangle(cornerRadius: BRadius.card))
        }
        .buttonStyle(.plain)
    }

    // MARK: Side column

    @ViewBuilder
    private var thisWeekCard: some View {
        let deltas = model.changeLog.weekDeltas()
        if !deltas.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sideLabel(Copy.growingThisWeek)
                VStack(spacing: 10) {
                    ForEach(Array(deltas.enumerated()), id: \.offset) { _, delta in
                        HStack {
                            Text(delta.label)
                                .font(BFont.body)
                                .foregroundStyle(BColor.ink)
                            Spacer()
                            Text("\(delta.delta > 0 ? "↑" : "↓") \(ByteFormat.string(abs(delta.delta)))")
                                .font(BFont.rounded(13, .semibold))
                                .foregroundStyle(delta.delta > 0 ? BColor.tierRebuild : BColor.ok)
                        }
                    }
                }
                if deltas.contains(where: { $0.delta < 0 }) {
                    Text(Copy.trimmedFootnote)
                        .font(.system(size: 11.5))
                        .foregroundStyle(BColor.inkSoft)
                        .padding(.top, 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .bCard()
        }
    }

    private var updateCard: some View {
        let free = model.result?.disk.available ?? 0
        let need: Int64 = 24 * 1_000_000_000
        return VStack(alignment: .leading, spacing: 10) {
            sideLabel(Copy.planForUpdate)
            if free >= need {
                Text(Copy.updateCovered(ByteFormat.string(need), ByteFormat.string(free)))
                    .font(BFont.body)
                    .foregroundStyle(BColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(BColor.soil)
                        Capsule().fill(BColor.ok)
                            .frame(width: max(4, geo.size.width * CGFloat(need) / CGFloat(max(free, 1))))
                    }
                }
                .frame(height: 6)
            } else {
                Text(Copy.planRoomForUpdate)
                    .font(BFont.body)
                    .foregroundStyle(BColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Button(Copy.planForUpdate) {
                    model.composeUpdatePlan(neededBytes: max(need - free, 5_000_000_000))
                }
                .buttonStyle(SecondarySmallButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .bCard()
    }

    @ViewBuilder
    private var allTimeCard: some View {
        if model.receipts.lifetimeBytes > 0 {
            VStack(alignment: .leading, spacing: 6) {
                sideLabel(Copy.allTimeLabel)
                ByteCounter(bytes: model.receipts.lifetimeBytes, size: 32)
                Text(Copy.returnedToMac)
                    .font(.system(size: 12.5))
                    .foregroundStyle(BColor.inkSoft)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(BSpace.cardPadding)
            .background(
                LinearGradient(colors: [BColor.brandSoft, .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .background(BColor.surface)
            )
            .clipShape(RoundedRectangle(cornerRadius: BRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: BRadius.card, style: .continuous).strokeBorder(BColor.hair, lineWidth: 1))
        }
    }

    private func sideLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11.5, weight: .semibold))
            .kerning(0.7)
            .foregroundStyle(BColor.inkSoft)
    }
}

/// One win row (Warm Instrument): tier dot · name and line · size · verb.
/// Selectable rows build the plan in place; managed rows keep their doors.
struct SuggestionCard: View {
    @Environment(AppModel.self) private var model
    let suggestion: AppModel.Suggestion
    @State private var hover = false

    var body: some View {
        HStack(spacing: 14) {
            if let item = suggestion.item {
                RoundedRectangle(cornerRadius: 3)
                    .fill(item.entry.tier.color)
                    .frame(width: 9, height: 9)
                VStack(alignment: .leading, spacing: 1) {
                    Text(suggestion.title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(BColor.ink)
                    Text(suggestion.line)
                        .font(BFont.meta)
                        .foregroundStyle(BColor.inkSoft)
                        .lineLimit(2)
                }
                Spacer()
                if hover {
                    Button {
                        withAnimation(BMotion.light) { model.dismissSuggestion(suggestion.id) }
                    } label: {
                        Text(Copy.hide)
                            .font(BFont.meta.weight(.medium))
                            .foregroundStyle(BColor.inkSoft)
                    }
                    .buttonStyle(.plain)
                    .help(Copy.hideThirtyDays)
                }
                Text(suggestion.members.isEmpty ? Copy.groupTotal(ByteFormat.string(suggestion.bytes)) : ByteFormat.string(suggestion.bytes))
                    .font(BFont.rounded(13.5, .bold))
                    .foregroundStyle(BColor.ink)
                action(item)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLine)
    }

    private var accessibilityLine: String {
        guard let item = suggestion.item else { return suggestion.line }
        return "\(suggestion.title), \(ByteFormat.string(suggestion.bytes)), \(item.entry.tier.label)"
    }

    /// Selectable rows toggle the plan; everything else keeps its verb.
    @ViewBuilder
    private func action(_ item: AtlasItem) -> some View {
        if !suggestion.members.isEmpty {
            Button(Copy.reviewCleanup) { model.openReclaimPlan(items: suggestion.members) }
                .buttonStyle(PlanToggleButtonStyle(on: false))
        } else if model.canSelect(item) {
            let inPlan = model.trayItems.contains(item)
            Button(inPlan ? "\(Copy.inPlan) ✓" : Copy.addToPlan) {
                withAnimation(BMotion.light) { model.toggleTray(item) }
            }
            .buttonStyle(PlanToggleButtonStyle(on: inPlan))
        } else {
            Button(suggestion.action.title) { model.perform(suggestion.action, on: item) }
                .buttonStyle(PlanToggleButtonStyle(on: false))
                .accessibilityLabel(suggestion.action.title)
        }
    }


}

/// The add-to-plan pill: bordered at rest, accent-soft once in the plan.
struct PlanToggleButtonStyle: ButtonStyle {
    let on: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(on ? BColor.brand : BColor.ink)
            .padding(.horizontal, 14)
            .frame(height: 28)
            .background(on ? AnyShapeStyle(BColor.brandSoft) : AnyShapeStyle(BColor.surface), in: Capsule())
            .overlay {
                if !on { Capsule().strokeBorder(BColor.line, lineWidth: 1) }
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Small quiet pill (Warm Instrument): soil fill, ink label.
struct SecondarySmallButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(BColor.ink)
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(BColor.soil, in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
