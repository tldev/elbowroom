import SwiftUI

/// R2/R3: the plan sheet is the informed consent; nothing is summarized
/// away. Then execution with per-item status, the jar fill, and the pour.
public struct ReclaimPlanSheet: View {
    @Environment(AppModel.self) private var model
    @State private var checked: Set<String> = []
    @State private var didInit = false

    public init() {}

    private var selectedItems: [AtlasItem] { model.planItems.filter { checked.contains($0.id) } }
    private var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.bytes } }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.reclaiming || model.reclaimOutcome != nil {
                executionView
            } else {
                planList
            }
            Divider()
            footer
        }
        .frame(width: 640, height: 540)
        .background(BColor.bg)
        .fanZoomOverlay()
        .onAppear {
            guard !didInit else { return }
            didInit = true
            checked = Set(model.planItems.map(\.id))
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(model.planTitle)
                .font(.system(size: 19, weight: .heavy))
                .foregroundStyle(BColor.ink)
            Spacer()
            Text(Copy.planSubtitle)
                .font(BFont.meta)
                .foregroundStyle(BColor.inkSoft)
        }
        .padding(BSpace.sheetPadding)
    }

    // MARK: Plan (R2)

    private var planList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BSpace.l) {
                ForEach(ReclaimPlan(items: model.planItems).byOwner, id: \.owner) { group in
                    VStack(alignment: .leading, spacing: BSpace.s) {
                        Text(group.owner)
                            .font(BFont.meta.weight(.semibold))
                            .foregroundStyle(BColor.inkSoft)
                        ForEach(group.items) { item in
                            PlanRowView(
                                item: item,
                                checked: Binding(
                                    get: { checked.contains(item.id) },
                                    set: { on in
                                        if on { checked.insert(item.id) } else { checked.remove(item.id) }
                                    }
                                )
                            )
                        }
                    }
                }
            }
            .padding(BSpace.sheetPadding)
        }
    }

    // MARK: Execution (R3)

    private var executionView: some View {
        VStack(spacing: BSpace.l) {
            JarFill(progress: executionProgress)
                .frame(width: 220)
            if let outcome = model.reclaimOutcome {
                if !outcome.skipped.isEmpty {
                    // Errors get words, never sounds.
                    VStack(alignment: .leading, spacing: BSpace.s) {
                        Text(Copy.partialFail(outcome.skipped.count))
                            .font(BFont.body.weight(.semibold))
                            .foregroundStyle(BColor.ink)
                        ForEach(Array(outcome.skipped.enumerated()), id: \.offset) { _, skip in
                            Text("\(skip.name): \(skip.reason)")
                                .font(BFont.meta)
                                .foregroundStyle(BColor.inkSoft)
                        }
                    }
                    .frame(maxWidth: 420)
                } else if outcome.cancelled {
                    Text(Copy.reclaimStopped(outcome.doneCount))
                        .font(BFont.body)
                        .foregroundStyle(BColor.ink)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                }
            } else {
                statusList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(BSpace.sheetPadding)
    }

    private var executionProgress: Double {
        let total = model.reclaimStatuses.count
        guard total > 0 else { return 0 }
        let done = model.reclaimStatuses.filter {
            if case .done = $0 { return true }
            if case .skipped = $0 { return true }
            return false
        }.count
        return Double(done) / Double(total)
    }

    private var statusList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                let running = ReclaimPlan(items: selectedItems)
                ForEach(Array(running.items.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 8) {
                        statusIcon(index)
                        Text(item.displayName)
                            .font(BFont.meta)
                            .foregroundStyle(BColor.ink)
                        Spacer()
                        Text(ByteFormat.string(item.bytes))
                            .font(BFont.rounded(12, .medium))
                            .foregroundStyle(BColor.inkSoft)
                    }
                }
            }
        }
        .frame(maxHeight: 180)
    }

    @ViewBuilder
    private func statusIcon(_ index: Int) -> some View {
        let status = index < model.reclaimStatuses.count ? model.reclaimStatuses[index] : .pending
        switch status {
        case .pending:
            Circle().strokeBorder(BColor.line, lineWidth: 1.5).frame(width: 14, height: 14)
        case .moving:
            ProgressView().controlSize(.small).frame(width: 14, height: 14)
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(BColor.tierRegen).font(.system(size: 13))
        case .skipped:
            Image(systemName: "minus.circle").foregroundStyle(BColor.inkSoft).font(.system(size: 13))
        }
    }

    // MARK: Footer

    private var footer: some View {
        @Bindable var model = model
        let split = ReclaimPlan(items: selectedItems).freeSplit(remainingAllowance: model.pro.remainingAllowance)
        let freeBytes = split.now.reduce(Int64(0)) { $0 + $1.bytes }
        let lockedBytes = split.withPro.reduce(Int64(0)) { $0 + $1.bytes }

        return VStack(alignment: .leading, spacing: BSpace.m) {
            if model.reclaimOutcome == nil, !model.reclaiming, lockedBytes > 0 {
                // The free boundary split; the paywall never blocks the
                // free part.
                HStack(spacing: 8) {
                    Text("\(ByteFormat.string(freeBytes)) now · \(ByteFormat.string(lockedBytes)) with Pro")
                        .font(BFont.meta.weight(.medium))
                        .foregroundStyle(BColor.ink)
                    Text(Copy.paywallBoundary)
                        .font(BFont.meta)
                        .foregroundStyle(BColor.inkSoft)
                    Spacer()
                    Button(Copy.paywallButton) { model.sheet = .paywall(trigger: "free_boundary") }
                        .buttonStyle(.plain)
                        .font(BFont.meta.weight(.semibold))
                        .foregroundStyle(BColor.brand)
                }
            }
            HStack(spacing: BSpace.l) {
                if model.reclaimOutcome != nil {
                    Spacer()
                    PrimaryButton(Copy.ok) {
                        model.reclaimOutcome = nil
                        model.closeSheet()
                        model.clearTray()
                    }
                } else if model.reclaiming {
                    Spacer()
                    Button(Copy.cancel) { model.cancelReclaim() }
                        .buttonStyle(SecondaryButtonStyle())
                } else {
                    Toggle(Copy.trashToggle, isOn: $model.planKeepInTrash)
                        .toggleStyle(.checkbox)
                        .font(BFont.meta)
                        .fixedSize()
                    Spacer()
                    Button(Copy.cancel) { model.closeSheet() }
                        .buttonStyle(SecondaryButtonStyle())
                    PrimaryButton(Copy.reclaimPrimary(ByteFormat.string(lockedBytes > 0 ? freeBytes : selectedBytes))) {
                        model.runReclaim(selected: selectedItems)
                    }
                    .disabled(selectedItems.isEmpty)
                }
            }
        }
        .padding(BSpace.sheetPadding)
    }
}

