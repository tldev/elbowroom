import SwiftUI

// MARK: - Stash setup sheet

public struct StashSetupSheet: View {
    @Environment(AppModel.self) private var model
    @State private var volumes: [ExternalVolume] = []
    @State private var picked: ExternalVolume?
    @State private var speed: SpeedTest.Result?
    @State private var testing = false
    @State private var tmDecided = false
    @State private var errorLine: String?
    private let fixture: Bool

    public init() {
        fixture = false
    }

    /// State-injected variant for snapshot harness, mirroring
    /// LedgerView(initialSelection:).
    public init(fixtureVolumes: [ExternalVolume], picked: ExternalVolume?, speed: SpeedTest.Result?) {
        fixture = true
        _volumes = State(initialValue: fixtureVolumes)
        _picked = State(initialValue: picked)
        _speed = State(initialValue: speed)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BSpace.l) {
            Text(Copy.stashSetupTitle)
                .font(BFont.title)
                .foregroundStyle(BColor.ink)
            Text(Copy.stashSetupBody)
                .font(BFont.body)
                .foregroundStyle(BColor.inkSoft)

            if volumes.isEmpty {
                HStack(spacing: BSpace.m) {
                    Image(systemName: "externaldrive.badge.questionmark")
                        .font(.system(size: 28))
                        .foregroundStyle(BColor.inkSoft)
                    Text(Copy.stashNoDrives)
                        .font(BFont.body)
                        .foregroundStyle(BColor.inkSoft)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                volumeList
            }

            if let picked, picked.eligible {
                speedSection(picked)
            }
            if let errorLine {
                Text(errorLine)
                    .font(BFont.meta)
                    .foregroundStyle(BColor.tierYours)
            }
            Spacer()
            footer
        }
        .padding(BSpace.sheetPadding)
        .frame(width: 520, height: 500)
        .background(BColor.bg)
        .onAppear {
            guard !fixture else { return }
            // Enumerating volumes stats each one; a stalled drive would hang
            // the sheet if this ran on the render thread.
            Task.detached(priority: .userInitiated) {
                let found = ExternalVolume.mounted()
                await MainActor.run { volumes = found }
            }
        }
    }

