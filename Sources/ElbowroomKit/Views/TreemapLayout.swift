import Foundation
import CoreGraphics

/// Squarified treemap (Bruls, Huizing, van Wijk). Area is strictly
/// proportional to bytes; strips lay along the shorter side and cut when
/// adding an item would worsen the worst aspect ratio. Pure and deterministic
/// so the honesty tests run headless.
public enum Treemap {
    public struct Placed: Equatable {
        public let id: String
        public let rect: CGRect
    }

    public static func layout(items: [(id: String, bytes: Int64)], in rect: CGRect) -> [Placed] {
        let total = items.reduce(Double(0)) { $0 + Double(max($1.bytes, 0)) }
        guard total > 0, rect.width > 1, rect.height > 1 else { return [] }
        let scale = rect.width * rect.height / total
        var scaled = items
            .filter { $0.bytes > 0 }
            .map { (id: $0.id, area: Double($0.bytes) * scale) }
        scaled.sort { $0.area > $1.area }

        var out: [Placed] = []
        var remaining = rect
        var row: [(id: String, area: Double)] = []

        func worst(_ row: [(id: String, area: Double)], side: Double) -> Double {
            guard !row.isEmpty, side > 0 else { return .infinity }
            let sum = row.reduce(0) { $0 + $1.area }
            guard sum > 0 else { return .infinity }
            let maxA = row.map(\.area).max()!
            let minA = row.map(\.area).min()!
            let s2 = sum * sum
            let side2 = side * side
            return max(side2 * maxA / s2, s2 / (side2 * minA))
        }

        func flush() {
            guard !row.isEmpty else { return }
            let sum = row.reduce(0) { $0 + $1.area }
            let horizontal = remaining.width >= remaining.height
            if horizontal {
                // Strip is a vertical column on the leading edge.
                let stripW = sum / Double(remaining.height)
                var y = remaining.minY
                for item in row {
                    let h = item.area / stripW
                    out.append(Placed(id: item.id, rect: CGRect(
                        x: remaining.minX, y: y, width: stripW, height: h
                    )))
                    y += h
                }
                remaining = CGRect(
                    x: remaining.minX + stripW, y: remaining.minY,
                    width: remaining.width - stripW, height: remaining.height
                )
            } else {
                // Strip is a horizontal row along the top edge.
                let stripH = sum / Double(remaining.width)
                var x = remaining.minX
                for item in row {
                    let w = item.area / stripH
                    out.append(Placed(id: item.id, rect: CGRect(
                        x: x, y: remaining.minY, width: w, height: stripH
                    )))
                    x += w
                }
                remaining = CGRect(
                    x: remaining.minX, y: remaining.minY + stripH,
                    width: remaining.width, height: remaining.height - stripH
                )
            }
            row = []
        }

        for item in scaled {
            let side = Double(min(remaining.width, remaining.height))
            if row.isEmpty || worst(row + [item], side: side) <= worst(row, side: side) {
                row.append(item)
            } else {
                flush()
                row = [item]
            }
        }
        flush()
        return out
    }

    /// Level data: the top slices of a node's children, the rest folded into
    /// one aggregate so the map never becomes confetti.
    public static func slices(of node: ScanNode, limit: Int = 40) -> [(node: ScanNode?, id: String, name: String, bytes: Int64)] {
        var out: [(ScanNode?, String, String, Int64)] = node.children
            .prefix(limit)
            .map { ($0, $0.path, $0.name, $0.allocatedBytes) }
        let shown = node.children.prefix(limit).reduce(Int64(0)) { $0 + $1.allocatedBytes }
        let restCount = max(0, node.children.count - limit) + node.collapsedCount
        let restBytes = max(0, node.allocatedBytes - shown)
        if restBytes > 0 {
            out.append((nil, node.path + "|rest",
                        Copy.pebblePile(count: max(restCount, 1), size: ByteFormat.string(restBytes)),
                        restBytes))
        }
        return out.map { (node: $0.0, id: $0.1, name: $0.2, bytes: $0.3) }
    }
}
