import Foundation

/// Optional, presentation-only romanization using Foundation's offline ICU
/// transforms. Original lyric text is never replaced with this result.
enum Transliterator {
    static func latinized(_ text: String) -> String {
        guard needsLatinization(text) else { return text }
        let latin = text.applyingTransform(.toLatin, reverse: false) ?? text
        return latin.applyingTransform(.stripDiacritics, reverse: false) ?? latin
    }

    static func optionalLatinized(_ text: String) -> String? {
        guard needsLatinization(text) else { return nil }
        let value = latinized(text)
        return value == text ? nil : value
    }

    /// True when the text contains characters from a non-Latin script.
    static func needsLatinization(_ text: String) -> Bool {
        text.range(of: "[^\\p{Latin}\\p{Common}\\p{Inherited}]", options: .regularExpression) != nil
    }
}
