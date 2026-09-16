import SwiftUI

/// The Ledger: the dense truth table and the accessibility backbone.
/// Full parity with the Cross-Section by design; VoiceOver's canonical surface.
public struct LedgerView: View {
    @Environment(AppModel.self) private var model
    @State private var hoveredID: LedgerRow.ID?
    @State private var sortField: LedgerSort = .size
    @State private var sortAscending = false

    @State private var projection: LedgerModel

    public init(initialSelection: String? = nil, projection: LedgerModel? = nil) {
        _projection = State(initialValue: projection ?? LedgerModel())
        if let initialSelection {
            _hoveredID = State(initialValue: initialSelection)
        }
    }

    private var rows: [LedgerRow] { projection.rows }
    private var query: LedgerQuery {
        LedgerQuery(revision: model.inventory.revision, tier: model.ledgerTierFilter,
                    search: model.searchText, sort: sortField, ascending: sortAscending)
    }

    @State private var previewRowID: LedgerRow.ID?
    @State private var checkAnchorID: LedgerRow.ID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public var body: some View {
        VStack(spacing: 0) {
            // Hover and selection reuse the projection; only inventory/query
            // changes schedule work.
            let current = rows
            batchBar(current)
            if current.isEmpty {
                EmptyStateView(emptyLine, symbol: emptySymbol)
            } else {
                table(current)
            }
        }
        .background(BColor.bg)
        .task(id: query) {
            await projection.update(items: model.items, insights: model.result?.insights ?? [], query: query)
        }
        // Space gives a Quick-Look-style preview card on the hovered row.
        .onKeyPress(.space) {
            guard let id = hoveredID ?? rows.first?.id, previewRowID == nil else {
                previewRowID = nil
                return .handled
            }
            previewRowID = id
            return .handled
        }
        .onKeyPress(.escape) {
            guard previewRowID != nil else { return .ignored }
            previewRowID = nil
            return .handled
        }
        .overlay {
            if let id = previewRowID, let row = rows.first(where: { $0.id == id }) {
                previewCard(row)
            }
        }
    }

    private func previewCard(_ row: LedgerRow) -> some View {
        VStack(alignment: .leading, spacing: BSpace.m) {
            HStack {
                Text(row.name)
                    .font(BFont.title)
                    .foregroundStyle(BColor.ink)
                Spacer()
                Text(ByteFormat.string(row.bytes))
                    .font(BFont.rounded(22, .bold))
                    .foregroundStyle(BColor.ink)
            }
            HStack(spacing: BSpace.m) {
                TierChip(row.tier)
                if row.lastTouched != nil {
                    Text(RelativeDate.staleness(row.lastTouched))
                        .font(BFont.meta)
                        .foregroundStyle(BColor.inkSoft)
                }
            }
            if let item = row.item, item.entryID != "app.bundle" {
                Text(row.isMerged ? row.mergedSummary : item.entry.identityLine)
                    .font(BFont.body)
                    .foregroundStyle(BColor.inkSoft)
            }
            if row.isMerged {
                Text(Copy.locationCount(row.items.count)).font(BFont.meta).foregroundStyle(BColor.inkSoft)
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(row.items) { item in
                            HStack(alignment: .top) {
                                Text(displayPath(item.id)).font(BFont.path).textSelection(.enabled)
                                Spacer()
                                Text(ByteFormat.string(item.bytes)).font(BFont.meta)
                            }
                        }
                    }
                }.frame(maxHeight: 220)
            } else {
                Text(row.path).font(BFont.path).foregroundStyle(BColor.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(BSpace.sheetPadding)
        .frame(width: 440)
        .background(BColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: BRadius.sheet))
        .overlay(RoundedRectangle(cornerRadius: BRadius.sheet).strokeBorder(BColor.line, lineWidth: 1))
        .shadow(color: BColor.ink.opacity(0.1), radius: 24, y: 8)
        .onTapGesture { previewRowID = nil }
        .transition(.scale(scale: 0.96).combined(with: .opacity))
    }

