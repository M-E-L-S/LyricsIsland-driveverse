import Foundation

struct NeteaseLyricsProvider: LyricsProvider {
    enum ProviderError: Error {
        case badStatus(Int)
        case invalidResponse
    }

    let source: LyricsSource = .netease
    private let session: URLSession
    private let baseURL: URL

    init(
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://music.163.com")!
    ) {
        self.session = session
        self.baseURL = baseURL
    }

    func search(for query: LyricsSearchQuery, limit: Int) async throws -> [LyricsCandidate] {
        let keyword = ([query.title] + query.artists).joined(separator: " ")
        let data = try await get(
            path: "/api/search/get/web",
            queryItems: [
                URLQueryItem(name: "s", value: keyword),
                URLQueryItem(name: "type", value: "1"),
                URLQueryItem(name: "offset", value: "0"),
                URLQueryItem(name: "total", value: "true"),
                URLQueryItem(name: "limit", value: String(limit)),
            ]
        )
        let response = try JSONDecoder().decode(NeteaseSearchResponse.self, from: data)
        return response.result?.songs.prefix(limit).map { song in
            LyricsCandidate(
                identifier: String(song.id),
                source: .netease,
                title: song.name,
                artists: song.artistNames,
                album: song.albumName,
                durationMs: song.durationMs
            )
        } ?? []
    }

    func lyrics(for candidate: LyricsCandidate) async throws -> LyricsContent {
        let data = try await get(
            path: "/api/song/lyric/v1",
            queryItems: [
                URLQueryItem(name: "id", value: candidate.identifier),
                URLQueryItem(name: "cp", value: "false"),
                URLQueryItem(name: "lv", value: "0"),
                URLQueryItem(name: "kv", value: "0"),
                URLQueryItem(name: "tv", value: "0"),
                URLQueryItem(name: "rv", value: "0"),
                URLQueryItem(name: "yv", value: "0"),
                URLQueryItem(name: "ytv", value: "0"),
                URLQueryItem(name: "yrv", value: "0"),
            ]
        )
        let response = try JSONDecoder().decode(NeteaseLyricsResponse.self, from: data)
        if response.nolyric == true { return .instrumental }
        if response.uncollected == true { return .notFound }

        if let yrc = response.yrc?.lyric, !yrc.isEmpty {
            let primary = WordTimedLyricsParser.parseYRC(yrc)
            if !primary.isEmpty {
                let lines = LyricsLineMerger.merge(
                    primary: primary,
                    translationRaw: response.ytlrc?.lyric ?? response.tlyric?.lyric,
                    transliterationRaw: response.yromalrc?.lyric ?? response.romalrc?.lyric
                )
                let timing: LyricsTiming = lines.contains { $0.words?.isEmpty == false }
                    ? .wordSynced : .synced
                return .document(LyricsDocument(source: .netease, timing: timing, lines: lines))
            }
        }

        guard let lrc = response.lrc?.lyric, !lrc.isEmpty else { return .notFound }
        let primary = LRCParser.parse(lrc)
        if primary.isEmpty {
            return .document(.plain(lrc, source: .netease))
        }
        let lines = LyricsLineMerger.merge(
            primary: primary,
            translationRaw: response.tlyric?.lyric,
            transliterationRaw: response.romalrc?.lyric
        )
        return .document(LyricsDocument(source: .netease, timing: .synced, lines: lines))
    }

    private func get(path: String, queryItems: [URLQueryItem]) async throws -> Data {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = queryItems
        guard let url = components.url else { throw ProviderError.invalidResponse }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ProviderError.invalidResponse }
        guard http.statusCode == 200 else { throw ProviderError.badStatus(http.statusCode) }
        return data
    }
}

private struct NeteaseSearchResponse: Decodable {
    struct Result: Decodable {
        let songs: [Song]
    }

    struct Artist: Decodable {
        let name: String
    }

    struct Album: Decodable {
        let name: String
    }

    struct Song: Decodable {
        let id: Int64
        let name: String
        let durationMs: Int?
        let artistNames: [String]
        let albumName: String?

        enum CodingKeys: String, CodingKey {
            case id, name, duration, dt, artists, ar, album, al
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try values.decode(Int64.self, forKey: .id)
            name = try values.decode(String.self, forKey: .name)
            durationMs = try values.decodeIfPresent(Int.self, forKey: .duration)
                ?? values.decodeIfPresent(Int.self, forKey: .dt)
            let artists = try values.decodeIfPresent([Artist].self, forKey: .artists)
                ?? values.decodeIfPresent([Artist].self, forKey: .ar)
                ?? []
            artistNames = artists.map(\.name)
            albumName = try values.decodeIfPresent(Album.self, forKey: .album)?.name
                ?? values.decodeIfPresent(Album.self, forKey: .al)?.name
        }
    }

    let result: Result?
}

private struct NeteaseLyricsResponse: Decodable {
    struct Block: Decodable {
        let lyric: String?
    }

    let nolyric: Bool?
    let uncollected: Bool?
    let lrc: Block?
    let tlyric: Block?
    let romalrc: Block?
    let yrc: Block?
    let ytlrc: Block?
    let yromalrc: Block?
}
