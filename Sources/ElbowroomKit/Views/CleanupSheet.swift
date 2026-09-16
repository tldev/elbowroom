import SwiftUI
import AppKit

/// Cleanup sheet: the tool's own listing as checkable rows, the literal
/// commands Elbowroom will run shown beneath, one Run button. Nothing executes
/// until Run; failures land on their rows and the sheet stays open.
public struct CleanupSheet: View {
    @Environment(AppModel.self) private var model
    let entryID: String
    @State private var tool: DevTool = .simctl
    @State private var actions: [ToolAction] = []
    @State private var notes: [String] = []
    @State private var blockedReason: String?
    @State private var estimatedBytes: Int64?
    @State private var loading = true
    @State private var running = false
    @State private var failures: [String: String] = [:]
    private let fixture: Bool

    public init(entryID: String) {
        self.entryID = entryID
        fixture = false
    }

    /// Snapshot-harness variant: plan injected, nothing runs.
    public init(fixturePlan: CleanupPlan) {
        entryID = fixturePlan.entryID
        _tool = State(initialValue: fixturePlan.tool)
        _actions = State(initialValue: fixturePlan.actions)
        _notes = State(initialValue: fixturePlan.notes)
        _blockedReason = State(initialValue: fixturePlan.blockedReason)
        _estimatedBytes = State(initialValue: fixturePlan.estimatedBytes)
        _loading = State(initialValue: false)
        fixture = true
    }