    private func batchBar(_ rows: [LedgerRow]) -> some View {
        HStack(spacing: BSpace.m) {
            if let tier = model.ledgerTierFilter {
                tierFilterChip(tier)
            }
            // Installers are the safe bulk case (every row carries "app
            // already installed"): one plan takes the whole set.
            if model.ledgerTierFilter == .yours {
                let installers = model.lensFindings.filter { $0.kind == .installer }
                if installers.count > 1 {
                    Button(Copy.reclaimAll) { model.reclaimFindings(installers) }
                        .buttonStyle(SecondarySmallButtonStyle())
                }
            }
            Spacer()
            Text(sortField == .size && !sortAscending
                 ? "\(Copy.itemCount(rows.count)) · \(Copy.sortedBySize)"
                 : Copy.itemCount(rows.count))
                .font(BFont.meta)
                .foregroundStyle(BColor.inkSoft)
        }
        .padding(.horizontal, BSpace.l)
        .padding(.vertical, BSpace.s)
    }

    /// After a lens pass finds nothing, the Personal filter says so in its
    /// own words instead of pretending a search failed.
    private var emptyLine: String {
        if model.ledgerTierFilter == .yours && model.searchText.isEmpty && !model.scanning {
            return Copy.lensEmpty
        }
        return model.searchText.isEmpty && model.ledgerTierFilter == nil
            ? Copy.kibiDenTidy : Copy.kibiSearchNone
    }

    private var emptySymbol: String {
        model.ledgerTierFilter == .yours ? "magnifyingglass" : "checkmark.circle"
    }

