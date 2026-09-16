import Foundation

/// Analytics: opt-in, anonymous, aggregates only. No paths, no file names,
/// no device fingerprinting. v1 keeps events in a local JSON file the user can
/// read; nothing leaves the Mac until a consented uploader exists.
public final class Analytics: @unchecked Sendable {
    public static let shared = Analytics()
    private let queue = DispatchQueue(label: "elbowroom.analytics")
    private let fileURL: URL

    public var enabled: Bool { SettingsStore.shared.analyticsOptIn }

    init() {
        let dir = ReceiptStore.defaultDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("analytics-local.json")
    }

    public func log(_ name: String, _ props: [String: String] = [:]) {
        guard enabled else { return }
        queue.async {
            var events = (try? JSONDecoder().decode([[String: String]].self, from: Data(contentsOf: self.fileURL))) ?? []
            var event = props
            event["event"] = name
            event["t"] = ISO8601DateFormatter().string(from: Date())
            events.append(event)
            if let data = try? JSONEncoder().encode(events) {
                try? data.write(to: self.fileURL, options: .atomic)
            }
        }
    }
}
