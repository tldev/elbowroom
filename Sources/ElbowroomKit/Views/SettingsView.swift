import SwiftUI
import AppKit

/// Settings (Warm Instrument): centered pill tabs over card-styled panes.
public struct ElbowroomSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var tab = 0

    public init() {}

    private var tabs: [String] {
        [Loc.t("General"), Loc.t("Receipts"), Loc.t("Privacy")]
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(Array(tabs.enumerated()), id: \.offset) { index, label in
                    Button {
                        withAnimation(BMotion.light) { tab = index }
                    } label: {
                        Text(label)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(tab == index ? BColor.ink : BColor.inkSoft)
                            .padding(.horizontal, 14)
                            .frame(height: 28)
                            .background {
                                if tab == index {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(BColor.surface)
                                        .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                                }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(tab == index ? [.isSelected] : [])
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) { Divider().overlay(BColor.hair) }
            Group {
                switch tab {
                case 0: GeneralPane()
                case 1: ReceiptsPane()
                default: PrivacyPane()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 540, height: 460)
        .background(BColor.bg)
    }
}

struct GeneralPane: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Loc.overrideKey) private var langOverride = ""

    var body: some View {
        @Bindable var settings = model.settings
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(spacing: 0) {
                    settingsRow(Loc.t("Language")) {
                        Picker("", selection: $langOverride) {
                            Text(Copy.themeFollowSystem).tag("")
                            Text("English").tag("en")
                            Text("日本語").tag("ja")
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    Divider().overlay(BColor.hair)
                    settingsRow(Loc.t("Play sounds")) {
                        Toggle("", isOn: $settings.soundsOn)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                    Divider().overlay(BColor.hair)
                    settingsRow(Copy.keepInTrashLabel) {
                        Toggle("", isOn: $settings.keepInTrashDefault)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                    Divider().overlay(BColor.hair)
                    settingsRow(Loc.t("Low-space alert")) {
                        HStack(spacing: 10) {
                            Slider(value: Binding(
                                get: { Double(settings.freeSpaceThresholdGB) },
                                set: { settings.freeSpaceThresholdGB = Int($0) }
                            ), in: 5...50, step: 5)
                            .frame(width: 160)
                            Text(Loc.f("%d GB free", settings.freeSpaceThresholdGB))
                                .font(BFont.meta)
                                .monospacedDigit()
                                .foregroundStyle(BColor.inkSoft)
                                .frame(width: 72, alignment: .trailing)
                        }
                    }
                    Divider().overlay(BColor.hair)
                    settingsRow(Loc.t("Connection speed")) {
                        HStack(spacing: 10) {
                            Text("\(ByteFormat.rate(settings.connectionBytesPerSecond))/s")
                                .font(BFont.meta)
                                .monospacedDigit()
                                .foregroundStyle(BColor.inkSoft)
                            Button(Loc.t("Measure Again")) {
                                Task {
                                    if let bps = await SpeedTest.sampleConnection() {
                                        settings.connectionBytesPerSecond = bps
                                        settings.connectionMeasuredAt = Date()
                                    }
                                }
                            }
                            .buttonStyle(RowActionButtonStyle())
                        }
                    }
                }
                .background(BColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(BColor.hair, lineWidth: 1))
                if langOverride != Loc.lang && !(langOverride.isEmpty && Loc.lang == Loc.detect()) {
                    Text(Loc.t("Takes effect after Elbowroom reopens."))
                        .font(BFont.meta)
                        .foregroundStyle(BColor.inkSoft)
                        .padding(.horizontal, 4)
                        .padding(.top, 10)
                }
                Text(Copy.keepInTrashNote)
                    .font(BFont.meta)
                    .foregroundStyle(BColor.inkSoft)
                    .padding(.horizontal, 4)
                    .padding(.top, 12)
                Text(Loc.t("The connection speed only phrases re-download times. Nothing uploads."))
                    .font(BFont.meta)
                    .foregroundStyle(BColor.inkSoft)
                    .padding(.horizontal, 4)
                    .padding(.top, 12)
            }
            .padding(BSpace.xl)
        }
        .background(BColor.bg)
    }

    private func settingsRow(_ label: String, @ViewBuilder control: () -> some View) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13.5))
                .foregroundStyle(BColor.ink)
            Spacer()
            control()
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 46)
    }
}

struct ReceiptsPane: View {
    @Environment(AppModel.self) private var model
    @State private var restored: UUID?

    var body: some View {
        VStack(spacing: 0) {
            if model.receipts.receipts.isEmpty {
                EmptyStateView(Copy.kibiReceiptsEmpty, symbol: "list.bullet.rectangle")
            } else {
                List {
                    ForEach(model.receipts.receipts.reversed()) { receipt in
                        receiptRow(receipt)
                    }
                }
                .listStyle(.inset)
                HStack {
                    Text(Copy.lifetime(ByteFormat.string(model.receipts.lifetimeBytes)))
                        .font(BFont.meta)
                        .foregroundStyle(BColor.inkSoft)
                    Spacer()
                    Button(Copy.exportCSV) { exportCSV() }
                        .controlSize(.small)
                }
                .padding()
            }
        }
    }

