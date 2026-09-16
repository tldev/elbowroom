import SwiftUI
import StoreKit

/// Window anatomy: header 64 pt with the segmented control, Disk Strip
/// 28 pt (the app's heartbeat, visible in every view), content, and the bottom
/// tray that materializes on selection and never covers content.
public struct MainWindow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.requestReview) private var requestReview
    @FocusState private var searchFocused: Bool
    @State private var searchVisible = false

    public init() {}

    public var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            header
            DiskStrip()
                .background(BColor.bg)
                .zIndex(1)  // the hover legend card hangs over the content below
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    // The plan footer is always present (Warm Instrument):
                    // the running total is the app's working memory.
                    TrayBar()
                }
        }
        .frame(minWidth: 900, minHeight: 620)
        .background(BColor.bg)
        .fanZoomOverlay()  // lens rows in Items raise the loupe from here
        .animation(BMotion.standard, value: model.trayItems.isEmpty)
        .overlay(alignment: .bottom) { toastOverlay }
        .sheet(item: $model.sheet) { sheet in
            sheetView(sheet)
        }
        .task {
            if model.result == nil && !model.scanning && !model.loadCachedScan() {
                model.startScan()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.rescanIfSensible()
        }
        // Review prompt: once, 3 s after the first pour of 5 GB or more.
        .onChange(of: model.reclaimOutcome?.reclaimedBytes) { _, bytes in
            guard let bytes, bytes >= 5 * 1_000_000_000, !model.settings.reviewAsked else { return }
            model.settings.reviewAsked = true
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                requestReview()
            }
        }
        // Keyboard map.
        .background {
            Group {
                Button("") { model.view = .den }.keyboardShortcut("1", modifiers: .command)
                Button("") { model.view = .ledger }.keyboardShortcut("2", modifiers: .command)
                Button("") { model.view = .crossSection }.keyboardShortcut("3", modifiers: .command)
                Button("") { model.openLenses() }.keyboardShortcut("4", modifiers: .command)
                Button("") { searchVisible = true; searchFocused = true }.keyboardShortcut("f", modifiers: .command)
                Button("") { model.openReclaimPlan() }.keyboardShortcut(.delete, modifiers: .command)
                Button("") {
                    for item in model.trayItems where item.entry.stashable {
                        model.stashItem(item)
                    }
                }.keyboardShortcut("s", modifiers: .command)
            }
            .opacity(0)
            .accessibilityHidden(true)
        }
    }

    // MARK: Header (64 pt)

    private var header: some View {
        @Bindable var model = model
        return HStack(spacing: BSpace.l) {
            StrataMark()
                .frame(width: 24, height: 20)
                .accessibilityHidden(true)

            Spacer()

            SegmentedTabs(selection: $model.view)

            Spacer()

            HStack(spacing: BSpace.m) {
                if searchVisible {
                    TextField(Copy.searchPlaceholder, text: $model.searchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                        .focused($searchFocused)
                        .onSubmit { if model.searchText.isEmpty { searchVisible = false } }
                        .onExitCommand {
                            model.searchText = ""
                            searchVisible = false
                        }
                }
                headerButton("clock", help: Copy.viewChanges, active: model.view == .changes) {
                    model.view = model.view == .changes ? .den : .changes
                }
                headerButton("magnifyingglass", help: Copy.searchPlaceholder, active: searchVisible) {
                    searchVisible.toggle()
                    if searchVisible { searchFocused = true } else { model.searchText = "" }
                }
                headerButton("arrow.clockwise", help: Copy.scanAgain, active: false) {
                    model.rescanSoon()
                }
                .disabled(model.scanning)
                // The mock's title-bar theme toggle: pins light or dark;
                // the pin persists, Settings keeps no duplicate control.
                headerButton("circle.lefthalf.filled", help: Copy.themeToggleHelp, active: model.settings.themeOverride != nil) {
                    let dark = model.settings.themeOverride == "dark"
                        || (model.settings.themeOverride == nil
                            && NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
                    model.settings.themeOverride = dark ? "light" : "dark"
                }
                SettingsLink {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(BColor.inkSoft)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(Copy.settingsLabel)
            }
        }
        .padding(.horizontal, BSpace.l)
        .frame(height: 64)
        .background(BColor.bg)
    }

    private func headerButton(_ symbol: String, help: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(active ? BColor.brand : BColor.inkSoft)
                .frame(width: 30, height: 30)
                .background(active ? BColor.brand.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if model.result == nil && model.scanning {
            firstScanPlaceholder
        } else {
            // All four views stay alive; switching tabs only flips opacity.
            // The Ledger's table costs real time to build (NSTableView
            // measures every row), so it is built once, not per switch.
            ZStack {
                pane(DenView(), .den)
                pane(MapView(), .crossSection)
                pane(LedgerView(), .ledger)
                pane(ChangesView(), .changes)
            }
        }
    }

    private func pane(_ content: some View, _ tab: MainView) -> some View {
        let active = model.view == tab
        return content
            .opacity(active ? 1 : 0)
            .allowsHitTesting(active)
            .accessibilityHidden(!active)
    }

    private var firstScanPlaceholder: some View {
        VStack(spacing: BSpace.l) {
            ProgressView()
            Text("\(model.scanItemsSeen) items · \(ByteFormat.string(model.scanBytesSeen))")
                .font(BFont.meta)
                .foregroundStyle(BColor.inkSoft)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BColor.bg)
    }

    // MARK: Toast

    @ViewBuilder
    private var toastOverlay: some View {
        if let toast = model.toast {
            ToastView(toast)
                .padding(.bottom, model.trayItems.isEmpty ? BSpace.xl : 76)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task {
                    try? await Task.sleep(nanoseconds: 2_400_000_000)
                    withAnimation(BMotion.light) {
                        if model.toast?.id == toast.id { model.toast = nil }
                    }
                }
        }
    }

    // MARK: Sheets

    @ViewBuilder
    private func sheetView(_ sheet: ActiveSheet) -> some View {
        switch sheet {
        case .reclaimPlan:
            ReclaimPlanSheet()
        case .stashSetup:
            StashSetupSheet()
        case .stashCatalog:
            StashCatalogView()
        case .teach(let flow, let bytes):
            TeachFlowSheet(flowID: flow, bytes: bytes)
        case .cleanup(let entryID):
            CleanupSheet(entryID: entryID)
        case .paywall(let trigger):
            PaywallSheet(trigger: trigger)
        case .reconcile(let entry):
            ReconcileSheet(entry: entry)
        case .updatePlanner:
            UpdatePlannerSheet()
        case .askKibi(let name, let path, let bytes, let children):
            AskKibiSheet(name: name, path: path, bytes: bytes, children: children)
        }
    }
}

/// Bottom tray: 56 pt, running total, Reclaim primary, Stash when every
/// selected item is stash-blessed, Clear.
struct TrayBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let empty = model.trayItems.isEmpty
        HStack(spacing: BSpace.l) {
            Text(Copy.trayCount(model.trayItems.count, ByteFormat.string(model.trayBytes)))
                .font(BFont.body.weight(.medium))
                .foregroundStyle(empty ? BColor.inkSoft : BColor.ink)
                .contentTransition(.numericText())
            Spacer()
            if !empty {
                Button(Copy.trayClear) { model.clearTray() }
                    .buttonStyle(.plain)
                    .font(BFont.body)
                    .foregroundStyle(BColor.inkSoft)
                if model.trayAllStashable {
                    Button(Copy.trayStash) {
                        for item in model.trayItems { model.stashItem(item) }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
            Button(Copy.trayReclaim) { model.openReclaimPlan() }
                .buttonStyle(TrayPrimaryButtonStyle(enabled: !empty))
                .disabled(empty)
        }
        .padding(.horizontal, BSpace.xl)
        .frame(height: 56)
        .background(BColor.surface)
        .overlay(alignment: .top) { Divider().overlay(BColor.hair) }
        .animation(BMotion.light, value: empty)
    }
}


/// The tray's primary verb: accent-filled when armed, soil-quiet when the
/// plan is empty (Warm Instrument).
struct TrayPrimaryButtonStyle: ButtonStyle {
    var enabled = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(BFont.body.weight(.semibold))
            .foregroundStyle(enabled ? BColor.onBrand : BColor.faint)
            .padding(.horizontal, BSpace.xl)
            .frame(height: 38)
            .background(enabled ? BColor.brand : BColor.soil, in: RoundedRectangle(cornerRadius: BRadius.control))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
