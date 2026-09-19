import Testing
import Foundation
@testable import DriveVerse

/// Serialization umbrella: every suite that touches StubURLProtocol's static
/// state must be nested in here (via extension), because `.serialized` only
/// orders tests within one suite tree — sibling suites run in parallel.
@Suite(.serialized) enum HTTPStubbedTests {}

/// Records every request and answers from a per-run handler.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (status: Int, body: Data))?
    nonisolated(unsafe) static var headers: [String: String]?
    nonisolated(unsafe) static var requests: [URLRequest] = []

    static func reset(headers: [String: String]? = nil, handler: @escaping (URLRequest) -> (status: Int, body: Data)) {
        self.handler = handler
        self.headers = headers
        self.requests = []
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        let (status, body) = Self.handler?(request) ?? (500, Data())
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil, headerFields: Self.headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func json(_ s: String) -> Data { Data(s.utf8) }

private let syncedHit = json("""
{"id": 1, "trackName": "song", "artistName": "artist", "albumName": "album",
 "duration": 200.0, "instrumental": false,
 "plainLyrics": "Hello world", "syncedLyrics": "[00:01.00]Hello world"}
""")

private func queryValue(_ request: URLRequest, _ name: String) -> String? {
    URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
        .queryItems?.first { $0.name == name }?.value
}

extension HTTPStubbedTests {
@Suite struct LRCLIBClientTests {
    private var client: LRCLIBClient { LRCLIBClient(session: StubURLProtocol.makeSession()) }

    @Test func directHitReturnsSynced() async throws {
        StubURLProtocol.reset { _ in (200, syncedHit) }

        let result = try await client.fetchLyrics(
            title: "Song (Remastered 2011)", artist: "Artist feat. Other",
            album: "Album (Deluxe)", durationMs: 200_000
        )
        #expect(result == .synced("[00:01.00]Hello world"))
        #expect(StubURLProtocol.requests.count == 1)

        let request = try #require(StubURLProtocol.requests.first)
        #expect(request.url?.path == "/api/get")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "DriveVerse/1.0 personal project")
        // Queries are sent normalized, with duration in seconds.
        #expect(queryValue(request, "track_name") == "song")
        #expect(queryValue(request, "artist_name") == "artist")
        #expect(queryValue(request, "album_name") == "album")
        #expect(queryValue(request, "duration") == "200")
    }

    @Test func fallbackChainGetGetSearch() async throws {
        StubURLProtocol.reset { request in
            let path = request.url!.path
            if path == "/api/get" { return (404, Data()) }
            // /api/search: one wrong-duration candidate, one match without
            // synced lyrics, one match with — the last should win.
            return (200, json("""
            [
              {"id": 1, "trackName": "song", "duration": 300.0, "syncedLyrics": "[00:01.00]Wrong"},
              {"id": 2, "trackName": "song", "duration": 201.0, "plainLyrics": "Plain only"},
              {"id": 3, "trackName": "song", "duration": 199.0, "syncedLyrics": "[00:01.00]Right"}
            ]
            """))
        }

        let result = try await client.fetchLyrics(
            title: "Song", artist: "Artist", album: "Album", durationMs: 200_000
        )
        #expect(result == .synced("[00:01.00]Right"))

        let paths = StubURLProtocol.requests.map { $0.url!.path }
        #expect(paths == ["/api/get", "/api/get", "/api/search"])
        // First get carries the album, the retry drops it.
        #expect(queryValue(StubURLProtocol.requests[0], "album_name") == "album")
        #expect(queryValue(StubURLProtocol.requests[1], "album_name") == nil)
    }

    @Test func instrumentalTrack() async throws {
        StubURLProtocol.reset { _ in
            (200, json("""
            {"id": 9, "trackName": "song", "instrumental": true,
             "plainLyrics": null, "syncedLyrics": null}
            """))
        }
        let result = try await client.fetchLyrics(title: "Song", artist: "Artist", album: nil, durationMs: 100_000)
        #expect(result == .instrumental)
    }

    @Test func plainLyricsFallback() async throws {
        StubURLProtocol.reset { _ in
            (200, json("""
            {"id": 9, "trackName": "song", "instrumental": false,
             "plainLyrics": "Just words", "syncedLyrics": null}
            """))
        }
        let result = try await client.fetchLyrics(title: "Song", artist: "Artist", album: nil, durationMs: nil)
        #expect(result == .plain("Just words"))
    }

    @Test func nothingFoundAnywhere() async throws {
        StubURLProtocol.reset { request in
            request.url!.path == "/api/search" ? (200, json("[]")) : (404, Data())
        }
        let result = try await client.fetchLyrics(title: "Song", artist: "Artist", album: "Album", durationMs: 100_000)
        #expect(result == .notFound)
        #expect(StubURLProtocol.requests.count == 3)
    }

    @Test func noAlbumSkipsSecondGet() async throws {
        StubURLProtocol.reset { request in
            request.url!.path == "/api/search" ? (200, json("[]")) : (404, Data())
        }
        _ = try await client.fetchLyrics(title: "Song", artist: "Artist", album: nil, durationMs: 100_000)
        let paths = StubURLProtocol.requests.map { $0.url!.path }
        #expect(paths == ["/api/get", "/api/search"])
    }

    @Test func serverErrorThrows() async {
        StubURLProtocol.reset { _ in (500, Data()) }
        await #expect(throws: LRCLIBClient.ClientError.badStatus(500)) {
            _ = try await client.fetchLyrics(title: "Song", artist: "Artist", album: nil, durationMs: nil)
        }
    }

    // Lives in this suite (not its own) because it shares StubURLProtocol's
    // static state — suites run in parallel, .serialized only orders within one.
    @Test func secondLookupServedFromCache() async throws {
        StubURLProtocol.reset { request in
            if request.url?.path == "/api/search" {
                return (200, json("""
                [{"id": 1, "trackName": "song", "artistName": "artist", "albumName": "album",
                  "duration": 200.0, "instrumental": false,
                  "plainLyrics": "Hello world", "syncedLyrics": "[00:01.00]Hello world"}]
                """))
            }
            return (200, syncedHit)
        }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("driveverse-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let service = LyricsService(
            client: LRCLIBClient(session: StubURLProtocol.makeSession()),
            cache: LyricsCache(directory: dir)
        )
        let state = NowPlayingState(
            title: "Song", artist: "Artist", album: "Album",
            durationMs: 200_000, positionMs: 0,
            isPlaying: true, capturedAt: Date()
        )

        let first = try await service.lyrics(for: state)
        guard case .document(let document) = first else {
            Issue.record("expected a structured lyrics document")
            return
        }
        #expect(document.source == .lrclib)
        #expect(document.timing == .synced)
        #expect(document.lines.first?.original == "Hello world")
        #expect(StubURLProtocol.requests.count == 1)

        let second = try await service.lyrics(for: state)
        #expect(second == first)
        #expect(StubURLProtocol.requests.count == 1) // no extra network hit
    }
}

@Suite struct MultiProviderClientTests {
    @Test func kugouSearchReturnsMultipleTrackCandidates() async throws {
        StubURLProtocol.reset { request in
            guard request.url?.path == "/search" else { return (404, Data()) }
            return (200, json("""
            {"candidates":[
              {"id":"A","accesskey":"KA","song":"Song","singer":"Artist","duration":200000},
              {"id":"B","accesskey":"KB","song":"Song (Live)","singer":"Artist","duration":205000}
            ]}
            """))
        }
        let provider = KugouLyricsProvider(
            session: StubURLProtocol.makeSession(),
            searchBaseURL: URL(string: "https://stub.invalid")!,
            lyricsBaseURL: URL(string: "https://stub.invalid")!
        )
        let query = LyricsSearchQuery(
            title: "Song", artist: "Artist", album: "Album", durationMs: 200_000
        )
        let candidates = try await provider.search(for: query, limit: 3)
        #expect(candidates.map(\.identifier) == ["A", "B"])
        #expect(candidates.first?.album == nil)
        #expect(candidates.first?.durationMs == 200_000)
    }

    @Test func neteaseSearchAndYRCFetch() async throws {
        StubURLProtocol.reset { request in
            switch request.url?.path {
            case "/api/search/get/web":
                return (200, json("""
                {"result":{"songs":[{"id":123,"name":"Song","duration":200000,
                  "artists":[{"name":"Artist"}],"album":{"name":"Album"}}]}}
                """))
            case "/api/song/lyric/v1":
                return (200, json("""
                {"code":200,
                 "yrc":{"lyric":"[1000,1000](1000,400,0)你(1400,600,0)好"},
                 "ytlrc":{"lyric":"[00:01.00]Hello"},
                 "yromalrc":{"lyric":"[00:01.00]ni hao"}}
                """))
            default:
                return (404, Data())
            }
        }
        let provider = NeteaseLyricsProvider(
            session: StubURLProtocol.makeSession(),
            baseURL: URL(string: "https://stub.invalid")!
        )
        let query = LyricsSearchQuery(
            title: "Song", artist: "Artist", album: "Album", durationMs: 200_000
        )
        let candidates = try await provider.search(for: query, limit: 3)
        let candidate = try #require(candidates.first)
        let content = try await provider.lyrics(for: candidate)
        guard case .document(let document) = content else {
            Issue.record("expected document")
            return
        }
        #expect(document.source == .netease)
        #expect(document.timing == .wordSynced)
        #expect(document.lines.first?.translation == "Hello")
        #expect(document.lines.first?.transliteration == "ni hao")
    }

    @Test func kugouFetchDecryptsKRC() async throws {
        StubURLProtocol.reset { request in
            switch request.url?.path {
            case "/search":
                return (200, json("""{"candidates":[{"id":"10","accesskey":"key"}]}"""))
            case "/download":
                return (200, json("""
                {"content":"a3JjMTjb6kFqAkSXUCeAG8joSG9GfWcBEcRa91CH/e1ydSWeQkfR9VTT"}
                """))
            default:
                return (404, Data())
            }
        }
        let provider = KugouLyricsProvider(
            session: StubURLProtocol.makeSession(),
            searchBaseURL: URL(string: "https://stub.invalid")!,
            lyricsBaseURL: URL(string: "https://stub.invalid")!
        )
        let candidate = LyricsCandidate(
            identifier: "hash",
            source: .kugou,
            title: "Song",
            artists: ["Artist"],
            album: "Album",
            durationMs: 2_000,
            metadata: ["hash": "hash"]
        )
        let content = try await provider.lyrics(for: candidate)
        guard case .document(let document) = content else {
            Issue.record("expected document")
            return
        }
        #expect(document.source == .kugou)
        #expect(document.timing == .wordSynced)
        #expect(document.lines.first?.original == "你好")
    }
}
}
