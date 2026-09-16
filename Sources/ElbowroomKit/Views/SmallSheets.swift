import SwiftUI
import AppKit

// MARK: - Teach flow sheet

public struct TeachFlowSheet: View {
    @Environment(AppModel.self) private var model
    let flowID: TeachFlowID
    let bytes: Int64
    @State private var copiedTick = false

    public init(flowID: TeachFlowID, bytes: Int64) {
        self.flowID = flowID
        self.bytes = bytes
    }

    private var flow: TeachFlow { TeachFlow.flow(flowID) }

    public var body: some View {
        VStack(alignment: .leading, spacing: BSpace.l) {
            HStack(alignment: .firstTextBaseline) {
                Text(flow.title)
                    .font(BFont.title)
                    .foregroundStyle(BColor.ink)
                Spacer()
                if bytes > 0 {
                    HStack(spacing: 6) {
                        HollowBadge()
                        Text(ByteFormat.string(bytes))
                            .font(BFont.rounded(20, .bold))
                            .foregroundStyle(BColor.ink)
                    }
                }
            }
            Text(flow.why)
                .font(BFont.body)
                .foregroundStyle(BColor.ink)
                .lineSpacing(3)

            if let doorLabel = flow.doorLabel {
                Button {
                    openDoor()
                } label: {
                    Label(doorLabel, systemImage: "arrow.up.forward.app")
                        .font(BFont.body.weight(.medium))
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            if let command = flow.command {
                VStack(alignment: .leading, spacing: BSpace.s) {
                    if let warning = flow.warning {
                        Label(warning, systemImage: "info.circle")
                            .font(BFont.meta)
                            .foregroundStyle(BColor.inkSoft)
                    }
                    HStack(alignment: .top) {
                        Text(command)
                            .font(BFont.path.weight(.medium))
                            .foregroundStyle(BColor.ink)
                            .textSelection(.enabled)
                        Spacer()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(command, forType: .string)
                            SoundPlayer.shared.play(.pebble)
                            withAnimation(BMotion.light) { copiedTick = true }
                            Task {
                                try? await Task.sleep(nanoseconds: 1_500_000_000)
                                withAnimation { copiedTick = false }
                            }
                        } label: {
                            Label(copiedTick ? Copy.copied : Copy.copyCommand,
                                  systemImage: copiedTick ? "checkmark" : "doc.on.doc")
                                .font(BFont.meta)
                        }
                        .buttonStyle(SecondarySmallButtonStyle())
                    }
                    if let gloss = flow.commandGloss {
                        Text(gloss)
                            .font(BFont.meta)
                            .foregroundStyle(BColor.inkSoft)
                    }
                }
                .padding(BSpace.m)
                .background(BColor.soil.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: BRadius.control))
            }

            Spacer()
            HStack {
                Spacer()
                PrimaryButton(Copy.ok) { model.sheet = nil }
            }
        }
        .padding(BSpace.sheetPadding)
        .frame(width: 520, height: flow.command == nil ? 300 : 420)
        .background(BColor.bg)
    }

    private func openDoor() {
        switch flowID {
        case .simulatorRuntimes:
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Xcode.app"))
        case .deviceBackups:
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"))
        case .trash:
            let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
            NSWorkspace.shared.open(trash)
        default:
            if let urlString = flow.doorURL, let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        }
        Analytics.shared.log("teach_open", ["flow": flowID.rawValue, "action": "door"])
    }
}

// MARK: - Paywall

public struct PaywallSheet: View {
    @Environment(AppModel.self) private var model
    let trigger: String

    public init(trigger: String) { self.trigger = trigger }

