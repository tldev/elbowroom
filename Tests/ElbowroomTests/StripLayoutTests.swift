import XCTest
@testable import ElbowroomKit

/// Disk Strip marks: the sliver floor, the cursor magnifier, and width
/// conservation so the free edge never moves.
final class StripLayoutTests: XCTestCase {
    func testSliverGetsFloorAndPayerCovers() {
        let marks = StripLayout.marks(natural: [1, 500])
        XCTAssertEqual(marks[0].width, 3)
        XCTAssertEqual(marks[1].width, 498, accuracy: 0.001)
    }

    func testTotalWidthConserved() {
        for mouse in [nil, CGFloat(0), 5, 200, 700] {
            let natural: [CGFloat] = [2, 6, 21, 700]
            let marks = StripLayout.marks(natural: natural, mouseX: mouse)
            let total = marks.reduce(0) { $0 + $1.width }
            XCTAssertEqual(total, natural.reduce(0, +), accuracy: 0.001, "mouse \(String(describing: mouse))")
        }
    }

    func testMagnifierGrowsSliverUnderCursor() {
        let far = StripLayout.marks(natural: [2, 500], mouseX: 400)
        XCTAssertEqual(far[0].width, 3)
        let near = StripLayout.marks(natural: [2, 500], mouseX: 1.5)
        XCTAssertEqual(near[0].width, 16, accuracy: 0.001)
    }

    func testMagnifierFadesWithDistance() {
        let mid = StripLayout.marks(natural: [2, 500], mouseX: 25)
        XCTAssertGreaterThan(mid[0].width, 3)
        XCTAssertLessThan(mid[0].width, 16)
    }

    func testComfortableMarksAreNotMagnified() {
        let marks = StripLayout.marks(natural: [40, 500], mouseX: 20)
        XCTAssertEqual(marks[0].width, 40, accuracy: 0.001)
    }

    func testZeroSegmentsDropOut() {
        let marks = StripLayout.marks(natural: [0, 10, 0, 500])
        XCTAssertEqual(marks.map(\.index), [1, 3])
    }

    func testHitResolution() {
        let marks = StripLayout.marks(natural: [10, 500])
        XCTAssertEqual(StripLayout.hit(marks, at: 5), 0)
        XCTAssertEqual(StripLayout.hit(marks, at: 100), 1)
        XCTAssertEqual(StripLayout.hit(marks, at: 600), StripLayout.freeIndex)
        XCTAssertNil(StripLayout.hit(marks, at: -4))
        XCTAssertNil(StripLayout.hit(marks, at: 11))
    }

    func testPayersNeverDropBelowTwiceMagnified() {
        // Pathological: many slivers, one modest payer. The payer bottoms out
        // at 32 and the layout accepts the small overflow instead of vanishing.
        let natural: [CGFloat] = [1, 1, 1, 1, 1, 40]
        let marks = StripLayout.marks(natural: natural)
        XCTAssertGreaterThanOrEqual(marks[5].width, 32 - 0.001)
    }
}
