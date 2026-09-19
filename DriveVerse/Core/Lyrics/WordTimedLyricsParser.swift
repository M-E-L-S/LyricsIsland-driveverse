import Foundation

// YRC/KRC parsing behavior was informed by Lyricify Lyrics Helper:
// https://github.com/WXRIW/Lyricify-Lyrics-Helper (Apache-2.0).

enum WordTimedLyricsParser {
    private static let yrcLineRegex = try! NSRegularExpression(
        pattern: #"^\[(\d+),(\d+)\](.*)$"#
    )
    private static let yrcWordRegex = try! NSRegularExpression(
        pattern: #"\((\d+),(\d+),\d+\)([^\(]*)"#
    )
    private static let krcLineRegex = try! NSRegularExpression(
        pattern: #"^\[(\d+),(\d+)\](.*)$"#
    )
    private static let krcWordRegex = try! NSRegularExpression(
        pattern: #"<(\d+),(\d+),\d+>([^<]*)"#
    )

    static func parseYRC(_ raw: String) -> [LyricsLine] {
        parse(raw, lineRegex: yrcLineRegex, wordRegex: yrcWordRegex, wordStartsAreRelative: false)
    }

    static func parseKRC(_ raw: String) -> [LyricsLine] {
        var lines = parse(raw, lineRegex: krcLineRegex, wordRegex: krcWordRegex, wordStartsAreRelative: true)
        let language = parseKugouLanguage(from: raw)
        for index in lines.indices {
            let old = lines[index]
            lines[index] = LyricsLine(
                startTimeMs: old.startTimeMs,
                endTimeMs: old.endTimeMs,
                original: old.original,
                translation: language.translation[safe: index],
                transliteration: language.transliteration[safe: index],
                words: old.words
            )
        }
        return lines
    }

    static func krcMetadata(_ raw: String) -> [String: String] {
        var values: [String: String] = [:]
        for line in raw.components(separatedBy: .newlines) {
            guard line.hasPrefix("["), let separator = line.firstIndex(of: ":"),
                  let end = line.lastIndex(of: "]"), separator < end else { continue }
            let keyStart = line.index(after: line.startIndex)
            let valueStart = line.index(after: separator)
            let key = String(line[keyStart..<separator]).lowercased()
            if ["ti", "ar", "al"].contains(key) {
                values[key] = String(line[valueStart..<end])
            }
        }
        return values
    }

    private static func parse(
        _ raw: String,
        lineRegex: NSRegularExpression,
        wordRegex: NSRegularExpression,
        wordStartsAreRelative: Bool
    ) -> [LyricsLine] {
        raw.components(separatedBy: .newlines).compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let match = firstMatch(lineRegex, in: line),
                  let start = intCapture(match, 1, in: line),
                  let duration = intCapture(match, 2, in: line),
                  let body = stringCapture(match, 3, in: line) else {
                return nil
            }

            let range = NSRange(body.startIndex..<body.endIndex, in: body)
            let wordMatches = wordRegex.matches(in: body, range: range)
            let words = wordMatches.compactMap { wordMatch -> LyricWordTiming? in
                guard let rawStart = intCapture(wordMatch, 1, in: body),
                      let wordDuration = intCapture(wordMatch, 2, in: body),
                      let text = stringCapture(wordMatch, 3, in: body),
                      !text.isEmpty else { return nil }
                let wordStart = wordStartsAreRelative ? start + rawStart : rawStart
                return LyricWordTiming(
                    startTimeMs: wordStart,
                    endTimeMs: wordStart + wordDuration,
                    original: text
                )
            }
            let original = words.map(\.original).joined()
            let fallback = body
                .replacingOccurrences(of: #"\([^)]*\)"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"<[^>]*>"#, with: "", options: .regularExpression)
            let text = original.isEmpty ? fallback : original
            guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return LyricsLine(
                startTimeMs: start,
                endTimeMs: start + duration,
                original: text,
                words: words.isEmpty ? nil : words
            )
        }.sorted { $0.startTimeMs < $1.startTimeMs }
    }

    private struct KugouLanguageEntry: Decodable {
        let type: Int
        let lyricContent: [[String]]
    }

    private struct KugouLanguage: Decodable {
        let content: [KugouLanguageEntry]
    }

    private static func parseKugouLanguage(from raw: String) -> (
        translation: [String], transliteration: [String]
    ) {
        guard let languageLine = raw.components(separatedBy: .newlines)
            .first(where: { $0.hasPrefix("[language:") }),
              let end = languageLine.lastIndex(of: "]") else {
            return ([], [])
        }
        let start = languageLine.index(languageLine.startIndex, offsetBy: "[language:".count)
        let encoded = String(languageLine[start..<end])
        guard let data = Data(base64Encoded: encoded),
              let language = try? JSONDecoder().decode(KugouLanguage.self, from: data) else {
            return ([], [])
        }

        func values(for type: Int) -> [String] {
            language.content.first(where: { $0.type == type })?
                .lyricContent.map { $0.joined() } ?? []
        }
        // Kugou uses type 0 for romanization and type 1 for translation.
        return (values(for: 1), values(for: 0))
    }

    private static func firstMatch(_ regex: NSRegularExpression, in text: String) -> NSTextCheckingResult? {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text))
    }

    private static func stringCapture(
        _ match: NSTextCheckingResult,
        _ index: Int,
        in text: String
    ) -> String? {
        guard let range = Range(match.range(at: index), in: text) else { return nil }
        return String(text[range])
    }

    private static func intCapture(
        _ match: NSTextCheckingResult,
        _ index: Int,
        in text: String
    ) -> Int? {
        stringCapture(match, index, in: text).flatMap(Int.init)
    }
}

enum LyricsLineMerger {
    static func merge(
        primary: [LyricsLine],
        translationRaw: String?,
        transliterationRaw: String?
    ) -> [LyricsLine] {
        let translations = timedTexts(from: translationRaw)
        let transliterations = timedTexts(from: transliterationRaw)
        return primary.map { line in
            LyricsLine(
                startTimeMs: line.startTimeMs,
                endTimeMs: line.endTimeMs,
                original: line.original,
                translation: nearestText(to: line.startTimeMs, in: translations),
                transliteration: nearestText(to: line.startTimeMs, in: transliterations),
                words: line.words
            )
        }
    }

    private static func timedTexts(from raw: String?) -> [(Int, String)] {
        guard let raw, !raw.isEmpty else { return [] }
        let yrc = WordTimedLyricsParser.parseYRC(raw)
        let lines = yrc.isEmpty ? LRCParser.parse(raw) : yrc
        return lines.map { ($0.startTimeMs, $0.original) }
    }

    private static func nearestText(to time: Int, in values: [(Int, String)]) -> String? {
        values
            .map { (distance: abs($0.0 - time), text: $0.1) }
            .filter { $0.distance <= 150 }
            .min { $0.distance < $1.distance }?
            .text
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