    /// The active Disk Strip tier filter, worn as a TierChip with an ✕.
    /// Sits with the batch actions; clicking it clears the filter.
    private func tierFilterChip(_ tier: Tier) -> some View {
        Button {
            withAnimation(BMotion.light) { model.ledgerTierFilter = nil }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: tier.systemImage)
                    .font(.system(size: 10, weight: .semibold))
                Text(tier.label)
                    .font(.system(size: 11, weight: .medium))
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .opacity(0.7)
            }
            .padding(.horizontal, 8)
            .frame(height: 22)
            .foregroundStyle(tier.color)
            .background(tier.color.opacity(0.18), in: Capsule())
            .overlay(Capsule().strokeBorder(tier.color.opacity(0.55), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(Copy.clearFilter)
        .accessibilityLabel("\(tier.label). \(Copy.clearFilter)")
    }

    /// The mock's grid, hand-built (Warm Instrument): transparent rows on
    /// bg, surface wash on hover, accent-soft wash for rows in the plan,
    /// hairline separators, one fixed order. Columns 52 · flex · 110 · 140 ·
    /// 130 · 100 inside 24 pt gutters.
    private func table(_ rows: [LedgerRow]) -> some View {
        VStack(spacing: 0) {
            columnHeader
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in itemRow(row) }
                }
            }
        }
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 52, height: 1)
            headerCell(Copy.colName, field: .name, alignment: .leading)
            headerCell(Copy.colSize, field: .size, alignment: .trailing)
                .frame(width: 110)
            headerCell(Copy.colTier, field: .tier, alignment: .leading)
                .frame(width: 140)
                .padding(.leading, 24)
            headerCell(Copy.colLastTouched, field: .touched, alignment: .leading)
                .frame(width: 130)
            Color.clear.frame(width: 100, height: 1)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) { Divider().overlay(BColor.hair) }
    }

    /// Sortable header: click to sort, click again to flip. The active
    /// column wears a real chevron, not a text glyph.
    private func headerCell(_ label: String, field: LedgerSort, alignment: Alignment) -> some View {
        Button {
            if sortField == field {
                sortAscending.toggle()
            } else {
                sortField = field
                sortAscending = false
            }
        } label: {
            HStack(spacing: 4) {
                Text(label.uppercased())
                    .font(.system(size: 11.5, weight: .semibold))
                    .kerning(0.46)
                    .foregroundStyle(sortField == field ? BColor.inkSoft : BColor.faint)
                if sortField == field {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(BColor.inkSoft)
                }
            }
            .frame(maxWidth: .infinity, alignment: alignment)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(sortField == field ? [.isSelected] : [])
    }

    private func itemRow(_ row: LedgerRow) -> some View {
        let finding = lensFinding(row)
        let selectable = !row.items.isEmpty && row.items.allSatisfy { model.canSelect($0) }
        let selectedCount = row.selectedCount(in: Set(model.trayItems.map(\.id)))
        let checked = selectable && selectedCount == row.items.count
        return HStack(spacing: 0) {
            // Checkbox zone (52): the mock's 18 pt rounded accent box.
            HStack {
                if selectable {
                    planCheckbox(checked: checked, partial: selectedCount > 0 && !checked)
                }
            }
            .frame(width: 52, alignment: .leading)

            // Name: icon or fan, then name over one quiet sub line.
            HStack(spacing: 12) {
                if let finding, finding.wearsMediaFan {
                    MediaFan(samples: finding.samples)
                } else {
                    ItemIcon(
                        entryID: row.item?.entryID ?? row.insight?.entryID ?? "",
                        url: row.item?.url, tier: row.tier,
                        owner: row.owner, lensKind: finding?.kind
                    )
                }
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(row.name)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(BColor.ink)
                            .lineLimit(1)
                        if row.item == nil {
                            HollowBadge()
                        }
                    }
                    Text(subLine(row, finding: finding))
                        .font(.system(size: 12))
                        .foregroundStyle(BColor.inkSoft)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(row.bytes > 0 ? ByteFormat.string(row.bytes) : "")
                .font(BFont.rounded(13.5, .bold))
                .foregroundStyle(BColor.ink)
                .frame(width: 110, alignment: .trailing)

            TierChip(row.tier)
                .frame(width: 140, alignment: .leading)
                .padding(.leading, 24)

            Text(RelativeDate.short(row.lastTouched))
                .font(.system(size: 12.5))
                .foregroundStyle(BColor.inkSoft)
                .frame(width: 130, alignment: .leading)

            // Managed verbs stay visible (the mock shows them); the
            // selectable icon pair rests hidden and reveals on hover, so
            // rows match the design at rest. Color.clear keeps the column's
            // width even when a row has no verb at all (System bedrock),
            // so Size and Tier never drift.
            ZStack(alignment: .trailing) {
                Color.clear
                rowAction(row)
                    .opacity(selectable && !row.isMerged && hoveredID != row.id ? 0 : 1)
            }
            .frame(width: 100, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 9)
        .frame(height: 52)
        .background(checked ? BColor.brandSoft : (hoveredID == row.id ? BColor.surface : .clear))
        .overlay(alignment: .bottom) { Divider().overlay(BColor.hair) }
        .contentShape(Rectangle())
        .onHover { hoveredID = $0 ? row.id : (hoveredID == row.id ? nil : hoveredID) }
        .onTapGesture {
            // The row is the checkbox (mock): clicking anywhere toggles the
            // plan, shift-click extends the range like the box itself.
            if selectable {
                trayBinding(row).wrappedValue.toggle()
            }
        }
        .contextMenu { contextMenu(ids: [row.id]) }
        .animation(BMotion.light, value: hoveredID == row.id)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLine(row))
    }

    private func planCheckbox(checked: Bool, partial: Bool = false) -> some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(checked ? AnyShapeStyle(BColor.brand) : AnyShapeStyle(BColor.surface))
            .overlay {
                if checked || partial {
                    Image(systemName: partial ? "minus" : "checkmark")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(checked ? BColor.onBrand : BColor.brand)
                } else {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(BColor.line, lineWidth: 1.5)
                }
            }
            .frame(width: 18, height: 18)
    }

    /// The single quiet sub line: what a lens saw plus the short path, or
    /// just the place itself.
    private func subLine(_ row: LedgerRow, finding: LensFinding?) -> String {
        if row.isMerged { return "\(Copy.locationCount(row.members.count)) · \(row.mergedSummary)" }
        let short = row.path.isEmpty ? nil : displayPath(row.path)
        if let finding {
            return [finding.evidenceLine, short].compactMap { $0 }.joined(separator: " · ")
        }
        // The mock's density: what it is, then where (identity clause · path).
        func firstClause(_ line: String) -> String {
            String(line.split(separator: ".").first.map(String.init) ?? line)
        }
        if let item = row.item {
            // App rows carry no descriptor: the name and icon already say
            // what it is, and no bundle ships a usable description of its
            // own (probed: kMDItemDescription and CFBundleGetInfoString are
            // empty across common apps). The path still says where.
            if item.entryID == "app.bundle" {
                return short ?? ""
            }
            return [firstClause(item.entry.identityLine), short].compactMap { $0 }.joined(separator: " · ")
        }
        if let insight = row.insight {
            return firstClause(Atlas.entry(insight.entryID).identityLine)
        }
        return short ?? ""
    }


    /// Every row's direct verbs, as real buttons: icon pair for rows Elbowroom
    /// moves itself, worded pills where another tool or a lesson does the work.
    @ViewBuilder
    private func rowAction(_ row: LedgerRow) -> some View {
        if row.isMerged {
            if row.items.allSatisfy({ model.canSelect($0) }) {
                Button(Copy.reviewCleanup) { model.openReclaimPlan(items: row.items) }
                    .buttonStyle(RowActionButtonStyle())
            } else {
                Button(Copy.groupDetails) { previewRowID = row.id }
                    .buttonStyle(RowActionButtonStyle())
            }
        } else if let item = row.item, model.canSelect(item) {
            HStack(spacing: 6) {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(RowIconButtonStyle())
                .help(Copy.revealInFinder)
                .accessibilityLabel(Copy.revealInFinder)
                Button {
                    model.perform(.reclaim, on: item)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(RowIconButtonStyle())
                .help(Copy.trayReclaim)
                .accessibilityLabel(Copy.trayReclaim)
            }
        } else if let item = row.item, let action = model.action(for: item) {
            Button(action.title) { model.perform(action, on: item) }
                .buttonStyle(RowActionButtonStyle())
                .accessibilityLabel(action.title)
        } else if let insight = row.insight, let flow = Atlas.entry(insight.entryID).teachFlow {
            Button(Copy.showMe) { model.sheet = .teach(flow, bytes: insight.bytes) }
                .buttonStyle(RowActionButtonStyle())
        }
    }

    /// Checkbox binding with range semantics: a plain click toggles one row,
    /// shift-click extends the clicked state from the last-toggled row across
    /// everything between, ticking down the range in a brief cascade.
    private func trayBinding(_ row: LedgerRow) -> Binding<Bool> {
        Binding(
            get: { !row.items.isEmpty && row.items.allSatisfy { model.trayItems.contains($0) } },
            set: { include in
                let shift = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
                let visible = rows
                if shift, let anchor = checkAnchorID, anchor != row.id,
                   let a = visible.firstIndex(where: { $0.id == anchor }),
                   let b = visible.firstIndex(where: { $0.id == row.id }) {
                    applyTray(Array(visible[min(a, b)...max(a, b)]), include: include)
                } else {
                    model.setTray(items: row.items, selected: include)
                }
                checkAnchorID = row.id
            }
        )
    }

    private func applyTray(_ range: [LedgerRow], include: Bool) {
        let step: UInt64 = reduceMotion ? 0 : min(25_000_000, 400_000_000 / UInt64(max(range.count, 1)))
        Task {
            for row in range {
                model.setTray(items: row.items, selected: include)
                if step > 0 { try? await Task.sleep(nanoseconds: step) }
            }
        }
    }

    private func lensFinding(_ row: LedgerRow) -> LensFinding? {
        guard row.item?.entryID == "lens.found" else { return nil }
        return model.lensFindings.first { $0.url.path == row.id }
    }

    /// Paths render home-relative so they fit whole in the fixed row height.
    private func displayPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) { return "~" + path.dropFirst(home.count) }
        return path
    }

    private func accessibilityLine(_ row: LedgerRow) -> String {
        // VoiceOver order: name, size, tier, last touched.
        var parts = [row.name, ByteFormat.string(row.bytes), row.tier.label]
        if row.isMerged { parts.append(Copy.locationCount(row.items.count)) }
        if let touched = row.lastTouched { parts.append(RelativeDate.short(touched)) }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private func contextMenu(ids: Set<LedgerRow.ID>) -> some View {
        let selected = rows.filter { ids.contains($0.id) }.flatMap(\.items)
        if !selected.isEmpty {
            if selected.allSatisfy({ model.canSelect($0) }) {
                Button(Copy.trayReclaim) {
                    for item in selected where !model.trayItems.contains(item) {
                        model.toggleTray(item)
                    }
                    model.openReclaimPlan()
                }
            }
            if let first = selected.first, selected.count == 1 {
                Button(Copy.revealInFinder) {
                    NSWorkspace.shared.activateFileViewerSelecting([first.url])
                }
            }
        }
        // The trailing action column's verb, mirrored for one row.
        if ids.count == 1, let row = rows.first(where: { ids.contains($0.id) }) {
            if let item = row.item, !model.canSelect(item), let action = model.action(for: item) {
                Button(action.title) { model.perform(action, on: item) }
            } else if let insight = row.insight,
                      let flow = Atlas.entry(insight.entryID).teachFlow {
                Button(Copy.showMe) { model.sheet = .teach(flow, bytes: insight.bytes) }
            }
        }
    }
}


