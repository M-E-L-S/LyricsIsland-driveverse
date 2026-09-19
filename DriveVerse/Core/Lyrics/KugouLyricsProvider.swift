import Foundation
import Compression

// KRC retrieval/decryption behavior was informed by Lyricify Lyrics Helper:
// https://github.com/WXRIW/Lyricify-Lyrics-Helper (Apache-2.0).

struct KugouLyricsProvider: LyricsProvider {
    enum ProviderError: Error {
        case badStatus(Int)
        case invalidResponse
        case invalidKRC
    }

    let source: LyricsSource = .kugou
    private let session: URLSession
    private let searchBaseURL: URL
    private let lyricsBaseURL: URL

    init(
        session: URLSession = .shared,
        searchBaseURL: URL = URL(string: "https://lyrics.kugou.com")!,
        lyricsBaseURL: URL = URL(string: "https://lyrics.kugou.com")!
    ) {
        self.session = session
        self.searchBaseURL = searchBaseURL
        self.lyricsBaseURL = lyricsBaseURL
    }

    func search(for query: LyricsSearchQuery, limit: Int) async throws -> [LyricsCandidate] {
        let keyword = ([query.title] + query.artists).joined(separator: " ")
        var queryItems = [
            URLQueryItem(name: "ver", value: "1"),
            URLQueryItem(name: "man", value: "yes"),
            URLQueryItem(name: "client", value: "pc"),
            URLQueryItem(name: "keyword", value: keyword),
        ]
        if let duration = query.durationMs {
            queryItems.append(URLQueryItem(name: "duration", value: String(duration)))
        }
        let data = try await get(
            baseURL: searchBaseURL,
            path: "/search",
            queryItems: queryItems
        )
        let response = try JSONDecoder().decode(KugouLyricsSearchResponse.self, from: data)
        return response.candidates.prefix(limit).map { item in
            LyricsCandidate(
                identifier: item.id,
                source: .kugou,
                title: item.song ?? query.title,
                artists: LyricsMatcher.splitArtists(item.singer ?? ""),
                album: nil,
                durationMs: item.duration,
                metadata: ["lyricID": item.id, "accessKey": item.accessKey]
            )
        }
    }

    func lyrics(for candidate: LyricsCandidate) async throws -> LyricsContent {
        let token: KugouLyricsSearchResponse.Candidate
        if let accessKey = candidate.metadata["accessKey"] {
            token = KugouLyricsSearchResponse.Candidate(
                id: candidate.metadata["lyricID"] ?? candidate.identifier,
                accessKey: accessKey,
                singer: nil,
                song: nil,
                duration: nil
            )
        } else {
            let keyword = ([candidate.title] + candidate.artists).joined(separator: " ")
            var searchItems = [
                URLQueryItem(name: "ver", value: "1"),
                URLQueryItem(name: "man", value: "yes"),
                URLQueryItem(name: "client", value: "pc"),
                URLQueryItem(name: "keyword", value: keyword),
            ]
            if let duration = candidate.durationMs {
                searchItems.append(URLQueryItem(name: "duration", value: String(duration)))
            }
            let searchData = try await get(
                baseURL: lyricsBaseURL,
                path: "/search",
                queryItems: searchItems
            )
            let search = try JSONDecoder().decode(KugouLyricsSearchResponse.self, from: searchData)
            guard let first = search.candidates.first else { return .notFound }
            token = first
        }

        let downloadData = try await get(
            baseURL: lyricsBaseURL,
            path: "/download",
            queryItems: [
                URLQueryItem(name: "ver", value: "1"),
                URLQueryItem(name: "client", value: "pc"),
                URLQueryItem(name: "id", value: token.id),
                URLQueryItem(name: "accesskey", value: token.accessKey),
                URLQueryItem(name: "fmt", value: "krc"),
                URLQueryItem(name: "charset", value: "utf8"),
            ]
        )
        let download = try JSONDecoder().decode(KugouLyricsDownloadResponse.self, from: downloadData)
        guard let raw = Self.decodeKRC(download.content) else { throw ProviderError.invalidKRC }
        let lines = WordTimedLyricsParser.parseKRC(raw)
        guard !lines.isEmpty else { return .notFound }
        let tags = WordTimedLyricsParser.krcMetadata(raw)
        let timing: LyricsTiming = lines.contains { $0.words?.isEmpty == false } ? .wordSynced : .synced
        return .document(LyricsDocument(
            source: .kugou,
            timing: timing,
            lines: lines,
            trackMetadata: LyricsTrackMetadata(
                title: tags["ti"],
                artists: tags["ar"].map { LyricsMatcher.splitArtists($0) } ?? candidate.artists,
                album: tags["al"],
                durationMs: candidate.durationMs
            )
        ))
    }

