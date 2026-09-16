import Foundation

/// Connection speed sampling. The measured rate only phrases re-download
/// times; nothing uploads.
public enum SpeedTest {
    /// Sampled once during onboarding via a short CDN fetch, refreshable
    /// from Settings.
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