/// Every row carries a face at thumbnail scale. App-owned items wear
/// their app's real icon, genuine files and bundles wear their Finder icon,
/// and bare folders or insights wear a tier-tinted symbol chip — never a
/// sea of identical blue folders.
struct ItemIcon: View {
    let entryID: String
    let url: URL?
    let tier: Tier
    let owner: String
    let lensKind: LensKind?

    @State private var image: NSImage?
    /// Resolution touches the disk and Icon Services, so it runs off-main
    /// once per key and caches; rows render the chip instantly.
    private static let cache = NSCache<NSString, NSImage>()

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tier.color.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(tier.color.opacity(0.25), lineWidth: 1)
                    )
                    .overlay(
                        Image(systemName: symbolName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(tier.color)
                    )
            }
        }
        .frame(width: 34, height: 34)
        .accessibilityHidden(true)
        .task(id: cacheKey) {
            let key = cacheKey as NSString
            if let hit = Self.cache.object(forKey: key) { image = hit; return }
            image = nil
            let entryID = entryID, url = url, owner = owner, lensKind = lensKind
            let found = await Task.detached(priority: .utility) {
                Self.resolve(entryID: entryID, url: url, owner: owner, lensKind: lensKind)
            }.value
            guard !Task.isCancelled else { return }
            if let found {
                Self.cache.setObject(found, forKey: key)
                image = found
            }
        }
    }

    private var cacheKey: String { entryID + "|" + (url?.path ?? owner) }

    nonisolated private static func resolve(entryID: String, url: URL?, owner: String, lensKind: LensKind?) -> NSImage? {
        let fm = FileManager.default
        func app(_ name: String) -> NSImage? {
            let path = "/Applications/\(name).app"
            return fm.fileExists(atPath: path) ? NSWorkspace.shared.icon(forFile: path) : nil
        }
        // The owning app's icon is the most recognizable face there is.
        if entryID == "sys.appCache", let url,
           let icon = app(AppNames.human(fromCacheFolder: url.lastPathComponent)) {
            return icon
        }
        if entryID.hasPrefix("xcode."), let icon = app("Xcode") { return icon }
        if lensKind == .game, let icon = app("Steam") { return icon }
        switch owner {
        case "Simulator": if let icon = app("Xcode") { return icon }
        default: break
        }
        if let icon = app(owner) { return icon }
        // Real files and bundles carry their Finder icon; bare folders fall
        // through to the chip.
        if let url {
            var isDirectory: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDirectory),
               !isDirectory.boolValue || !url.pathExtension.isEmpty {
                return NSWorkspace.shared.icon(forFile: url.path)
            }
        }
        return nil
    }

    private var symbolName: String {
        if lensKind != nil, LensFinding.isDownloadsRoot(url) { return "arrow.down.circle" }
        if let lensKind {
            switch lensKind {
            case .vm: return "desktopcomputer"
            case .weights: return "brain"
            case .project: return "curlybraces"
            case .downloads: return "arrow.down.circle"
            case .ghost: return "clock.arrow.circlepath"
            case .game: return "gamecontroller"
            case .installer: return "shippingbox"
            case .twin: return "doc.on.doc"
            case .zipShadow: return "doc.zipper"
            default: return "photo"
            }
        }
        switch entryID {
        case "sys.iosBackups": return "iphone"
        case "sys.trash": return "trash"
        case "sys.purgeable": return "internaldrive"
        case "sys.snapshots": return "clock.arrow.circlepath"
        case "sys.os": return "apple.logo"
        case "sys.updateStaging": return "arrow.down.circle"
        case "sys.swap": return "memorychip"
        case "xcode.simDevices", "xcode.testDevices", "xcode.simRuntimes": return "iphone"
        default: break
        }
        switch Atlas.entry(entryID).pack {
        case .xcode: return "hammer"
        case .javascript: return "cube"
        case .rust: return "cube.transparent"
        case .homebrew: return "mug"
        case .containers: return "shippingbox"
        case .ml: return "brain"
        case .systemResidue: return "internaldrive"
        case .applications: return "square.grid.2x2"
        }
    }
}

/// Row verbs in the Ledger's trailing actions column: quiet bordered pill,
/// TierChip-height, unmistakably a button.
struct RowActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(BColor.ink)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(BColor.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(BColor.ink.opacity(0.25), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// The icon variant for the mechanical action (Reclaim): same quiet
/// bordered language, round, tooltip carries the word.
struct RowIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(isEnabled ? BColor.ink : BColor.inkSoft.opacity(0.5))
            .frame(width: 22, height: 22)
            .background(BColor.surface, in: Circle())
            .overlay(Circle().strokeBorder(BColor.ink.opacity(isEnabled ? 0.25 : 0.12), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Circle())
    }
}
