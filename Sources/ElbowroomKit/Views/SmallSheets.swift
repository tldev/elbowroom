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
        if flowID == .docker {
            CleanupSheet(entryID: "docker.data")
        } else {
            teachBody
        }
    }

    private var teachBody: some View {
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

            if let figure {
                Image(nsImage: figure)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: BRadius.control))
                    .overlay(
                        RoundedRectangle(cornerRadius: BRadius.control)
                            .strokeBorder(BColor.line, lineWidth: 1)
                    )
            }

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
        .frame(width: 520, height: sheetHeight)
        .background(BColor.bg)
    }

    /// The figure scales to the sheet's inner width; its height rides along.
    private var sheetHeight: CGFloat {
        if let figure { return 296 + figure.size.height * 472 / figure.size.width }
        return flow.command == nil ? 300 : 420
    }

    private var figure: NSImage? {
        guard let base = flow.figure, let url = TeachFigures.url(base) else { return nil }
        return NSImage(contentsOf: url)
    }

    private func openDoor() {
        switch flowID {
        case .simulatorRuntimes:
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Xcode.app"))
        case .sharedWithYou:
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Messages.app"))
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
                        // Replace this sheet (not stack under the plan),
                        // through the one entry that resets stale run state.
                        model.sheet = nil
                        model.openReclaimPlan(items: plan.reclaimItems, title: Copy.planRoomForUpdate)
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
