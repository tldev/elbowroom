import XCTest
@testable import ElbowroomKit

//// copy rules are absolute, so they are tests: no em-dashes anywhere in
/// the product, no exclamation points, no marketing lines, no "unfortunately".
/// The rules hold in every launch language.
final class CopyRulesTests: XCTestCase {
    private func inEachLanguage(_ body: () -> Void) {
        let saved = Loc.lang
        defer { Loc.lang = saved }
        for lang in ["en", "ja"] {
            Loc.lang = lang
            body()
        }
    }

    func testNoEmDashesAnywhere() {
        inEachLanguage {
            for s in Copy.auditableStrings {
                XCTAssertFalse(s.contains("\u{2014}"), "[\(Loc.lang)] Em-dash found in: \(s)")
                XCTAssertFalse(s.contains("\u{2013}"), "[\(Loc.lang)] En-dash found in: \(s)")
            }
            for entry in Atlas.entries.values {
                XCTAssertFalse(entry.title.contains("\u{2014}"), "Em-dash in title: \(entry.title)")
                XCTAssertFalse(entry.identityLine.contains("\u{2014}"), "Em-dash in identity: \(entry.identityLine)")
            }
            for flow in TeachFlow.flows.values {
                XCTAssertFalse(flow.title.contains("\u{2014}"))
                XCTAssertFalse(flow.why.contains("\u{2014}"))
            }
        }
    }

    /// House rule from the founder: no ellipsis anywhere, spelled or typed;
    /// nothing may read as cut off.
    func testNoEllipsisAnywhere() {
        inEachLanguage {
            for s in Copy.auditableStrings {
                XCTAssertFalse(s.contains("\u{2026}"), "[\(Loc.lang)] Ellipsis found in: \(s)")
                XCTAssertFalse(s.contains("..."), "[\(Loc.lang)] Spelled ellipsis in: \(s)")
            }
            for entry in Atlas.entries.values {
                XCTAssertFalse(entry.title.contains("\u{2026}"))
                XCTAssertFalse(entry.identityLine.contains("\u{2026}"))
            }
            for flow in TeachFlow.flows.values {
                XCTAssertFalse(flow.why.contains("\u{2026}"))
                XCTAssertFalse((flow.commandGloss ?? "").contains("\u{2026}"))
            }
        }
    }

    func testNoExclamationPoints() {
        inEachLanguage {
            for s in Copy.auditableStrings {
                XCTAssertFalse(s.contains("!"), "[\(Loc.lang)] Exclamation point found in: \(s)")
                XCTAssertFalse(s.contains("\u{FF01}"), "[\(Loc.lang)] Full-width exclamation in: \(s)")
            }
            for entry in Atlas.entries.values {
                XCTAssertFalse(entry.identityLine.contains("!"))
            }
        }
    }

    /// Every ja value keeps its template placeholders (%@, %d, positional)
    /// exactly as the en key has them, so String(format:) never misfires.
    func testJapanesePlaceholderParity() {
        let pattern = try! NSRegularExpression(pattern: "%([0-9]+\\$)?[@d]")
        func specifiers(_ s: String) -> [String] {
            pattern.matches(in: s, range: NSRange(s.startIndex..., in: s))
                .map { (s as NSString).substring(with: $0.range) }
        }
        for (en, ja) in Loc.jaStrings {
            XCTAssertEqual(
                specifiers(en).sorted(), specifiers(ja).sorted(),
                "Placeholder mismatch for key: \(en)"
            )
        }
    }

    /// Every Atlas identity and teach-flow string has a ja entry (: all of
    /// the deck plus Atlas strings are translated).
    func testJapaneseCoversAtlasAndTeachFlows() {
        let saved = Loc.lang
        defer { Loc.lang = saved }
        Loc.lang = "en"
        for entry in Atlas.entries.values {
            XCTAssertNotNil(Loc.jaStrings[entry.title], "No ja for Atlas title: \(entry.title)")
            XCTAssertNotNil(Loc.jaStrings[entry.identityLine], "No ja for identity: \(entry.identityLine)")
        }
        for flow in TeachFlow.flows.values {
            XCTAssertNotNil(Loc.jaStrings[flow.title], "No ja for teach title: \(flow.title)")
            XCTAssertNotNil(Loc.jaStrings[flow.why], "No ja for teach why: \(flow.why)")
            if let door = flow.doorLabel {
                XCTAssertNotNil(Loc.jaStrings[door], "No ja for teach door: \(door)")
            }
            if let gloss = flow.commandGloss {
                XCTAssertNotNil(Loc.jaStrings[gloss], "No ja for teach gloss: \(gloss)")
            }
            if let warning = flow.warning {
                XCTAssertNotNil(Loc.jaStrings[warning], "No ja for teach warning: \(warning)")
            }
        }
    }

