import Foundation
import CryptoKit

struct CachedLyrics: Codable, Equatable {
    let content: LyricsContent
    let storedAt: Date
}

/// Disk cache for structured lyric lookups, keyed by format version, provider,
/// and normalized track signature. Entries are never served past 30 days.
/// Negative results (`notFound`) are retried after a day.
final class LyricsCache {
    static let maxAge: TimeInterval = 30 * 24 * 3600
    static let notFoundMaxAge: TimeInterval = 24 * 3600

    private let directory: URL
    private let fileManager = FileManager.default
    var now: () -> Date

    init(directory: URL? = nil, now: @escaping () -> Date = Date.init) {
        self.directory = directory ?? FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LyricsCache", isDirectory: true)
        self.now = now
        try? fileManager.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    static func key(source: LyricsSource, trackSignature: String) -> String {
        "lyrics-v\(LyricsDocument.currentFormatVersion)|\(source.rawValue)|\(trackSignature)"
    }

    static func selectionKey(
        trackSignature: String,
        secondaryRequirement: LyricsSecondaryRequirement
    ) -> String {
        "lyrics-v\(LyricsDocument.currentFormatVersion)|selection|\(secondaryRequirement.rawValue)|\(trackSignature)"
    }

    func lookup(signature: String) -> LyricsContent? {
        let url = fileURL(for: signature)
        guard let data = try? Data(contentsOf: url),
              let cached = try? JSONDecoder().decode(CachedLyrics.self, from: data) else {
            return nil
        }
        let age = now().timeIntervalSince(cached.storedAt)
        let limit = cached.content.isNotFound ? Self.notFoundMaxAge : Self.maxAge
        guard age >= 0, age < limit else {
            try? fileManager.removeItem(at: url)
            return nil
        }
        return cached.content
    }

    func store(_ content: LyricsContent, signature: String) {
        let cached = CachedLyrics(content: content, storedAt: now())
        guard let data = try? JSONEncoder().encode(cached) else { return }
        try? data.write(to: fileURL(for: signature), options: .atomic)
    }

    func clear() {
        try? fileManager.removeItem(at: directory)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func fileURL(for signature: String) -> URL {
        let digest = SHA256.hash(data: Data(signature.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name + ".json")
    }
}