    private var entry: AtlasEntry { Atlas.entry(entryID) }
    private var plan: CleanupPlan {
        CleanupPlan(tool: tool, entryID: entryID, actions: actions,
                    blockedReason: blockedReason, estimatedBytes: estimatedBytes)
    }
    private var checkedBytes: Int64 { plan.checkedBytes }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 560, height: 580)
        .background(BColor.bg)
        .onAppear {
            guard !fixture else { return }
            Task {
                let composed = await model.composeCleanupPlan(entryID: entryID)
                tool = composed.tool
                actions = composed.actions
                notes = composed.notes
                blockedReason = composed.blockedReason
                estimatedBytes = composed.estimatedBytes
                loading = false
            }
        }
    }

    private var header: some View {
        HStack(spacing: BSpace.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(BFont.title)
                    .foregroundStyle(BColor.ink)
                Text(entry.identityLine)
                    .font(BFont.meta)
                    .foregroundStyle(BColor.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button {
                model.sheet = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(BColor.inkSoft)
            }
            .buttonStyle(.plain)
        }
        .padding(BSpace.sheetPadding)
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            HStack(spacing: BSpace.s) {
                ProgressView().controlSize(.small)
                Text(Copy.cleanupListing)
                    .font(BFont.meta)
                    .foregroundStyle(BColor.inkSoft)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let blockedReason {
            VStack(spacing: BSpace.m) {
                Text(blockedReason)
                    .font(BFont.body)
                    .foregroundStyle(BColor.inkSoft)
                if let flow = entry.teachFlow {
                    Button(Copy.showMe) { model.sheet = .teach(flow, bytes: 0) }
                        .buttonStyle(SecondarySmallButtonStyle())
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if actions.isEmpty {
            // Nothing removable: say what stays, so a big row opening an
            // empty sheet reads as an explanation, not a broken promise.
            VStack(spacing: BSpace.s) {
                Text(Copy.kibiDenTidy)
                    .font(BFont.body)
                    .foregroundStyle(BColor.inkSoft)
                notesBlock
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: BSpace.s) {
                    ForEach(sections, id: \.ids[0]) { section in
                        if let title = section.title {
                            groupHeader(title, ids: section.ids)
                        }
                        ForEach(section.ids, id: \.self) { id in
                            if let i = actions.firstIndex(where: { $0.id == id }) {
                                actionRow($actions[i], grouped: section.title != nil)
                                    .padding(.leading, section.title != nil ? BSpace.xl : 0)
                            }
                        }
                    }
                    autoThinRow
                    notesBlock
                    commandBlock
                    Text(Copy.cleanupNoUndo)
                        .font(BFont.meta)
                        .foregroundStyle(BColor.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(BSpace.sheetPadding)
            }
        }
    }

    /// Consecutive same-group actions fold under one header.
    private var sections: [(title: String?, ids: [String])] {
        var out: [(title: String?, ids: [String])] = []
        for action in actions {
            if let last = out.indices.last, action.groupTitle != nil,
               out[last].title == action.groupTitle {
                out[last].ids.append(action.id)
            } else {
                out.append((action.groupTitle, [action.id]))
            }
        }
        return out
    }

    /// One checkbox for the whole set: off, mixed, or all. Checking it is the
    /// "just make it work" path; single rows below still opt out.
    private func groupHeader(_ title: String, ids: [String]) -> some View {
        let members = actions.filter { ids.contains($0.id) }
        let checkedCount = members.count(where: \.checked)
        let bytes = members.reduce(Int64(0)) { $0 + $1.bytes }
        return HStack(alignment: .firstTextBaseline, spacing: BSpace.m) {
            TriStateCheck(
                state: checkedCount == 0 ? .off : (checkedCount == members.count ? .on : .mixed)
            ) { include in
                for index in actions.indices where ids.contains(actions[index].id) {
                    actions[index].checked = include
                }
            }
            .disabled(running)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(BFont.body.weight(.semibold))
                        .foregroundStyle(BColor.ink)
                    // Zero = the tool did not say; the header stays quiet
                    // and the plan's "up to" estimate speaks instead.
                    if bytes > 0 {
                        Text(ByteFormat.string(bytes))
                            .font(BFont.rounded(12, .medium))
                            .foregroundStyle(BColor.inkSoft)
                    }
                }
                if checkedCount > 0, let warning = members.first?.warning {
                    Text(warning)
                        .font(BFont.meta)
                        .foregroundStyle(BColor.tierRebuild)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
        }
        .padding(.horizontal, BSpace.m)
        .padding(.top, BSpace.s)
    }

    /// Evolved, tmutil only: the closest thing to "off" that macOS
    /// allows. A standing consent, not a one-shot: Elbowroom deletes local
    /// snapshots whenever they hold space again. The row states the trade
    /// plainly and persists across the sheet.
    @ViewBuilder
    private var autoThinRow: some View {
        if tool == .tmutil {
            let on = model.settings.autoThinSnapshots
            Button {
                model.settings.autoThinSnapshots.toggle()
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: BSpace.m) {
                    sheetCheckbox(on: on)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Copy.tmAutoTitle)
                            .font(BFont.body.weight(.medium))
                            .foregroundStyle(BColor.ink)
                        Text(Copy.tmAutoDetail)
                            .font(BFont.meta)
                            .foregroundStyle(BColor.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
                .padding(BSpace.m)
                .background(BColor.soil)
                .clipShape(RoundedRectangle(cornerRadius: BRadius.control))
                .contentShape(RoundedRectangle(cornerRadius: BRadius.control))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Copy.tmAutoTitle)
            .accessibilityAddTraits(on ? [.isSelected] : [])
            .padding(.top, BSpace.s)
        }
    }

    @ViewBuilder
    private var notesBlock: some View {
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(notes, id: \.self) { note in
                    Text(note)
                        .font(BFont.meta)
                        .foregroundStyle(BColor.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// The whole row is the checkbox (Warm Instrument): click anywhere.
    private func actionRow(_ action: Binding<ToolAction>, grouped: Bool = false) -> some View {
        let value = action.wrappedValue
        return Button {
            action.wrappedValue.checked.toggle()
        } label: {
            actionRowLabel(value, grouped: grouped)
        }
        .buttonStyle(.plain)
        .disabled(running)
        .accessibilityAddTraits(value.checked ? [.isSelected] : [])
    }

    private func actionRowLabel(_ value: ToolAction, grouped: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: BSpace.m) {
            sheetCheckbox(on: value.checked)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(value.title)
                        .font(BFont.body.weight(.medium))
                        .foregroundStyle(BColor.ink)
                    if value.bytes > 0 {
                        Text(ByteFormat.string(value.bytes))
                            .font(BFont.rounded(12, .medium))
                            .foregroundStyle(BColor.inkSoft)
                    }
                }
                if let detail = value.detail {
                    Text(detail)
                        .font(BFont.meta)
                        .foregroundStyle(BColor.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // Grouped rows leave the warning to their header, once.
                if let warning = value.warning, value.checked, !grouped {
                    Text(warning)
                        .font(BFont.meta)
                        .foregroundStyle(BColor.tierRebuild)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let failure = failures[value.id] {
                    Text(failure)
                        .font(BFont.meta)
                        .foregroundStyle(BColor.tierYours)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
        }
        .padding(BSpace.m)
        .background(value.checked ? AnyShapeStyle(BColor.brandSoft) : AnyShapeStyle(BColor.surface))
        .clipShape(RoundedRectangle(cornerRadius: BRadius.control))
        .overlay(RoundedRectangle(cornerRadius: BRadius.control).strokeBorder(BColor.line, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: BRadius.control))
    }

    private func sheetCheckbox(on: Bool) -> some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(on ? AnyShapeStyle(BColor.brand) : AnyShapeStyle(BColor.surface))
            .overlay {
                if on {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(BColor.onBrand)
                } else {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(BColor.line, lineWidth: 1.5)
                }
            }
            .frame(width: 18, height: 18)
    }

    @ViewBuilder
    private var commandBlock: some View {
        let preview = plan.commandPreview
        if !preview.isEmpty {
            VStack(alignment: .leading, spacing: BSpace.xs) {
                Text(Copy.cleanupWillRun)
                    .font(BFont.meta.weight(.semibold))
                    .foregroundStyle(BColor.inkSoft)
                Text(preview)
                    .font(BFont.path)
                    .foregroundStyle(BColor.ink)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(BSpace.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(BColor.soil)
                    .clipShape(RoundedRectangle(cornerRadius: BRadius.control))
            }
            .padding(.top, BSpace.s)
        }
    }

    private var footer: some View {
        HStack {
            Button(Copy.copyCommand) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(plan.commandPreview, forType: .string)
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(plan.checkedActions.isEmpty)
            Spacer()
            if running {
                ProgressView().controlSize(.small)
                    .padding(.trailing, BSpace.s)
            }
            PrimaryButton(runLabel) { run() }
                .disabled(running || plan.checkedActions.isEmpty || fixture)
                .opacity(plan.checkedActions.isEmpty ? 0.5 : 1)
        }
        .padding(BSpace.sheetPadding)
    }

    /// "Run (12.4 GB)" when rows carry sizes; "Run (up to 38 GB)" when the
    /// tool did not say and the plan carries an estimate instead.
    private var runLabel: String {
        if checkedBytes == 0, let estimatedBytes, !plan.checkedActions.isEmpty {
            return Copy.runItUpTo(ByteFormat.string(estimatedBytes))
        }
        return Copy.runIt(ByteFormat.string(checkedBytes))
    }

    private func run() {
        running = true
        failures = [:]
        let current = plan
        Task {
            let fails = await model.runCleanup(current)
            if fails.isEmpty {
                model.sheet = nil
            } else {
                failures = fails
                // Completed rows leave the list; failed ones stay checked.
                actions = actions.filter { fails[$0.id] != nil || !$0.checked }
                running = false
            }
        }
    }
}

/// Group checkbox with an honest middle: off, mixed (some rows), on (all).
/// Clicking from mixed selects the whole set.
struct TriStateCheck: View {
    enum GroupState { case off, mixed, on }
    let state: GroupState
    let onToggle: (Bool) -> Void

    var body: some View {
        Button {
            onToggle(state != .on)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(state == .off ? BColor.inkSoft : BColor.ink)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(state == .on ? [.isSelected] : [])
    }

    private var symbol: String {
        switch state {
        case .off: "square"
        case .mixed: "minus.square.fill"
        case .on: "checkmark.square.fill"
        }
    }
}
