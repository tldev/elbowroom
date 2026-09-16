import CoreGraphics

/// Layout solver for the Disk Strip's marks. Pure math, no views:
/// proportional widths with a visibility floor, and a cursor-driven magnifier
/// so slivers grow to a hoverable size as the mouse nears. Total mark width is
/// conserved; the widest marks pay for every boost, so the free edge never
/// moves.
enum StripLayout {
    struct Mark: Equatable {
        let index: Int
        let x: CGFloat
        let width: CGFloat
    }

    /// Hit result for the free-space region right of the last mark.
    static let freeIndex = -1

    static func marks(
        natural: [CGFloat],
        gap: CGFloat = 2,
        floorWidth: CGFloat = 3,
        magnified: CGFloat = 16,
        radius: CGFloat = 48,
        mouseX: CGFloat? = nil
    ) -> [Mark] {
        // Marks below the floor read as nothing and cannot be hovered; give
        // them the floor and let the widest marks absorb the difference.
        let idx = natural.indices.filter { natural[$0] > 0 }
        guard !idx.isEmpty else { return [] }
        var w = [Int: CGFloat]()
        for i in idx { w[i] = max(natural[i], floorWidth) }

        // Distance to the cursor is measured on the pre-magnification layout,
        // so magnifying never feeds back into its own geometry.
        var centers = [Int: CGFloat]()
        var run: CGFloat = 0
        for i in idx {
            centers[i] = run + w[i]! / 2
            run += w[i]! + gap
        }

        if let mouseX {
            for i in idx where w[i]! < magnified {
                let d = abs(centers[i]! - mouseX)
                guard d < radius else { continue }
                let t = 1 - d / radius
                w[i]! += (magnified - w[i]!) * t * t * (3 - 2 * t)
            }
        }

        // Conservation: the widest marks give back exactly what floors and
        // magnification added, never dropping below 2x the magnified size.
        let deficit = idx.reduce(0) { $0 + w[$1]! - natural[$1] }
        let payers = idx.filter { natural[$0] > magnified * 2 }
        let payable = payers.reduce(0) { $0 + (natural[$1] - magnified * 2) }
        if deficit > 0, payable > 0 {
            let share = min(1, deficit / payable)
            for i in payers { w[i]! -= (natural[i] - magnified * 2) * share }
        }

        var out: [Mark] = []
        var x: CGFloat = 0
        for i in idx {
            out.append(Mark(index: i, x: x, width: w[i]!))
            x += w[i]! + gap
        }
        return out
    }

    /// The mark under x, `freeIndex` past the last mark, nil in a gap or
    /// left of the first mark.
    static func hit(_ marks: [Mark], at x: CGFloat) -> Int? {
        for mark in marks where x >= mark.x && x <= mark.x + mark.width {
            return mark.index
        }
        if let last = marks.last, x > last.x + last.width { return freeIndex }
        return nil
    }
}
