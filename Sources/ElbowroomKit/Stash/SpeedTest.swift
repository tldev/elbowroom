import Foundation

/// Destination speed test: up to 10 s, 1 GB temp write, result phrased
/// plainly. Threshold judgment: sustained writes above 300 MB/s are fine for
/// build folders; below that, archives and weights only.
public enum SpeedTest {
    public struct Result: Sendable {
        public let bytesPerSecond: Double
        public var fastEnoughForBuilds: Bool { bytesPerSecond >= 300_000_000 }
        public var line: String {
            fastEnoughForBuilds
                ? Copy.speedFast(ByteFormat.rate(bytesPerSecond))
                : Copy.speedSlow(ByteFormat.rate(bytesPerSecond))
        }
    }

    /// Write 64 MB chunks up to 1 GB or 10 s, whichever first; delete the file;
    /// return the sustained rate.
    public static func run(on volume: URL) async -> Result {
        let target = volume.appendingPathComponent(".elbowroom-speedtest.tmp")
        let chunk = Data(count: 64 * 1_048_576)
        let deadline = Date().addingTimeInterval(10)
        let maxBytes: Int64 = 1_000_000_000

        return await Task.detached(priority: .userInitiated) {
            var written: Int64 = 0
            let start = Date()
            FileManager.default.createFile(atPath: target.path, contents: nil)
            defer { try? FileManager.default.removeItem(at: target) }
            guard let handle = try? FileHandle(forWritingTo: target) else {
                return Result(bytesPerSecond: 0)
            }
            defer { try? handle.close() }
            while Date() < deadline, written < maxBytes {
                do {
                    try handle.write(contentsOf: chunk)
                    try handle.synchronize()
                    written += Int64(chunk.count)
                } catch { break }
            }
            let elapsed = max(Date().timeIntervalSince(start), 0.1)
            return Result(bytesPerSecond: Double(written) / elapsed)
        }.value
    }

    /// Connection speed sampled once during onboarding via a short CDN
    /// fetch, used only to phrase re-download times.
    public static func sampleConnection() async -> Double? {
        guard let url = URL(string: "https://speed.cloudflare.com/__down?bytes=10000000") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        let start = Date()
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let elapsed = max(Date().timeIntervalSince(start), 0.05)
            guard data.count > 100_000 else { return nil }
            return Double(data.count) / elapsed
        } catch {
            return nil
        }
    }
}