    /// Every sound the app can play resolves to a shipped file.
    func testAllSoundsShip() {
        for sound in ElbowroomSound.allCases {
            XCTAssertNotNil(SoundPlayer.resourceURL(sound), "missing sound: \(sound.rawValue)")
        }
    }

    /// The Shared with You item teaches its own flow (not the Photos library
    /// one), and the flow's annotated settings figure ships in the bundle.
    func testSharedWithYouFlowAndFigure() {
        XCTAssertEqual(Atlas.entry("sys.photosSyndication").teachFlow, .sharedWithYou)
        let flow = TeachFlow.flow(.sharedWithYou)
        XCTAssertEqual(flow.figure, "teach-shared-with-you")
        let saved = Loc.lang
        defer { Loc.lang = saved }
        for lang in ["en", "ja"] {
            Loc.lang = lang
            XCTAssertNotNil(TeachFigures.url("teach-shared-with-you"),
                            "figure missing for lang \(lang)")
        }
    }

    /// No teach flow contains the word "unfortunately".
    func testNoUnfortunately() {
        for flow in TeachFlow.flows.values {
            XCTAssertFalse(flow.why.lowercased().contains("unfortunately"))
            XCTAssertFalse((flow.warning ?? "").lowercased().contains("unfortunately"))
        }
    }

    /// Kibi lines are 6 words or fewer.
    func testKibiLinesShort() {
        for line in [Copy.kibiDenTidy, Copy.kibiReceiptsEmpty,
                     Copy.kibiChangesQuiet, Copy.kibiSearchNone] {
            XCTAssertLessThanOrEqual(line.split(separator: " ").count, 6, line)
        }
    }

    func testButtonsStartWithVerbs() {
        // Spot checks on the canonical buttons (writing rules).
        XCTAssertTrue(Copy.fdaOpen.hasPrefix("Open"))
        XCTAssertTrue(Copy.b3StartScan.hasPrefix("Start"))
        XCTAssertTrue(Copy.b3Relaunch.hasPrefix("Relaunch"))
        XCTAssertTrue(Copy.reclaimPrimary("5 GB").hasPrefix("Reclaim"))
    }

    /// B3: the guided fallback lists only the consent zones that exist on
    /// this account; a Mac without a Photos library gets no Photos dialog.
    func testPromptZonesSkipAbsentPaths() {
        let home = URL(fileURLWithPath: "/Users/dev")
        XCTAssertEqual(PromptZone.present(home: home) { _ in true }, PromptZone.allCases)
        let noPhotos = PromptZone.present(home: home) { !$0.contains("Photos Library") }
        XCTAssertFalse(noPhotos.contains(.photos))
        XCTAssertTrue(noPhotos.contains(.desktop))
        XCTAssertTrue(noPhotos.contains(.appData))
        XCTAssertEqual(PromptZone.present(home: home) { _ in false }, [])
    }
}

final class ByteFormatTests: XCTestCase {
    func testSplitUnits() {
        XCTAssertEqual(ByteFormat.split(41_300_000_000).joined, "41.3 GB")
        XCTAssertEqual(ByteFormat.split(950).joined, "950 B")
        XCTAssertEqual(ByteFormat.split(2_100_000).joined, "2.1 MB")
        XCTAssertEqual(ByteFormat.split(1_500_000_000_000).joined, "1.5 TB")
        XCTAssertEqual(ByteFormat.split(0).joined, "0 B")
    }

    func testRatePhrasing() {
        XCTAssertEqual(ByteFormat.rate(780_000_000), "780 MB")
        XCTAssertEqual(ByteFormat.rate(140_000_000), "140 MB")
    }

    func testMinutes() {
        XCTAssertEqual(ByteFormat.minutes(120), "2 min")
        XCTAssertEqual(ByteFormat.minutes(30), "30 sec")
        XCTAssertEqual(ByteFormat.minutes(3600), "60 min")
    }

    func testStaleness() {
        let now = Date()
        XCTAssertEqual(RelativeDate.staleness(now.addingTimeInterval(-160 * 86_400), now: now), "untouched 5 months")
        XCTAssertEqual(RelativeDate.staleness(now, now: now), "touched today")
    }
}
