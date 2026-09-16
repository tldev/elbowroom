import SwiftUI

/// The Map: a squarified treemap of the actual directory tree, tinted by the
/// four-tier classification. Area is strictly proportional to bytes. Click a
/// folder to drill in; the path bar climbs back out; Esc goes up one.
/// What the footer pill says about the hovered region (Warm Instrument):
/// name, size, path, and one lens-flavored note.
struct MapHoverInfo: Equatable {
    let name: String
    let size: String
    let path: String
    let note: String
}

struct MapHoverKey: PreferenceKey {
    static let defaultValue: MapHoverInfo? = nil
    static func reduce(value: inout MapHoverInfo?, nextValue: () -> MapHoverInfo?) {
        if let next = nextValue() { value = next }
    }
}

public struct MapView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoverInfo: MapHoverInfo?

    public init() {}

    private var currentNode: ScanNode? {
        model.zoomPath.last.flatMap { model.result?.root.find(path: $0.path) } ?? model.result?.root
    }

    public var body: some View {
        VStack(spacing: 0) {
            pathBar
            GeometryReader { geo in
                if let node = currentNode {
                    treemap(node: node, size: geo.size)
                }
            }
            .padding(.horizontal, BSpace.l)
            .padding(.bottom, BSpace.s)
            footer
        }
        .background(BColor.bg)
        .onPreferenceChange(MapHoverKey.self) { hoverInfo = $0 }
        .onKeyPress(.escape) {
            if !model.zoomPath.isEmpty {
                withAnimation(reduceMotion ? nil : BMotion.standard) { _ = model.zoomPath.removeLast() }
                return .handled
            }
            return .ignored
        }
        .accessibilityLabel("Map. The Items view lists the same contents.")
    }

    // MARK: Path bar

    private var pathBar: some View {
        HStack(spacing: 8) {
            pathSegment(name: model.result?.disk.volumeName ?? "Macintosh HD", depth: 0)
            ForEach(Array(model.zoomPath.enumerated()), id: \.element.id) { index, node in
                Text("›")
                    .font(.system(size: 12))
                    .foregroundStyle(BColor.faint)
                pathSegment(name: node.name, depth: index + 1)
            }
            Text(Copy.clickRegionHint)
                .font(.system(size: 12.5))
                .foregroundStyle(BColor.inkSoft)
                .padding(.leading, 2)
            Spacer()
            if let node = currentNode, let disk = model.result?.disk {
                Text(Copy.scannedAndFree(ByteFormat.string(node.allocatedBytes), ByteFormat.string(disk.available)))
                    .font(.system(size: 12.5))
                    .foregroundStyle(BColor.inkSoft)
            }
        }
        .padding(.horizontal, BSpace.l)
        .frame(height: 40)
    }

    private func pathSegment(name: String, depth: Int) -> some View {
        let isCurrent = depth == model.zoomPath.count
        return Button {
            withAnimation(reduceMotion ? nil : BMotion.standard) {
                model.zoomPath = Array(model.zoomPath.prefix(depth))
            }
        } label: {
            Text(name)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(BColor.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(isCurrent ? BColor.soil : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isCurrent && model.zoomPath.isEmpty)
    }

    // MARK: Treemap

    private func treemap(node: ScanNode, size: CGSize) -> some View {
        let slices = Treemap.slices(of: node)
        let placed = Treemap.layout(
            items: slices.map { (id: $0.id, bytes: $0.bytes) },
            in: CGRect(origin: .zero, size: size)
        )
        let byID = Dictionary(uniqueKeysWithValues: slices.map { ($0.id, $0) })
        return ZStack(alignment: .topLeading) {
            ForEach(placed, id: \.id) { tile in
                if let slice = byID[tile.id] {
                    MapTile(
                        node: slice.node,
                        name: slice.name,
                        bytes: slice.bytes,
                        rect: tile.rect.insetBy(dx: 1, dy: 1)
                    )
                    .offset(x: tile.rect.minX + 1, y: tile.rect.minY + 1)
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .animation(reduceMotion ? nil : BMotion.standard, value: node.id)
    }

    // MARK: Footer: the legend is the identity channel

    /// Legend left, the hovered region's story in the center pill, the
    /// reading rule on the right (Warm Instrument).
    private var footer: some View {
        HStack(spacing: BSpace.l) {
            HStack(spacing: 14) {
                ForEach(Tier.allCases) { tier in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(tier.color)
                            .frame(width: 8, height: 8)
                        Text(tier.label)
                            .font(BFont.meta)
                            .foregroundStyle(BColor.inkSoft)
                    }
                    .help(tier.tooltip)
                }
            }
            .fixedSize()
            Spacer(minLength: 0)
            if let info = hoverInfo {
                HStack(spacing: 12) {
                    Text(info.name)
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(BColor.ink)
                    Text(info.size)
                        .font(BFont.rounded(12.5, .bold))
                        .foregroundStyle(BColor.ink)
                    Text(info.path)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(BColor.inkSoft)
                        .lineLimit(1)
                    if !info.note.isEmpty {
                        Text(info.note)
                            .font(.system(size: 12))
                            .foregroundStyle(BColor.inkSoft)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(BColor.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(BColor.hair, lineWidth: 1))
                .transition(.opacity)
            }
            Spacer(minLength: 0)
            Text(Copy.tintTierAreaSize)
                .font(.system(size: 11.5))
                .foregroundStyle(BColor.faint)
                .fixedSize()
        }
        .animation(BMotion.light, value: hoverInfo)
        .padding(.horizontal, BSpace.l)
        .frame(height: 44)
    }
}

// MARK: - Tile

struct MapTile: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let node: ScanNode?
    let name: String
    let bytes: Int64
    let rect: CGRect
    @State private var hover = false

    private var entry: AtlasEntry? { node?.atlasEntryID.map { Atlas.entry($0) } }
    private var tier: Tier? { entry?.tier }
    private var item: AtlasItem? {
        guard let node, let entryID = node.atlasEntryID else { return nil }
        return model.items.first { $0.id == node.path } ?? AtlasItem(
            entryID: entryID, url: node.url, bytes: node.allocatedBytes, lastTouched: node.lastTouched
        )
    }

    private var dimmedBySearch: Bool {
        guard !model.searchText.isEmpty else { return false }
        return !name.localizedCaseInsensitiveContains(model.searchText)
    }

    private var explainEligible: Bool {
        node != nil && entry == nil && bytes >= AskKibi.minimumBytes
            && AskKibi.isAvailable && node?.children.isEmpty == false
    }

    var body: some View {
        let fill = tier?.color.opacity(0.15) ?? BColor.inkSoft.opacity(0.06)
        let border = tier?.color.opacity(0.28) ?? BColor.ink.opacity(0.12)

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: BRadius.chamber)
                .fill(BColor.surface)
            RoundedRectangle(cornerRadius: BRadius.chamber)
                .fill(fill)
            RoundedRectangle(cornerRadius: BRadius.chamber)
                .strokeBorder(border, lineWidth: 1)
            label
        }
        .overlay(alignment: .topTrailing) { badges }
        .brightness(hover ? -0.03 : 0)
        .frame(width: max(rect.width, 2), height: max(rect.height, 2))
        .opacity(dimmedBySearch ? 0.25 : 1)
        .contentShape(Rectangle())
        .onHover { h in
            withAnimation(BMotion.light) { hover = h }
        }
        // The hovered region's story rides a preference to the footer pill.
        .preference(key: MapHoverKey.self, value: hover ? hoverInfo : nil)
        .onTapGesture { drill() }
        .contextMenu { menu }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var hoverInfo: MapHoverInfo {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var path = node?.path ?? ""
        if path.hasPrefix(home) { path = "~" + path.dropFirst(home.count) }
        // One lens-flavored note: what a lens named inside, else the entry's
        // identity, else staleness.
        let note: String
        if let nodePath = node?.path,
           let finding = model.lensFindings.first(where: { $0.url.path.hasPrefix(nodePath) }) {
            note = finding.evidenceLine
        } else if let entry {
            note = entry.identityLine
        } else if let touched = node?.lastTouched {
            note = RelativeDate.staleness(touched)
        } else {
            note = ""
        }
        return MapHoverInfo(name: name, size: ByteFormat.string(bytes), path: path, note: note)
    }

    /// The name renders only when it fits whole; otherwise the tile falls
    /// back to size only, and the hover card carries the full name. Nothing
    /// is ever cut off.
    private var nameFits: Bool {
        CGFloat(name.count) * 6.4 + 14 <= rect.width
    }

    @ViewBuilder
    private var label: some View {
        if rect.width >= 88, rect.height >= 36, nameFits {
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(BColor.ink)
                    .lineLimit(1)
                Text(ByteFormat.string(bytes))
                    .font(BFont.rounded(10, .regular))
                    .foregroundStyle(BColor.inkSoft)
            }
            .padding(6)
        } else if rect.width >= 46, rect.height >= 18 {
            Text(ByteFormat.string(bytes))
                .font(BFont.rounded(9, .medium))
                .foregroundStyle(BColor.inkSoft)
                .padding(4)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var badges: some View {
        HStack(spacing: 3) {
            if explainEligible, rect.width >= 60, rect.height >= 30 {
                Button(action: explain) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 8))
                        .foregroundStyle(BColor.inkSoft)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(Copy.askKibi)
            }
        }
        .padding(4)
    }

    @ViewBuilder
    private var menu: some View {
        if let item, let action = model.action(for: item) {
            Button(action.title) { model.perform(action, on: item) }
        }
        if explainEligible {
            Button(Copy.askKibi) { explain() }
        }
        if let node {
            Button(Copy.revealInFinder) {
                NSWorkspace.shared.activateFileViewerSelecting([node.url])
            }
        }
    }

    private var accessibilityText: String {
        var parts = [name, ByteFormat.string(bytes)]
        if let tier { parts.append(tier.label) }
        return parts.joined(separator: ", ")
    }

    private func drill() {
        guard let node, node.isDirectory, !node.children.isEmpty else { return }
        withAnimation(reduceMotion ? nil : BMotion.standard) {
            model.zoomPath.append(node)
        }
    }

    private func explain() {
        guard let node else { return }
        model.sheet = .askKibi(
            name: name, path: node.path, bytes: bytes,
            children: node.children.map(\.name)
        )
    }
}
