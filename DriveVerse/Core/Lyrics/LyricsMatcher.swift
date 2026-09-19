import Foundation

/// Title/artist normalization for querying LRCLIB and for cache keys.
enum LyricsMatcher {
    /// "Song (feat. X) - Remix" → "song"
    static func normalizeTitle(_ raw: String) -> String {
        var s = raw.lowercased()
        s = stripBracketed(s)
        if let dash = s.range(of: " - ") {
            s = String(s[..<dash.lowerBound])
        }
        s = stripFeatClause(s)
        return collapseWhitespace(s)
    }

    /// "Rihanna feat. JAY-Z" → "rihanna"
    static func normalizeArtist(_ raw: String) -> String {
        var s = raw.lowercased()
        s = stripBracketed(s)
        s = stripFeatClause(s)
        return collapseWhitespace(s)
    }

    static func normalizeAlbum(_ raw: String) -> String {
        collapseWhitespace(stripBracketed(raw.lowercased()))
    }

    static func splitArtists(_ raw: String) -> [String] {
        var value = raw.lowercased()
        for marker in [" featuring ", " feat. ", " feat ", " ft. ", " ft ", " with ", " & ", "、", ";", ",", "/"] {
            value = value.replacingOccurrences(of: marker, with: "|")
        }
        let artists = value.split(separator: "|")
            .map { collapseWhitespace(stripBracketed(String($0))) }
            .filter { !$0.isEmpty }
        return artists.isEmpty ? [normalizeArtist(raw)] : artists
    }

    static func titlesMatch(_ lhs: String, _ rhs: String) -> Bool {
        normalizeTitle(lhs) == normalizeTitle(rhs)
            && versionTerms(in: lhs) == versionTerms(in: rhs)
    }

    static func artistsMatch(_ lhs: [String], _ rhs: [String]) -> Bool {
        let wanted = Set(lhs.flatMap { splitArtists($0) }.map { normalizeArtist($0) }.filter { !$0.isEmpty })
        let actual = Set(rhs.flatMap { splitArtists($0) }.map { normalizeArtist($0) }.filter { !$0.isEmpty })
        if wanted.isEmpty { return true }
        return wanted == actual
    }

    static func albumsMatch(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs, !lhs.isEmpty else { return true }
        guard let rhs, !rhs.isEmpty else { return false }
        return normalizeAlbum(lhs) == normalizeAlbum(rhs)
    }

    /// Cache key for a track. Duration is bucketed to 5 s so slightly different
    /// reports of the same track usually share one cache entry.
    static func signature(
        title: String,
        artist: String,
        durationMs: Int?,
        album: String? = nil
    ) -> String {
        let bucket = durationMs.map { Int((Double($0) / 5000.0).rounded()) } ?? -1
        var base = "\(normalizeTitle(title))|\(normalizeArtist(artist))|\(bucket)"
        if let album, !album.isEmpty {
            base += "|album:\(normalizeAlbum(album))"
        }
        let versions = versionTerms(in: title).sorted().joined(separator: ",")
        return versions.isEmpty ? base : "\(base)|\(versions)"
    }

    /// Picks the `/api/search` result whose normalized title matches and whose
    /// duration is within ±3 s (when we know ours); prefers synced lyrics.
    static func bestMatch(from candidates: [LRCLIBResponse], title: String, durationMs: Int?) -> LRCLIBResponse? {
        let wantedTitle = normalizeTitle(title)
        let matches = candidates.filter { candidate in
            guard normalizeTitle(candidate.trackName ?? "") == wantedTitle else { return false }
            guard let durationMs else { return true }
            guard let duration = candidate.duration else { return false }
            return abs(duration * 1000 - Double(durationMs)) <= 3000
        }
        return matches.first { $0.syncedLyrics?.isEmpty == false } ?? matches.first
    }

    // MARK: - Helpers

    /// Removes every `(…)` and `[…]` segment.
    private static func stripBracketed(_ s: String) -> String {
        var out = ""
        var depth = 0
        for ch in s {
            if ch == "(" || ch == "[" {
                depth += 1
            } else if ch == ")" || ch == "]" {
                if depth > 0 { depth -= 1 }
            } else if depth == 0 {
                out.append(ch)
            }
        }
        return out
    }

    private static let featMarkers = [" feat. ", " feat ", " featuring ", " ft. ", " ft "]

    private static func stripFeatClause(_ s: String) -> String {
        var s = s
        for marker in featMarkers {
            if let r = s.range(of: marker) {
                s = String(s[..<r.lowerBound])
            }
        }
        return s
    }

    private static func collapseWhitespace(_ s: String) -> String {
        s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Keeps materially different releases from becoming a false title hit
    /// after bracket/suffix normalization.
    private static func versionTerms(in raw: String) -> Set<String> {
        let text = raw.lowercased()
        let groups: [(String, [String])] = [
            ("live", ["live", "现场", "演唱会"]),
            ("instrumental", ["instrumental", "伴奏", "纯音乐"]),
            ("cover", ["cover", "翻唱"]),
            ("remaster", ["remaster", "remastered", "重制"]),
            ("acoustic", ["acoustic", "不插电"]),
            ("karaoke", ["karaoke", "卡拉ok"]),
        ]
        return Set(groups.compactMap { canonical, terms in
            terms.contains(where: { text.contains($0) }) ? canonical : nil
        })
    }
}