    private func receiptRow(_ receipt: Receipt) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(receipt.date.formatted(date: .abbreviated, time: .shortened))
                    .font(BFont.body.weight(.medium))
                Spacer()
                Text(ByteFormat.string(receipt.totalBytes))
                    .font(BFont.rounded(13, .semibold))
                statusBadge(receipt)
            }
            ForEach(receipt.items.prefix(4)) { item in
                HStack(spacing: 6) {
                    TierChip(item.tier)
                    Text(item.name)
                        .font(BFont.meta)
                        .foregroundStyle(BColor.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Text(ByteFormat.string(item.bytes))
                        .font(BFont.meta)
                        .foregroundStyle(BColor.inkSoft)
                }
            }
            if receipt.items.count > 4 {
                Text(Loc.f("and %d more", receipt.items.count - 4))
                    .font(BFont.meta)
                    .foregroundStyle(BColor.inkSoft)
            }
            if receipt.restoreStatus == .inTrash {
                Button(Copy.putBack) {
                    Task {
                        if await model.receipts.restore(receipt) { model.rescanSoon() }
                    }
                }
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func statusBadge(_ receipt: Receipt) -> some View {
        let text: String = switch receipt.restoreStatus {
        case .inTrash: Loc.t("in Trash")
        case .emptied: Loc.t("emptied")
        case .restored: Loc.t("restored")
        case .deletedNow: Loc.t("deleted")
        }
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(BColor.inkSoft)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(BColor.soil, in: Capsule())
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "elbowroom-receipts.csv"
        if panel.runModal() == .OK, let url = panel.url {
            try? model.receipts.exportCSV().write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

struct PrivacyPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Text(Copy.b2Body)
                .font(BFont.body)
                .foregroundStyle(BColor.ink)
            Toggle(Loc.t("Share anonymous usage statistics"), isOn: $settings.analyticsOptIn)
            Text(Loc.t("Aggregates only: event names, byte counts, durations. No paths, no file names, no device fingerprint. Stored locally where you can read them."))
                .font(BFont.meta)
                .foregroundStyle(BColor.inkSoft)
            LabeledContent(Copy.askKibi) {
                Text(AskKibi.isAvailable ? Copy.askKibiReady : Copy.askKibiOff)
                    .font(BFont.meta)
                    .foregroundStyle(BColor.inkSoft)
                    .multilineTextAlignment(.trailing)
            }
            Button(Loc.t("Show the local analytics file")) {
                let url = ReceiptStore.defaultDirectory().appendingPathComponent("analytics-local.json")
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }

            LabeledContent(Copy.fdaTitle) {
                if fdaGranted {
                    Text(Copy.fdaGranted)
                        .font(BFont.meta)
                        .foregroundStyle(BColor.inkSoft)
                } else {
                    Button(Copy.fdaOpen) {
                        DiskAccess.openFullDiskSettings()
                    }
                }
            }
            Text(Copy.fdaLine)
                .font(BFont.meta)
                .foregroundStyle(BColor.inkSoft)
                .onAppear { probeFDA() }
        }
        .formStyle(.grouped)
        .padding()
    }

    @State private var fdaGranted = false

    /// TCC has no query API; reading a protected folder is the honest probe.
    private func probeFDA() {
        Task.detached(priority: .utility) {
            let granted = DiskAccess.fdaGranted()
            await MainActor.run { fdaGranted = granted }
        }
    }
}

// MARK: - About (Kibi waves once)

public struct AboutView: View {
    @Environment(AppModel.self) private var model

    public init() {}

    public var body: some View {
        VStack(spacing: BSpace.l) {
            StrataMark()
                .frame(width: 56, height: 44)
            Text("Elbowroom")
                .font(BFont.title)
                .foregroundStyle(BColor.ink)
            Text(Copy.roomToBuild)
                .font(BFont.body)
                .foregroundStyle(BColor.inkSoft)
            if model.receipts.lifetimeBytes > 0 {
                Text(Copy.lifetime(ByteFormat.string(model.receipts.lifetimeBytes)))
                    .font(BFont.meta)
                    .foregroundStyle(BColor.inkSoft)
            }
            Text(Loc.t("1.0 · made with unreasonable care"))
                .font(.system(size: 10))
                .foregroundStyle(BColor.inkSoft.opacity(0.7))
        }
        .padding(BSpace.xxl)
        .frame(width: 320, height: 340)
        .background(BColor.bg)
    }
}

// MARK: - Steward menu

public struct StewardMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let disk = model.result?.disk {
                Text(Copy.freeAmount(ByteFormat.string(disk.available)))
                    .font(BFont.meta)
            }
            Button(Copy.stewardOpen) {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }
            Button(Copy.stewardReclaimable(ByteFormat.string(model.solidReclaimable))) {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
                model.openReclaimPlan(items: model.crisisPlan())
            }
            Divider()
            Button(Copy.stewardPause) {
                model.settings.stewardPausedUntil = Date().addingTimeInterval(3 * 86_400)
            }
            Button(Copy.stewardQuit) { NSApp.terminate(nil) }
        }
    }
}
