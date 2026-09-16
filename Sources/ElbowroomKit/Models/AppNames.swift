import Foundation

/// Human names for ~/Library/Caches folders (system residue): a cache
/// folder is usually a reverse-DNS bundle id, and the app's name is its last
/// segment. A short override table covers the famous awkward ones. Plain
/// folder names (`Google`, `pip`) pass through untouched.
public enum AppNames {
    static let overrides: [String: String] = [
        "slackmacgap": "Slack",
        "vscode": "VS Code",
        "androidstudio": "Android Studio",
        "intellij": "IntelliJ IDEA",
        "pycharm": "PyCharm",
        "goland": "GoLand",
        "webstorm": "WebStorm",
        "rubymine": "RubyMine",
        "sublimetext": "Sublime Text",
        "iterm2": "iTerm2",
        "orbstack": "OrbStack",
        "lmstudio": "LM Studio",
    ]

    private static let dnsRoots: Set<String> = [
        "com", "org", "net", "io", "co", "dev", "app", "ai", "us", "de", "se", "sh", "gg", "im",
    ]

    /// Tail segments that name a product's shape, not the product:
    /// `com.spotify.client` is Spotify, not Client.
    private static let genericTails: Set<String> = [
        "client", "app", "desktop", "mac", "macos", "osx", "helper", "agent", "core", "main",
    ]

    public static func human(fromCacheFolder name: String) -> String {
        let segments = name.split(separator: ".").map(String.init)
        guard segments.count >= 2, let first = segments.first,
              dnsRoots.contains(first.lowercased())
        else { return name }
        var pick = segments[segments.count - 1]
        if segments.count >= 3, genericTails.contains(pick.lowercased()) {
            pick = segments[segments.count - 2]
        }
        if let override = overrides[pick.lowercased()] { return override }
        if pick.first?.isUppercase == true { return pick }
        return pick.prefix(1).uppercased() + pick.dropFirst()
    }
}
