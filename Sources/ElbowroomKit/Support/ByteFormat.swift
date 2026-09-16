import Foundation

/// Byte display. Decimal units to reconcile with Finder and `df`.
/// The unit renders smaller and softer than the value, so the split form
/// exists for views that style the two parts separately.
public enum ByteFormat {
    public struct Split {
        public let value: String
        public let unit: String
        public var joined: String { "\(value) \(unit)" }
    }

    public static func split(_ bytes: Int64) -> Split {
        let b = Double(max(bytes, 0))
        switch b {
        case ..<1000:
            return Split(value: String(Int(b)), unit: "B")
        case ..<1_000_000:
            return Split(value: format(b / 1000), unit: "KB")
        case ..<1_000_000_000:
            return Split(value: format(b / 1_000_000), unit: "MB")
        case ..<1_000_000_000_000:
            return Split(value: format(b / 1_000_000_000), unit: "GB")
        default:
            return Split(value: format(b / 1_000_000_000_000), unit: "TB")
        }
    }

    public static func string(_ bytes: Int64) -> String { split(bytes).joined }

    /// "780 MB/s" style transfer rates, phrased plainly.
    public static func rate(_ bytesPerSecond: Double) -> String {
        let s = split(Int64(bytesPerSecond))
        return "\(s.value) \(s.unit)"
    }

    private static func format(_ v: Double) -> String {
        if v >= 100 { return String(Int(v.rounded())) }
        if v >= 10 { return String(format: "%.1f", v) }
        return String(format: "%.1f", v)
    }

    /// "about 2 min" / "about 40 sec" cost phrasing.
    public static func minutes(_ seconds: Double) -> String {
        if seconds < 50 { return "\(max(5, Int((seconds / 5).rounded() * 5))) sec" }
        let m = Int((seconds / 60).rounded())
        return "\(max(1, m)) min"
    }
}

public enum RelativeDate {
    /// "untouched 5 months", "2 weeks ago" style staleness display.
    public static func staleness(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "" }
        let days = Int(now.timeIntervalSince(date) / 86_400)
        switch days {
        case ..<1: return Copy.touchedToday
        case ..<14: return Copy.untouchedDays(days)
        case ..<60: return Copy.untouchedWeeks(days / 7)
        case ..<700: return Copy.untouchedMonths(days / 30)
        default: return Copy.untouchedYears(days / 365)
        }
    }

    public static func short(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "" }
        let days = Int(now.timeIntervalSince(date) / 86_400)
        switch days {
        case ..<1: return Copy.dateToday
        case 1: return Copy.dateYesterday
        case ..<14: return Copy.daysAgo(days)
        case ..<60: return Copy.weeksAgo(days / 7)
        case ..<700: return Copy.monthsAgo(days / 30)
        default: return Copy.yearsAgo(days / 365)
        }
    }
}
