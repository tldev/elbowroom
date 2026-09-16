import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Ask Kibi. For unrecognized folders ≥ 500 MB, the on-device model gets
/// the folder name, up to 40 child names, owning-bundle hints, and byte
/// totals; never file contents; no network. The output is at most two
/// sentences of identity plus a tier *suggestion* rendered as a dashed chip.
/// Guessed tiers never enable bulk selection and never count toward headroom.
/// If Apple Intelligence is unavailable, the feature hides entirely.
public enum AskKibi {
    public struct Guess: Sendable {
        public let text: String
        /// A suggestion only; nil when the model declined or was unsure.
        public let tier: Tier?
    }

    public static let minimumBytes: Int64 = 500 * 1_000_000

    public static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return SystemLanguageModel.default.availability == .available
        }
        #endif
        return false
    }

    /// Ask about one folder. Returns nil when unavailable, on low confidence,
    /// or on any model error; the card then falls back to showing children.
    public static func explain(folderName: String, childNames: [String], bytes: Int64) async -> Guess? {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *) else { return nil }
        guard SystemLanguageModel.default.availability == .available else { return nil }

        let children = childNames.prefix(40).joined(separator: ", ")
        let language = Loc.lang == "ja" ? "Japanese" : "English"
        let instructions = """
        You explain folders on a Mac to a non-expert in plain \(language). \
        You see only a folder name, its size, and some child names, never file contents. \
        Reply with at most two short sentences saying what the folder most likely is and \
        whether tools recreate it. Then on a new line write exactly one of: \
        TIER: regenerable | TIER: rebuildable | TIER: managed | TIER: yours | TIER: unknown. \
        Choose TIER: unknown whenever you are not confident. Never use exclamation points or em dashes.
        """
        let prompt = """
        Folder name: \(folderName)
        Size: \(ByteFormat.string(bytes))
        Child names: \(children.isEmpty ? "(none visible)" : children)
        """
        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: prompt)
            return parse(response.content)
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

    static func parse(_ raw: String) -> Guess? {
        var tier: Tier?
        var lines: [String] = []
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let range = trimmed.range(of: "TIER:", options: [.caseInsensitive]) {
                let value = trimmed[range.upperBound...]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                tier = Tier(rawValue: value) // "unknown" maps to nil
            } else {
                lines.append(trimmed)
            }
        }
        // Contract: at most two sentences; trim anything longer.
        let text = lines.joined(separator: " ")
        guard !text.isEmpty else { return nil }
        let sentences = text.split(separator: ".", omittingEmptySubsequences: true)
        let clipped = sentences.prefix(2).joined(separator: ".")
        return Guess(text: clipped.hasSuffix(".") ? clipped : clipped + ".", tier: tier)
    }
}