    private func get(baseURL: URL, path: String, queryItems: [URLQueryItem]) async throws -> Data {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = queryItems
        guard let url = components.url else { throw ProviderError.invalidResponse }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("DriveVerse/1.0 personal project", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ProviderError.invalidResponse }
        guard http.statusCode == 200 else { throw ProviderError.badStatus(http.statusCode) }
        return data
    }

    static func decodeKRC(_ encoded: String) -> String? {
        guard let encrypted = Data(base64Encoded: encoded),
              encrypted.count > 4,
              String(data: encrypted.prefix(4), encoding: .ascii) == "krc1" else {
            return nil
        }
        let key: [UInt8] = [
            0x40, 0x47, 0x61, 0x77, 0x5e, 0x32, 0x74, 0x47,
            0x51, 0x36, 0x31, 0x2d, 0xce, 0xd2, 0x6e, 0x69,
        ]
        let compressed = Array(encrypted.dropFirst(4)).enumerated().map { index, byte in
            byte ^ key[index % key.count]
        }

        // Kugou stores a complete RFC 1950 zlib stream. Apple's
        // COMPRESSION_ZLIB decoder, despite its name, consumes the raw RFC 1951
        // DEFLATE payload, so remove the zlib header and Adler-32 trailer first.
        // Keep the original bytes as a fallback for nonstandard/raw fixtures.
        let payload = zlibDeflatePayload(from: compressed) ?? compressed

        var capacity = max(64 * 1024, payload.count * 4)
        while capacity <= 8 * 1024 * 1024 {
            var output = [UInt8](repeating: 0, count: capacity)
            let decodedCount = payload.withUnsafeBytes { sourceBuffer in
                output.withUnsafeMutableBytes { destinationBuffer in
                    guard let source = sourceBuffer.bindMemory(to: UInt8.self).baseAddress,
                          let destination = destinationBuffer.bindMemory(to: UInt8.self).baseAddress else {
                        return 0
                    }
                    return compression_decode_buffer(
                        destination,
                        capacity,
                        source,
                        payload.count,
                        nil,
                        COMPRESSION_ZLIB
                    )
                }
            }
            if decodedCount > 0, decodedCount < capacity {
                return String(bytes: output.prefix(decodedCount), encoding: .utf8)
            }
            capacity *= 2
        }
        return nil
    }

    private static func zlibDeflatePayload(from bytes: [UInt8]) -> [UInt8]? {
        // CMF + FLG, at least one DEFLATE byte, and the four-byte Adler-32.
        guard bytes.count >= 7 else { return nil }
        let cmf = bytes[0]
        let flg = bytes[1]
        guard (cmf & 0x0f) == 8, // DEFLATE
              (Int(cmf) * 256 + Int(flg)) % 31 == 0 else {
            return nil
        }

        var payloadStart = 2
        if (flg & 0x20) != 0 { // FDICT adds a four-byte dictionary identifier.
            payloadStart += 4
        }
        let payloadEnd = bytes.count - 4
        guard payloadStart < payloadEnd else { return nil }
        return Array(bytes[payloadStart..<payloadEnd])
    }
}

private struct KugouLyricsSearchResponse: Decodable {
    struct Candidate: Decodable {
        let id: String
        let accessKey: String
        let singer: String?
        let song: String?
        let duration: Int?

        enum CodingKeys: String, CodingKey {
            case id
            case accessKey = "accesskey"
            case singer, song, duration
        }

        init(id: String, accessKey: String, singer: String?, song: String?, duration: Int?) {
            self.id = id
            self.accessKey = accessKey
            self.singer = singer
            self.song = song
            self.duration = duration
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            if let string = try? values.decode(String.self, forKey: .id) {
                id = string
            } else {
                id = String(try values.decode(Int64.self, forKey: .id))
            }
            accessKey = try values.decode(String.self, forKey: .accessKey)
            singer = try values.decodeIfPresent(String.self, forKey: .singer)
            song = try values.decodeIfPresent(String.self, forKey: .song)
            duration = try values.decodeIfPresent(Int.self, forKey: .duration)
        }
    }

    let candidates: [Candidate]
}

private struct KugouLyricsDownloadResponse: Decodable {
    let content: String
}
