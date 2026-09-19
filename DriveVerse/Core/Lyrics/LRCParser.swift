import Foundation

/// Pure LRC parser. No I/O, no state — heavily unit-tested.
enum LRCParser {
    /// Parses LRC text into time-sorted, non-empty lyric lines.
    ///
    /// Supports multiple timestamp tags per line (`[00:10.00][00:45.00]Chorus`),
    /// `[mm:ss]`, `[mm:ss.x]`–`[mm:ss.xxx]`, and `[mm:ss:xx]` timestamps, and the
    /// `[offset:±ms]` tag (positive offset shifts lyrics earlier, per LRC
    /// convention). Metadata tags (`[ar:]`, `[ti:]`, `[al:]`, …) are ignored.
    static func parse(_ raw: String) -> [LyricsLine] {
        var offsetMs = 0
        var entries: [(timeMs: Int, text: String, order: Int)] = []
        var order = 0

        for rawLine in raw.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("[") else { continue }

            var times: [Int] = []
            var rest = Substring(line)
            while rest.first == "[", let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                rest = rest[rest.index(after: close)...]
                if let ms = timestampMs(tag) {
                    times.append(ms)
                } else if let offset = offsetValue(tag) {
                    offsetMs = offset
                }
                // else: metadata tag — ignore
            }

            let text = rest.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            for time in times {
                entries.append((time, text, order))
                order += 1
            }
        }

        let sorted = entries
            .sorted { lhs, rhs in
                lhs.timeMs == rhs.timeMs ? lhs.order < rhs.order : lhs.timeMs < rhs.timeMs
            }

        var groups: [(timeMs: Int, texts: [String])] = []
        for entry in sorted {
            if let last = groups.indices.last, groups[last].timeMs == entry.timeMs {
                if !groups[last].texts.contains(entry.text) {
                    groups[last].texts.append(entry.text)
                }
            } else {
                groups.append((entry.timeMs, [entry.text]))
            }
        }

        // Group before applying the offset: clamping two distinct early
        // timestamps to zero must not misclassify them as bilingual variants.
        groups = groups.map {
            (timeMs: max(0, $0.timeMs - offsetMs), texts: $0.texts)
        }

        return groups.enumerated().map { index, group in
            let endTimeMs = index + 1 < groups.count ? groups[index + 1].timeMs : nil
            let translation = group.texts.count > 1 ? group.texts[1] : nil
            let transliteration = group.texts.count > 2
                ? group.texts.dropFirst(2).joined(separator: "\n")
                : nil
            return LyricsLine(
                startTimeMs: group.timeMs,
                endTimeMs: endTimeMs,
                original: group.texts[0],
                translation: translation,
                transliteration: transliteration
            )
        }
    }

    /// `mm:ss`, `mm:ss.frac` (1–3 digits), or `mm:ss:frac`. Returns nil for
    /// anything else, which is how metadata tags are filtered out.
    private static func timestampMs(_ tag: Substring) -> Int? {
        let comps = tag.split(separator: ":")
        guard comps.count == 2 || comps.count == 3, let minutes = Int(comps[0]) else { return nil }

        var secondsPart = comps[1]
        var fracPart: Substring? = comps.count == 3 ? comps[2] : nil
        if fracPart == nil, let dot = secondsPart.firstIndex(of: ".") {
            fracPart = secondsPart[secondsPart.index(after: dot)...]
            secondsPart = secondsPart[..<dot]
        }
        guard let seconds = Int(secondsPart), minutes >= 0, (0..<60).contains(seconds) else { return nil }

        var fracMs = 0
        if let frac = fracPart, !frac.isEmpty {
            let digits = frac.prefix(3)
            guard let value = Int(digits) else { return nil }
            switch digits.count {
            case 1: fracMs = value * 100
            case 2: fracMs = value * 10
            default: fracMs = value
            }
        }
        return (minutes * 60 + seconds) * 1000 + fracMs
    }

    private static func offsetValue(_ tag: Substring) -> Int? {
        let lower = tag.lowercased()
        guard lower.hasPrefix("offset:") else { return nil }
        return Int(lower.dropFirst("offset:".count).trimmingCharacters(in: .whitespaces))
    }
}
