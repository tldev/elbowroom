import Foundation

/// Localization: en-US + ja-JP. English strings are the keys (the copy
/// deck stays the single source of truth); Japanese lives in one reviewed
/// table. Multi-argument templates use positional specifiers so ja can
/// reorder. Language resolves once per launch; Settings offers an override.
public enum Loc {
    public static let overrideKey = "elbowroom.lang"

    /// "en" or "ja", resolved at launch.
    public nonisolated(unsafe) static var lang: String = detect()

    public static func detect() -> String {
        if let o = UserDefaults.standard.string(forKey: overrideKey), o == "en" || o == "ja" {
            return o
        }
        return Locale.preferredLanguages.first?.hasPrefix("ja") == true ? "ja" : "en"
    }

    /// Translate a plain string.
    public static func t(_ key: String) -> String {
        lang == "ja" ? (jaStrings[key] ?? key) : key
    }

    /// Translate a template, then interpolate.
    public static func f(_ key: String, _ args: CVarArg...) -> String {
        String(format: t(key), arguments: args)
    }
}