/// PlanRow: checkbox · identity (2 lines max) · size over cost line.
/// Lens rows carry their own face: the finding's thumbnails, its
/// specific evidence, and the path, so consent here is as informed as the
/// lens sheet that offered it.
struct PlanRowView: View {
    @Environment(AppModel.self) private var model
    let item: AtlasItem
    @Binding var checked: Bool

    private var finding: LensFinding? {
        guard item.entryID == "lens.found" else { return nil }
        return model.lensFindings.first { $0.url.path == item.id }
    }

    var body: some View {
        HStack(alignment: .top, spacing: BSpace.m) {
            Toggle("", isOn: $checked)
                .labelsHidden()
                .toggleStyle(.checkbox)
            if let finding, finding.wearsMediaFan {
                MediaFan(samples: finding.samples)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(finding?.displayTitle ?? item.displayName)
                        .font(BFont.body)
                        .foregroundStyle(BColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
                    TierChip(item.entry.tier)
                        .fixedSize()
                }
                if let finding {
                    Text(finding.evidenceLine)
                        .font(BFont.meta)
                        .foregroundStyle(BColor.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(homePath(item.url.path))
                        .font(BFont.path)
                        .foregroundStyle(BColor.inkSoft.opacity(0.8))
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text(item.entry.identityLine)
                        .font(BFont.meta)
                        .foregroundStyle(BColor.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(ByteFormat.string(item.bytes))
                    .font(BFont.rounded(14, .semibold))
                    .foregroundStyle(BColor.ink)
                if let cost = item.costLine(bytesPerSecond: model.settings.connectionBytesPerSecond) {
                    Text(cost)
                        .font(.system(size: 11))
                        .foregroundStyle(BColor.inkSoft)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 200, alignment: .trailing)
                }
            }
        }
        .frame(minHeight: 44)
    }

    private func homePath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) { return "~" + path.dropFirst(home.count) }
        return path
    }
}

/// Determinate progress for the run (M3), instrument-plain.
struct JarFill: View {
    let progress: Double
    var body: some View {
        VStack(spacing: BSpace.s) {
            Text("\(Int(progress * 100))%")
                .font(BFont.rounded(28, .semibold))
                .foregroundStyle(BColor.ink)
                .contentTransition(.numericText())
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(BColor.soil)
                    Capsule()
                        .fill(BColor.ink.opacity(0.8))
                        .frame(width: max(4, geo.size.width * progress))
                        .animation(.easeOut(duration: 0.4), value: progress)
                }
            }
            .frame(height: 6)
        }
        .accessibilityLabel("\(Int(progress * 100)) percent done")
    }
}
