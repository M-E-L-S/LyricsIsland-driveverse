import Foundation

enum LyricsSource: String, Codable, Equatable, Hashable {
    case kugou
    case netease
    case lrclib

    var title: LocalizedStringResource {
        switch self {
        case .kugou: return "Kugou Music"
        case .netease: return "NetEase Cloud Music"
        case .lrclib: return "LRCLIB"
        }
    }
}

enum LyricsTiming: String, Codable, Equatable, Hashable {
    case wordSynced
    case synced
    case plain
}

struct LyricWordTiming: Codable, Equatable, Hashable {
    let startTimeMs: Int
    let endTimeMs: Int
    let original: String
}

struct LyricsTrackMetadata: Codable, Equatable {
    let title: String?
    let artists: [String]
    let album: String?
    let durationMs: Int?
}

/// Provider-neutral lyric line. Original text is immutable; presentation
/// options derive converted or transliterated text without replacing it.
struct LyricsLine: Codable, Equatable, Hashable {
    let startTimeMs: Int
    let endTimeMs: Int?
    let original: String
    let translation: String?
    let transliteration: String?
    let words: [LyricWordTiming]?

    init(
        startTimeMs: Int,
        endTimeMs: Int? = nil,
        original: String,
        translation: String? = nil,
        transliteration: String? = nil,
        words: [LyricWordTiming]? = nil
    ) {
        self.startTimeMs = startTimeMs
        self.endTimeMs = endTimeMs
        self.original = original
        self.translation = translation
        self.transliteration = transliteration
        self.words = words
    }
}

struct LyricsDocument: Codable, Equatable {
    /// Increment whenever the on-disk structured lyric representation changes.
    static let currentFormatVersion = 3

    let source: LyricsSource
    let formatVersion: Int
    let timing: LyricsTiming
    let lines: [LyricsLine]
    let trackMetadata: LyricsTrackMetadata?

    init(
        source: LyricsSource,
        formatVersion: Int = currentFormatVersion,
        timing: LyricsTiming,
        lines: [LyricsLine],
        trackMetadata: LyricsTrackMetadata? = nil
    ) {
        self.source = source
        self.formatVersion = formatVersion
        self.timing = timing
        self.lines = lines
        self.trackMetadata = trackMetadata
    }

    static func plain(_ text: String, source: LyricsSource) -> LyricsDocument {
        LyricsDocument(
            source: source,
            timing: .plain,
            lines: [LyricsLine(startTimeMs: 0, original: text)]
        )
    }

    var isSynchronized: Bool {
        timing == .synced || timing == .wordSynced
    }

    var isWordSynced: Bool {
        timing == .wordSynced && lines.contains { $0.words?.isEmpty == false }
    }
}

enum LyricsContent: Codable, Equatable {
    case document(LyricsDocument)
    case instrumental
    case notFound

    var isNotFound: Bool {
        if case .notFound = self { return true }
        return false
    }
}

enum LyricsDisplayMode: String, CaseIterable, Identifiable {
    case original
    case originalAndTranslation
    case originalAndTransliteration

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .original: return "Original only"
        case .originalAndTranslation: return "Original + translation"
        case .originalAndTransliteration: return "Original + transliteration"
        }
    }
}

enum ChineseConversion: String, CaseIterable, Identifiable {
    case preserve
    case simplified
    case traditional

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .preserve: return "Keep original characters"
        case .simplified: return "Simplified Chinese"
        case .traditional: return "Traditional Chinese"
        }
    }
}

struct LyricsDisplayOptions: Equatable {
    var mode: LyricsDisplayMode = .originalAndTranslation
    var chineseConversion: ChineseConversion = .preserve
}

enum ChineseTextConverter {
    private static let toSimplified = StringTransform("Traditional-Simplified")
    private static let toTraditional = StringTransform("Simplified-Traditional")

    static func convert(_ text: String, using option: ChineseConversion) -> String {
        switch option {
        case .preserve:
            return text
        case .simplified:
            return text.applyingTransform(toSimplified, reverse: false) ?? text
        case .traditional:
            return text.applyingTransform(toTraditional, reverse: false) ?? text
        }
    }
}

enum LyricsTextRenderer {
    static func primary(for line: LyricsLine, options: LyricsDisplayOptions) -> String {
        ChineseTextConverter.convert(line.original, using: options.chineseConversion)
    }

    static func secondary(for line: LyricsLine, options: LyricsDisplayOptions) -> String? {
        let text: String?
        switch options.mode {
        case .original:
            text = nil
        case .originalAndTranslation:
            text = line.translation
        case .originalAndTransliteration:
            text = line.transliteration ?? Transliterator.optionalLatinized(line.original)
        }
        guard let text, !text.isEmpty, text != line.original else { return nil }
        return ChineseTextConverter.convert(text, using: options.chineseConversion)
    }
}