    private var volumeList: some View {
        VStack(spacing: BSpace.s) {
            ForEach(volumes) { volume in
                Button {
                    guard volume.eligible else { return }
                    picked = volume
                    speed = nil
                    runSpeedTest(volume)
                } label: {
                    HStack(spacing: BSpace.m) {
                        Image(systemName: "externaldrive.fill")
                            .foregroundStyle(volume.eligible ? BColor.brand : BColor.inkSoft)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(volume.name)
                                .font(BFont.body.weight(.medium))
                                .foregroundStyle(BColor.ink)
                            // Excluded rows say why.
                            Text(volume.ineligibleReason ?? "\(ByteFormat.string(volume.available)) free of \(ByteFormat.string(volume.totalCapacity))")
                                .font(BFont.meta)
                                .foregroundStyle(BColor.inkSoft)
                        }
                        Spacer()
                        if picked?.id == volume.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(BColor.brand)
                        }
                    }
                    .padding(BSpace.m)
                    .background(BColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: BRadius.control))
                    .overlay(
                        RoundedRectangle(cornerRadius: BRadius.control)
                            .strokeBorder(picked?.id == volume.id ? BColor.brand.opacity(0.6) : BColor.line, lineWidth: 1)
                    )
                    .opacity(volume.eligible ? 1 : 0.55)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func speedSection(_ volume: ExternalVolume) -> some View {
        if testing {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(Copy.stashMeasuring)
                    .font(BFont.meta)
                    .foregroundStyle(BColor.inkSoft)
            }
        } else if let speed {
            VStack(alignment: .leading, spacing: BSpace.m) {
                Label(speed.line, systemImage: speed.fastEnoughForBuilds ? "hare" : "tortoise")
                    .font(BFont.body)
                    .foregroundStyle(BColor.ink)
                // Time Machine card: recommend exclude, one click either way,
                // never silent.
                if !tmDecided {
                    VStack(alignment: .leading, spacing: BSpace.s) {
                        Text(Copy.tmCard)
                            .font(BFont.meta)
                            .foregroundStyle(BColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button(Copy.tmExclude) { decideTM(exclude: true) }
                                .buttonStyle(SecondarySmallButtonStyle())
                            Button(Copy.tmInclude) { decideTM(exclude: false) }
                                .buttonStyle(.plain)
                                .font(BFont.meta)
                                .foregroundStyle(BColor.inkSoft)
                        }
                    }
                    .bCard()
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button(Copy.cancel) { model.sheet = nil }
                .buttonStyle(SecondaryButtonStyle())
            PrimaryButton(Copy.stashCreate) { create() }
                .disabled(picked == nil || speed == nil)
                .opacity(picked == nil || speed == nil ? 0.5 : 1)
        }
    }

    private func runSpeedTest(_ volume: ExternalVolume) {
        testing = true
        Task {
            let result = await SpeedTest.run(on: volume.url)
            self.speed = result
            self.testing = false
            Analytics.shared.log("stash_setup", ["speedTier": result.fastEnoughForBuilds ? "fast" : "slow"])
        }
    }

    private func decideTM(exclude: Bool) {
        tmDecided = true
        guard exclude, let picked else { return }
        // Best effort; tmutil may need elevated rights, and silence would lie.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        p.arguments = ["addexclusion", picked.url.appendingPathComponent("Stash").path]
        try? p.run()
    }

    private func create() {
        guard let picked else { return }
        do {
            try model.adoptStash(volume: picked.url)
            model.sheet = .stashCatalog
        } catch {
            errorLine = error.localizedDescription
        }
    }
}

// MARK: - Stash catalog

/// One Atlas category in the catalog: its live items plus manifest entries
/// whose source became a symlink after a rescan. Categories with several
/// locations collapse to one row with a group toggle.
struct CatalogGroup: Identifiable {
    let entryID: String
    var items: [AtlasItem]
    var ghosts: [StashEntry]

    var id: String { entryID }
    var count: Int { items.count + ghosts.count }
    var totalBytes: Int64 {
        items.reduce(0) { $0 + $1.bytes } + ghosts.reduce(0) { $0 + $1.bytes }
    }
    var stashedBytes: Int64 {
        items.filter(\.isStashed).reduce(0) { $0 + $1.bytes }
            + ghosts.reduce(0) { $0 + $1.bytes }
    }
    var allStashed: Bool { items.allSatisfy(\.isStashed) }
    var title: String { Atlas.entry(entryID).title }
    var soleItem: AtlasItem? { count == 1 ? items.first : nil }
    var soleGhost: StashEntry? { count == 1 ? ghosts.first : nil }

    static func build(items: [AtlasItem], ghosts: [StashEntry]) -> [CatalogGroup] {
        var byEntry: [String: CatalogGroup] = [:]
        var order: [String] = []
        for item in items {
            if byEntry[item.entryID] == nil {
                byEntry[item.entryID] = CatalogGroup(entryID: item.entryID, items: [], ghosts: [])
                order.append(item.entryID)
            }
            byEntry[item.entryID]?.items.append(item)
        }
        for ghost in ghosts {
            if byEntry[ghost.entryID] == nil {
                byEntry[ghost.entryID] = CatalogGroup(entryID: ghost.entryID, items: [], ghosts: [])
                order.append(ghost.entryID)
            }
            byEntry[ghost.entryID]?.ghosts.append(ghost)
        }
        for key in order { byEntry[key]?.ghosts.sort { $0.bytes > $1.bytes } }
        return order.compactMap { byEntry[$0] }.sorted {
            $0.totalBytes == $1.totalBytes ? $0.entryID < $1.entryID : $0.totalBytes > $1.totalBytes
        }
    }
}

public struct StashCatalogView: View {
    @Environment(AppModel.self) private var model
    @State private var expanded: Set<String>

    public init(initiallyExpanded: Set<String> = []) {
        _expanded = State(initialValue: initiallyExpanded)
    }

    /// Only Atlas-blessed movables appear; rebuildable project folders
    /// only where staleness > 30 days.
    private var catalog: [AtlasItem] {
        let cutoff = Date().addingTimeInterval(-30 * 86_400)
        return model.items.filter { item in
            guard item.entry.stashable else { return false }
            if item.entry.tier == .rebuildable, item.projectName != nil {
                return (item.lastTouched ?? .distantPast) < cutoff || item.isStashed
            }
            return true
        }
        .sorted { $0.bytes > $1.bytes }
    }

    private var stashedEntries: [StashEntry] {
        model.stash?.manifest.entries.filter { $0.status != .retired } ?? []
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if model.stash == nil {
                EmptyStateView(Copy.kibiStashEmpty, symbol: "externaldrive")
            } else {
                list
            }
            Divider()
            footer
        }
        .frame(width: 620, height: 540)
        .background(BColor.bg)
    }

    private var header: some View {
        HStack(spacing: BSpace.m) {
            Text(Copy.stashTitle)
                .font(BFont.title)
                .foregroundStyle(BColor.ink)
            if let stash = model.stash {
                Text(Copy.stashOn(stash.volumeName, ByteFormat.string(stash.stashedBytes)))
                    .font(BFont.meta)
                    .foregroundStyle(BColor.inkSoft)
                if !stash.volumeIsPresent {
                    Label(Copy.stashNotConnected, systemImage: "bolt.horizontal.circle")
                        .font(BFont.meta)
                        .foregroundStyle(BColor.tierRebuild)
                }
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

    /// After a rescan a moved folder is a symlink and leaves the item list;
    /// the manifest keeps its row here so the toggle back always exists.
    private var ghosts: [StashEntry] {
        let catalogPaths = Set(catalog.map { $0.url.path })
        return stashedEntries.filter {
            ($0.status == .done) && !catalogPaths.contains($0.sourcePath)
        }
    }

    private var groups: [CatalogGroup] {
        CatalogGroup.build(items: catalog, ghosts: ghosts)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: BSpace.s) {
                if catalog.isEmpty && stashedEntries.isEmpty {
                    EmptyStateView(Copy.kibiStashEmpty, symbol: "externaldrive")
                        .frame(height: 300)
                }
                ForEach(groups) { group in
                    if let item = group.soleItem {
                        catalogRow(item)
                    } else if let ghost = group.soleGhost {
                        manifestRow(ghost)
                    } else {
                        groupRows(group)
                    }
                }
                toolManagedRows
                dirtyRows
            }
            .padding(BSpace.sheetPadding)
        }
    }

    @ViewBuilder
    private func groupRows(_ group: CatalogGroup) -> some View {
        groupRow(group)
        if expanded.contains(group.entryID) {
            ForEach(group.items) { catalogRow($0, grouped: true) }
            ForEach(group.ghosts) { manifestRow($0, grouped: true) }
        }
    }

    private func groupRow(_ group: CatalogGroup) -> some View {
        let isOpen = expanded.contains(group.entryID)
        let blocker = StashManager.runningBlocker(for: group.entryID)
        let reason: String? = {
            if let blocker { return Copy.ineligibleRunning(blocker) }
            if model.stash?.volumeIsPresent == false { return Copy.stashConnectFirst(model.stash?.volumeName ?? "?") }
            return nil
        }()
        let partial = group.stashedBytes > 0 && !group.allStashed

        return HStack(spacing: BSpace.l) {
            Button {
                withAnimation(BMotion.light) {
                    if isOpen { expanded.remove(group.entryID) } else { expanded.insert(group.entryID) }
                }
            } label: {
                HStack(spacing: BSpace.s) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(BColor.inkSoft)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.title)
                            .font(BFont.body.weight(.medium))
                            .foregroundStyle(BColor.ink)
                        HStack(spacing: 8) {
                            if partial {
                                Text(Copy.stashGroupPartial(
                                    ByteFormat.string(group.stashedBytes),
                                    ByteFormat.string(group.totalBytes)
                                ))
                                .font(BFont.rounded(12, .medium))
                                .foregroundStyle(BColor.inkSoft)
                            } else {
                                Text(ByteFormat.string(group.totalBytes))
                                    .font(BFont.rounded(12, .medium))
                                    .foregroundStyle(BColor.inkSoft)
                            }
                            Text(Copy.stashGroupCount(group.count))
                                .font(BFont.meta)
                                .foregroundStyle(BColor.inkSoft)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
            StashToggle(
                isStashed: group.allStashed,
                progress: groupProgress(group),
                disabledReason: reason
            ) {
                if group.allStashed {
                    var ids = group.ghosts.map(\.id)
                    ids += group.items.compactMap { item in
                        stashedEntries.first { $0.sourcePath == item.url.path }?.id
                    }
                    model.bringHomeEntries(ids)
                } else {
                    model.stashItems(group.items.filter { !$0.isStashed })
                }
            }
        }
        .padding(BSpace.m)
        .background(BColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: BRadius.control))
        .overlay(RoundedRectangle(cornerRadius: BRadius.control).strokeBorder(BColor.line, lineWidth: 1))
    }

    /// Runtimes cannot move through the file system, but 20 GB does
    /// not get to hide from the catalog. Their row carries the tool door
    /// instead of a toggle.
    @ViewBuilder
    private var toolManagedRows: some View {
        if let item = model.items.first(where: { $0.entryID == "xcode.simRuntimes" }) {
            HStack(spacing: BSpace.l) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName)
                        .font(BFont.body.weight(.medium))
                        .foregroundStyle(BColor.ink)
                    HStack(spacing: 8) {
                        Text(ByteFormat.string(item.bytes))
                            .font(BFont.rounded(12, .medium))
                            .foregroundStyle(BColor.inkSoft)
                        Text(Copy.runtimeCatalogLine)
                            .font(BFont.meta)
                            .foregroundStyle(BColor.inkSoft)
                    }
                }
                Spacer()
                Button(Copy.cleanUp) { model.sheet = .cleanup(entryID: item.entryID) }
                    .buttonStyle(SecondarySmallButtonStyle())
                    .accessibilityLabel(Copy.cleanUp)
            }
            .padding(BSpace.m)
            .background(BColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: BRadius.control))
            .overlay(RoundedRectangle(cornerRadius: BRadius.control).strokeBorder(BColor.line, lineWidth: 1))
        }
    }

    /// Mean progress across the group's in-flight moves; nil when idle.
    private func groupProgress(_ group: CatalogGroup) -> Double? {
        let values = group.items.filter { model.stashBusy.contains($0.id) }
            .map { itemProgress($0) ?? 0.05 }
        guard !values.isEmpty else { return nil }
        return max(0.05, values.reduce(0, +) / Double(values.count))
    }

    private func manifestRow(_ entry: StashEntry, grouped: Bool = false) -> some View {
        HStack(spacing: BSpace.l) {
            VStack(alignment: .leading, spacing: 2) {
                Text(grouped ? groupedGhostLabel(entry) : entry.displayName)
                    .font(BFont.body.weight(.medium))
                    .foregroundStyle(BColor.ink)
                HStack(spacing: 8) {
                    Text(ByteFormat.string(entry.bytes))
                        .font(BFont.rounded(12, .medium))
                        .foregroundStyle(BColor.inkSoft)
                    Text(Copy.stashMovedAgo(RelativeDate.short(entry.movedAt)))
                        .font(BFont.meta)
                        .foregroundStyle(BColor.inkSoft)
                    if grouped {
                        Text(pathLabel(entry.sourcePath))
                            .font(BFont.meta)
                            .foregroundStyle(BColor.inkSoft.opacity(0.8))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            Spacer()
            StashToggle(
                isStashed: true,
                progress: model.stash?.progress[entry.id],
                disabledReason: model.stash?.volumeIsPresent == false
                    ? Copy.stashConnectFirst(model.stash?.volumeName ?? "?") : nil
            ) {
                model.bringHome(entryID: entry.id)
            }
        }
        .padding(BSpace.m)
        .background(BColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: BRadius.control))
        .overlay(RoundedRectangle(cornerRadius: BRadius.control).strokeBorder(BColor.line, lineWidth: 1))
        .padding(.leading, grouped ? BSpace.xl : 0)
    }

    /// Child rows inside a group: the repo name when known, else the parent
    /// folder name, with the abbreviated path alongside.
    private func groupedItemLabel(_ item: AtlasItem) -> String {
        if let project = item.projectName { return project }
        let parent = item.url.deletingLastPathComponent().lastPathComponent
        return parent.isEmpty ? item.url.lastPathComponent : parent
    }

    private func groupedGhostLabel(_ entry: StashEntry) -> String {
        let title = Atlas.entry(entry.entryID).title
        if entry.displayName != title { return entry.displayName }
        let parent = URL(fileURLWithPath: entry.sourcePath).deletingLastPathComponent().lastPathComponent
        return parent.isEmpty ? entry.displayName : parent
    }

    private func pathLabel(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard path.hasPrefix(home) else { return path }
        return "~" + path.dropFirst(home.count)
    }

    /// Live progress for an item mid-move, keyed through its manifest entry.
    private func itemProgress(_ item: AtlasItem) -> Double? {
        model.stash?.progress.first { entryID, _ in
            model.stash?.manifest.entries.first(where: { $0.id == entryID })?.sourcePath == item.url.path
        }?.value
    }

    private func catalogRow(_ item: AtlasItem, grouped: Bool = false) -> some View {
        let busy = model.stashBusy.contains(item.id)
        let entry = stashedEntries.first { $0.sourcePath == item.url.path }
        let progress: Double? = busy ? (itemProgress(item) ?? 0.05) : nil
        let blocker = StashManager.runningBlocker(for: item.entryID)
        let reason: String? = {
            if let blocker { return Copy.ineligibleRunning(blocker) }
            if model.stash?.volumeIsPresent == false { return Copy.stashConnectFirst(model.stash?.volumeName ?? "?") }
            return nil
        }()

        return HStack(spacing: BSpace.l) {
            VStack(alignment: .leading, spacing: 2) {
                Text(grouped ? groupedItemLabel(item) : item.displayName)
                    .font(BFont.body.weight(.medium))
                    .foregroundStyle(BColor.ink)
                HStack(spacing: 8) {
                    Text(ByteFormat.string(item.bytes))
                        .font(BFont.rounded(12, .medium))
                        .foregroundStyle(BColor.inkSoft)
                    if item.lastTouched != nil {
                        Text(RelativeDate.staleness(item.lastTouched))
                            .font(BFont.meta)
                            .foregroundStyle(BColor.inkSoft)
                    }
                    if grouped {
                        Text(pathLabel(item.url.path))
                            .font(BFont.meta)
                            .foregroundStyle(BColor.inkSoft.opacity(0.8))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            Spacer()
            StashToggle(
                isStashed: item.isStashed,
                progress: progress,
                disabledReason: reason
            ) {
                if item.isStashed {
                    if let entry { model.bringHome(entryID: entry.id) }
                } else {
                    model.stashItem(item)
                }
            }
        }
        .padding(BSpace.m)
        .background(BColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: BRadius.control))
        .overlay(RoundedRectangle(cornerRadius: BRadius.control).strokeBorder(BColor.line, lineWidth: 1))
        .opacity(reason == nil || item.isStashed ? 1 : 0.75)
        .padding(.leading, grouped ? BSpace.xl : 0)
    }

    /// DONE-DIRTY entries: space not yet freed; banner offers retry.
    @ViewBuilder
    private var dirtyRows: some View {
        let dirty = stashedEntries.filter { $0.status == .doneDirty }
        ForEach(dirty) { entry in
            HStack(spacing: BSpace.m) {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(BColor.tierRebuild)
                Text(Copy.stashDirtyBanner(entry.displayName))
                    .font(BFont.meta)
                    .foregroundStyle(BColor.ink)
                Spacer()
                Button(Copy.tryAgain) { model.stash?.retryClean(entry.id) }
                    .buttonStyle(SecondarySmallButtonStyle())
            }
            .padding(BSpace.m)
            .background(BColor.tierRebuild.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: BRadius.control))
        }
    }

    private var footer: some View {
        HStack {
            if model.stash != nil {
                Button(Copy.offboarding) { offboard() }
                    .buttonStyle(.plain)
                    .font(BFont.meta)
                    .foregroundStyle(BColor.inkSoft)
                    .help(Copy.offboardHelp)
            }
            Spacer()
            Text(Copy.toggleTooltip)
                .font(BFont.meta)
                .foregroundStyle(BColor.inkSoft)
        }
        .padding(BSpace.sheetPadding)
    }

    private func offboard() {
        guard let stash = model.stash else { return }
        Task {
            do {
                try await stash.bringEverythingHome { name in
                    Task { @MainActor in
                        self.model.toast = Toast(text: Copy.bringingHome(name))
                    }
                }
                self.model.toast = Toast(text: Copy.offboardingDone)
                self.model.rescanSoon()
            } catch {
                self.model.toast = Toast(text: (error as? LocalizedError)?.errorDescription ?? Copy.moveFail)
            }
        }
    }
}

// MARK: - Reconcile sheet

public struct ReconcileSheet: View {
    @Environment(AppModel.self) private var model
    let entry: StashEntry
    @State private var working = false

    public init(entry: StashEntry) { self.entry = entry }

    public var body: some View {
        VStack(alignment: .leading, spacing: BSpace.l) {
            Text(Copy.reconcileTitle(entry.displayName))
                .font(BFont.title)
                .foregroundStyle(BColor.ink)
            Text(Copy.reconcileBody)
                .font(BFont.body)
                .foregroundStyle(BColor.inkSoft)

            HStack(spacing: BSpace.l) {
                versionCard(
                    title: Copy.reconcileLocalSide,
                    bytes: sizeOf(path: entry.sourcePath),
                    date: modDate(path: entry.sourcePath),
                    badge: Copy.reconcileNewer
                )
                versionCard(
                    title: Copy.reconcileStashSide,
                    bytes: entry.bytes,
                    date: entry.movedAt,
                    badge: nil
                )
            }

            Spacer()
            if working {
                ProgressView(Copy.reconcileMerging)
                    .frame(maxWidth: .infinity)
            } else {
                HStack {
                    Button(Copy.reconcileKeepLocal) {
                        model.stash?.reconcileKeepLocal(entry.id)
                        model.guardian.refresh()
                        model.sheet = nil
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    Spacer()
                    PrimaryButton(Copy.reconcilePrimary) { merge() }
                }
            }
        }
        .padding(BSpace.sheetPadding)
        .frame(width: 520, height: 380)
        .background(BColor.bg)
    }

    private func versionCard(title: String, bytes: Int64, date: Date?, badge: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(BFont.meta.weight(.semibold))
                    .foregroundStyle(BColor.inkSoft)
                if let badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(BColor.brand)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(BColor.brand.opacity(0.15), in: Capsule())
                }
            }
            Text(ByteFormat.string(bytes))
                .font(BFont.rounded(22, .bold))
                .foregroundStyle(BColor.ink)
            if let date {
                Text(RelativeDate.short(date))
                    .font(BFont.meta)
                    .foregroundStyle(BColor.inkSoft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .bCard()
    }

    private func sizeOf(path: String) -> Int64 {
        var total: Int64 = 0
        let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey], options: []
        )
        while let obj = enumerator?.nextObject() {
            guard let url = obj as? URL,
                  let size = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize
            else { continue }
            total += Int64(size)
        }
        return total
    }

    private func modDate(path: String) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date
    }

    private func merge() {
        working = true
        Task {
            do {
                try await model.stash?.reconcileMergingLocal(entry.id)
                self.model.guardian.refresh()
                self.model.sheet = nil
            } catch {
                self.model.toast = Toast(text: (error as? LocalizedError)?.errorDescription ?? Copy.moveFail)
                self.model.sheet = nil
            }
        }
    }
}