    public var body: some View {
        VStack(spacing: BSpace.l) {
            Text(Copy.paywallTitle)
                .font(BFont.title)
                .foregroundStyle(BColor.ink)
            if trigger == "free_boundary" {
                Text(Copy.paywallBoundary)
                    .font(BFont.meta)
                    .foregroundStyle(BColor.inkSoft)
            }
            VStack(alignment: .leading, spacing: BSpace.s) {
                ForEach(Copy.paywallLines, id: \.self) { line in
                    Label(line, systemImage: "checkmark")
                        .font(BFont.body)
                        .foregroundStyle(BColor.ink)
                }
            }
            Text(model.purchases.priceLine)
                .font(BFont.body.weight(.semibold))
                .foregroundStyle(BColor.ink)
            if model.purchases.busy {
                ProgressView()
                    .frame(height: 44)
            } else if model.purchases.storeReachable {
                PrimaryButton(Copy.paywallButton) {
                    Task {
                        let bought = await model.purchases.purchase()
                        Analytics.shared.log("paywall", ["trigger": trigger, "outcome": bought ? "purchase" : "cancel"])
                        if bought { model.sheet = nil }
                    }
                }
            } else {
                // No App Store product from this build; say so instead of a
                // button that would lie (register).
                Text(Copy.paywallUnavailable)
                    .font(BFont.meta)
                    .foregroundStyle(BColor.inkSoft)
                if PurchaseManager.isDevDistribution {
                    Button(Copy.devUnlock) {
                        model.pro.unlock()
                        model.sheet = nil
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .help(Copy.devUnlockNote)
                }
            }
            if let error = model.purchases.lastError {
                Text(error)
                    .font(BFont.meta)
                    .foregroundStyle(BColor.inkSoft)
            }
            HStack(spacing: BSpace.l) {
                Button(Copy.paywallRestore) {
                    Task {
                        await model.purchases.restore()
                        if model.pro.isPro { model.sheet = nil }
                    }
                }
                .buttonStyle(.plain)
                .font(BFont.meta)
                .foregroundStyle(BColor.inkSoft)
                Button(Copy.paywallDecline) {
                    model.settings.paywallDeclinedAt = Date()
                    Analytics.shared.log("paywall", ["trigger": trigger, "outcome": "decline"])
                    model.sheet = nil
                }
                .buttonStyle(.plain)
                .font(BFont.meta)
                .foregroundStyle(BColor.inkSoft)
            }
        }
        .padding(BSpace.xxl)
        .frame(width: 420, height: 560)
        .background(BColor.bg)
    }
}

// MARK: - Update Planner sheet

public struct UpdatePlannerSheet: View {
    @Environment(AppModel.self) private var model

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: BSpace.l) {
            if let plan = model.updatePlan {
                Text(Copy.plannerGenericTitle)
                    .font(BFont.title)
                    .foregroundStyle(BColor.ink)
                Text(Copy.plannerBody(need: ByteFormat.string(plan.neededBytes), promised: ByteFormat.string(plan.promisedBytes), minutes: plan.estimatedMinutes()))
                    .font(BFont.body)
                    .foregroundStyle(BColor.inkSoft)

                ScrollView {
                    VStack(alignment: .leading, spacing: BSpace.s) {
                        planSection(Copy.plannerReclaimSection, items: plan.reclaimItems)
                        if !plan.stashSuggestions.isEmpty {
                            planSection(Copy.plannerStashSection, items: plan.stashSuggestions)
                        }
                        if !plan.teachItems.isEmpty {
                            Text(Copy.plannerTeachSection)
                                .font(BFont.meta.weight(.semibold))
                                .foregroundStyle(BColor.inkSoft)
                                .padding(.top, BSpace.s)
                            ForEach(plan.teachItems) { item in
                                HStack(spacing: 8) {
                                    HollowBadge()
                                    Text(item.displayName)
                                        .font(BFont.meta)
                                        .foregroundStyle(BColor.ink)
                                    Spacer()
                                    Text(ByteFormat.string(item.bytes))
                                        .font(BFont.rounded(12, .medium))
                                        .foregroundStyle(BColor.inkSoft)
                                    if let flow = item.entry.teachFlow {
                                        Button(Copy.showMe) { model.sheet = .teach(flow, bytes: item.bytes) }
                                            .buttonStyle(.plain)
                                            .font(BFont.meta)
                                            .foregroundStyle(BColor.brand)
                                    }
                                }
                            }
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button(Copy.cancel) { model.sheet = nil }
                        .buttonStyle(SecondaryButtonStyle())
                    PrimaryButton(Copy.reclaimPrimary(ByteFormat.string(plan.reclaimItems.reduce(Int64(0)) { $0 + $1.bytes }))) {
                        model.planItems = plan.reclaimItems
                        model.planTitle = Copy.planRoomForUpdate
                        model.sheet = .reclaimPlan(title: model.planTitle)
                    }
                    .disabled(plan.reclaimItems.isEmpty)
                }
            }
        }
        .padding(BSpace.sheetPadding)
        .frame(width: 560, height: 480)
        .background(BColor.bg)
        .onAppear {
            if let plan = model.updatePlan {
                Analytics.shared.log("planner_run", [
                    "need": String(plan.neededBytes),
                    "freed": String(plan.promisedBytes),
                ])
            }
        }
    }

    private func planSection(_ title: String, items: [AtlasItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(BFont.meta.weight(.semibold))
                .foregroundStyle(BColor.inkSoft)
            ForEach(items) { item in
                HStack(spacing: 8) {
                    TierChip(item.entry.tier)
                    Text(item.displayName)
                        .font(BFont.meta)
                        .foregroundStyle(BColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Text(ByteFormat.string(item.bytes))
                        .font(BFont.rounded(12, .medium))
                        .foregroundStyle(BColor.inkSoft)
                }
            }
        }
    }
}

// MARK: - First-Rebuildable confirmation

