import XCTest
@testable import ElbowroomKit

/// Every lens detector is pure; these fixtures never touch the disk.
final class LensTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func fact(_ path: String, bytes: Int64 = 1_000_000, ageDays: Double = 10, dir: Bool = false) -> FileFact {
        FileFact(path: path, bytes: bytes, modified: now.addingTimeInterval(-ageDays * 86_400), isDirectory: dir)
    }

    func testMediaHoardGroupsAndSamples() {
        var facts: [FileFact] = []
        for i in 0..<80 {
            facts.append(fact("/u/Pictures/trip/IMG_\(i).heic", bytes: 4_000_000, ageDays: Double(100 + i)))
        }
        facts.append(fact("/u/Pictures/trip/clip.mov", bytes: 900_000_000))
        facts.append(fact("/u/Documents/one.jpg"))
        let found = Lens.mediaHoards(facts)
        XCTAssertEqual(found.count, 1, "a lone jpg is not a hoard")
        XCTAssertEqual(found[0].kind, .mediaHoard)
        XCTAssertEqual(found[0].count, 80)
        XCTAssertEqual(found[0].count2, 1)
        XCTAssertEqual(found[0].samples.first, "/u/Pictures/trip/clip.mov", "samples lead with the largest")
        XCTAssertLessThanOrEqual(found[0].samples.count, 24)
    }

    func testScreenRecordingsSplitFromMedia() {
        let facts = (0..<5).map {
            fact("/u/Desktop/Screen Recording 2024-0\($0).mov", bytes: 800_000_000)
        }
        let found = Lens.mediaHoards(facts)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].kind, .screenRecordings)
    }

    /// ~/Downloads speaks in large files of any type, direct children only;
    /// media there never forms an album, but a subfolder album still can.
    func testDownloadsPileCountsLargeFilesOfAnyType() {
        let facts = [
            fact("/u/Downloads/installer.dmg", bytes: 2_000_000_000),
            fact("/u/Downloads/talk.mov", bytes: 1_500_000_000),
            fact("/u/Downloads/dataset.zip", bytes: 300_000_000),
            fact("/u/Downloads/note.pdf", bytes: 5_000_000),
            fact("/u/Downloads/sub/huge.iso", bytes: 2_000_000_000),
        ]
        let pile = try! XCTUnwrap(Lens.downloadsPile(facts, downloads: "/u/Downloads"))
        XCTAssertEqual(pile.kind, .downloads)
        XCTAssertEqual(pile.count, 3, "small files and nested files stay out")
        XCTAssertEqual(pile.bytes, 3_800_000_000)
        XCTAssertEqual(pile.evidenceLine, "3 large files")
        XCTAssertNil(Lens.downloadsPile([fact("/u/Downloads/one.zip", bytes: 200_000_000)],
                                        downloads: "/u/Downloads"),
                     "a quiet Downloads earns no row")
    }

    func testMediaHoardsLeaveDownloadsRootToThePile() {
        var facts = (0..<70).map { fact("/u/Downloads/IMG_\($0).heic", bytes: 30_000_000) }
        facts += (0..<70).map { fact("/u/Downloads/trip/IMG_\($0).heic", bytes: 30_000_000) }
        let found = Lens.mediaHoards(facts, downloads: "/u/Downloads")
        XCTAssertEqual(found.map(\.url.path), ["/u/Downloads/trip"],
                       "the root defers to the pile; the subfolder album stays")
    }

    func testInstallerMatchesInstalledApp() {
        let facts = [
            fact("/u/Downloads/Docker-4.30-arm64.dmg", bytes: 600_000_000),
            fact("/u/Downloads/mystery-tool.dmg", bytes: 300_000_000),
            fact("/u/Desktop/Docker.dmg", bytes: 500_000_000),
        ]
        let found = Lens.installers(facts, downloads: "/u/Downloads", installedApps: ["Docker", "Xcode"])
        XCTAssertEqual(found.count, 1, "unmatched and out-of-Downloads installers stay quiet")
        XCTAssertEqual(found[0].label, "Docker")
    }

    func testStrataBucketsByAge() {
        let facts = [
            fact("/u/Downloads/new.zip", bytes: 100, ageDays: 2),
            fact("/u/Downloads/old.zip", bytes: 200, ageDays: 400),
            fact("/u/Downloads/sub/deep.zip", bytes: 400, ageDays: 2),
        ]
        let found = Lens.strata(facts, downloads: "/u/Downloads", now: now)
        XCTAssertEqual(found.count, 2, "only Downloads' own top level stratifies")
        XCTAssertEqual(found.first { $0.label == "week" }?.bytes, 100)
        XCTAssertEqual(found.first { $0.label == "ancient" }?.bytes, 200)
    }

    func testTwinsPairByInjectedHash() {
        let facts = [
            fact("/u/a/movie.mp4", bytes: 300_000_000),
            fact("/u/b/movie copy.mp4", bytes: 300_000_000),
            fact("/u/c/other.mp4", bytes: 300_000_000),
            fact("/u/d/small.mp4", bytes: 1_000),
        ]
        let found = Lens.twins(facts) { path in path.contains("movie") ? 7 : 9 }
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].url.path, "/u/a/movie.mp4")
        XCTAssertEqual(found[0].counterpart?.path, "/u/b/movie copy.mp4")
    }

    func testZipShadowNeedsExpandedSibling() {
        let facts = [
            fact("/u/dl/dataset.zip", bytes: 50_000_000),
            fact("/u/dl/dataset", dir: true),
            fact("/u/dl/lonely.zip", bytes: 50_000_000),
            fact("/u/dl/bundle.tar.gz", bytes: 50_000_000),
            fact("/u/dl/bundle", dir: true),
        ]
        let found = Lens.zipShadows(facts)
        XCTAssertEqual(Set(found.map(\.url.lastPathComponent)), ["dataset.zip", "bundle.tar.gz"])
        XCTAssertEqual(found.first { $0.url.lastPathComponent == "bundle.tar.gz" }?.counterpart?.path, "/u/dl/bundle")
    }

    func testProjectsSizeNetOfNamedInsides() {
        let seeds = [
            Lens.ProjectSeed(path: "/u/work/acme", marker: "Git", bytes: 3_000_000_000,
                             sourceTouched: now.addingTimeInterval(-90 * 86_400)),
            Lens.ProjectSeed(path: "/u/work/thin", marker: "JavaScript", bytes: 900_000_000,
                             sourceTouched: nil, fallbackTouched: now),
        ]
        let named: [(String, Int64)] = [
            ("/u/work/acme/node_modules", 1_200_000_000),
            ("/u/work/thin/node_modules", 600_000_000),
            ("/u/elsewhere/target", 999_999_999),
        ]
        let found = Lens.projects(seeds, home: "/u", excluding: named)
        XCTAssertEqual(found.count, 1, "thin nets out under the floor")
        XCTAssertEqual(found[0].kind, .project)
        XCTAssertEqual(found[0].bytes, 1_800_000_000, "colony bytes never count twice")
        XCTAssertEqual(found[0].label, "Git")
        XCTAssertEqual(found[0].date, seeds[0].sourceTouched)
    }

    func testProjectsFoldNestedAndSkipHiddenTerritory() {
        func seed(_ path: String) -> Lens.ProjectSeed {
            Lens.ProjectSeed(path: path, marker: "Git", bytes: 2_000_000_000, sourceTouched: now)
        }
        let found = Lens.projects([
            seed("/u/work/mono"),
            seed("/u/work/mono/vendor/dep"),   // folds into its outermost root
            seed("/u/.oh-my-zsh"),             // dot territory is tool-managed
            seed("/u/Library/Vendor/tool"),    // ~/Library is never lens land
            seed("/u/Downloads"),              // a stray manifest names no project
            seed("/u/Downloads/cloned"),       // but a repo inside still counts
            seed("/opt/elsewhere"),            // outside the home tree
        ], home: "/u", excluding: [])
        XCTAssertEqual(found.map(\.url.path).sorted(), ["/u/Downloads/cloned", "/u/work/mono"])
        XCTAssertEqual(found.first { $0.url.path == "/u/work/mono" }?.bytes, 2_000_000_000,
                       "a nested repo folds in; it never subtracts")
    }

    /// "pike-old" sorts between "pike" and "pike/server", so folding must
    /// not lean on sort adjacency (found live on the first real scan).
    func testProjectsFoldNestsAcrossSortNeighbors() {
        func seed(_ path: String) -> Lens.ProjectSeed {
            Lens.ProjectSeed(path: path, marker: "Git", bytes: 2_000_000_000, sourceTouched: now)
        }
        let found = Lens.projects(
            [seed("/u/projects/pike"), seed("/u/projects/pike-old"), seed("/u/projects/pike/server")],
            home: "/u", excluding: []
        )
        XCTAssertEqual(found.map(\.url.path).sorted(), ["/u/projects/pike", "/u/projects/pike-old"])
    }

    func testProjectEvidenceLineSpeaksSources() {
        // evidenceLine reads the real clock, so the fixture date must too.
        let finding = LensFinding(kind: .project, url: URL(fileURLWithPath: "/u/work/acme"),
                                  bytes: 2_000_000_000, label: "Git",
                                  date: Date(timeIntervalSinceNow: -150 * 86_400))
        XCTAssertTrue(finding.evidenceLine.hasPrefix("Git project"))
        XCTAssertTrue(finding.evidenceLine.contains("untouched"), "staleness rides the evidence line")
        XCTAssertEqual(finding.displayTitle, "acme")
    }

    /// ~/Downloads is a waypoint, not an album: the row keeps its media
    /// evidence but wears a download face instead of the photo fan.
    func testDownloadsRootNeverWearsTheFan() {
        let downloads = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        let atRoot = LensFinding(kind: .mediaHoard, url: downloads, bytes: 2_000_000_000)
        XCTAssertTrue(atRoot.isDownloadsRoot)
        XCTAssertFalse(atRoot.wearsMediaFan)
        let album = LensFinding(kind: .mediaHoard,
                                url: downloads.appendingPathComponent("trip"), bytes: 2_000_000_000)
        XCTAssertFalse(album.isDownloadsRoot)
        XCTAssertTrue(album.wearsMediaFan)
    }

    func testGhostsShrinkByWhatOtherRowsName() {
        let install = now.addingTimeInterval(-2 * 365 * 86_400)
        let old = install.addingTimeInterval(-86_400)
        // A migrated tree whose insides are mostly one named project: the
        // ghost row keeps only the remainder, and drops under the floor.
        let dropped = Lens.ghosts(dirNewest: ["/u/old-code": (bytes: 3_000_000_000, newest: old)],
                                  installDate: install,
                                  excluding: [("/u/old-code/acme", 2_600_000_000)])
        XCTAssertTrue(dropped.isEmpty)
        let kept = Lens.ghosts(dirNewest: ["/u/old-code": (bytes: 3_000_000_000, newest: old)],
                               installDate: install,
                               excluding: [("/u/old-code/acme", 1_000_000_000)])
        XCTAssertEqual(kept.first?.bytes, 2_000_000_000)
        // Telltale names stay listed no matter how small they net out.
        let marked = Lens.ghosts(dirNewest: ["/u/Relocated Items": (bytes: 600_000_000, newest: old)],
                                 installDate: install,
                                 excluding: [("/u/Relocated Items/proj", 550_000_000)])
        XCTAssertEqual(marked.first?.bytes, 50_000_000)
    }

    func testGhostsByNameAndByDate() {
        let install = now.addingTimeInterval(-2 * 365 * 86_400)
        let found = Lens.ghosts(dirNewest: [
            "/u/Relocated Items": (bytes: 1_000, newest: now),
            "/u/old-projects": (bytes: 2_000_000_000, newest: install.addingTimeInterval(-86_400)),
            "/u/current": (bytes: 5_000_000_000, newest: now),
        ], installDate: install)
        XCTAssertEqual(Set(found.map(\.url.lastPathComponent)), ["Relocated Items", "old-projects"])
    }

    func testVMsAndWeights() {
        let facts = [
            fact("/u/VMs/Windows 11.utm", bytes: 60_000_000_000, dir: true),
            fact("/u/isos/ubuntu-24.iso", bytes: 5_000_000_000),
            fact("/u/models/llama-70b.gguf", bytes: 40_000_000_000),
            fact("/u/models/tiny.gguf", bytes: 1_000),
        ]
        let vms = Lens.vms(facts)
        XCTAssertEqual(vms.count, 2)
        XCTAssertEqual(vms.first { $0.url.lastPathComponent == "Windows 11.utm" }?.label, "Windows")
        let weights = Lens.weights(facts)
        XCTAssertEqual(weights.count, 1)
        XCTAssertEqual(weights[0].label, "70B")
    }

    func testSteamManifestParses() {
        let acf = """
        "AppState" {
            "appid" "255710"
            "name" "Cities: Skylines"
            "installdir" "Cities_Skylines"
            "LastUpdated" "1650000000"
            "SizeOnDisk" "41000000000"
        }
        """
        let found = Lens.steamGames(fromACF: acf, libraryPath: "/s/steamapps")
        XCTAssertEqual(found?.label, "Cities: Skylines")
        XCTAssertEqual(found?.bytes, 41_000_000_000)
        XCTAssertEqual(found?.url.path, "/s/steamapps/common/Cities_Skylines")
    }
}
