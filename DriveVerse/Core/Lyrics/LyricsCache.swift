import Foundation
import CryptoKit

struct CachedLyrics: Codable, Equatable {
    let content: LyricsContent
    let storedAt: Date
}

private struct CachedCandidateChoices: Codable {
    let choices: [LyricsCandidateChoice]
    let selectedCandidateID: String?
    let storedAt: Date
}

private struct CachedManualSelection: Codable {
    let choice: LyricsCandidateChoice
    let storedAt: Date
}

/// Disk cache for structured lyric lookups, keyed by format version, provider,
/// and normalized track signature. Entries are never served past 30 days.
/// Negative results (`notFound`) are retried after a day.
final class LyricsCache {
    static let maxAge: TimeInterval = 30 * 24 * 3600
    static let notFoundMaxAge: TimeInterval = 24 * 3600
    /// Increment when automatic ranking semantics change so an old winner
    /// cannot bypass the corrected matcher for another 30 days.
    static let selectionAlgorithmVersion = 2

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
        "lyrics-v\(LyricsDocument.currentFormatVersion)|selection-v\(selectionAlgorithmVersion)|\(secondaryRequirement.rawValue)|\(trackSignature)"
    }

    static func candidatesKey(selectionKey: String) -> String {
        "candidates|\(selectionKey)"
    }

    static func manualKey(
        trackSignature: String,
        secondaryRequirement: LyricsSecondaryRequirement
    ) -> String {
        "lyrics-v\(LyricsDocument.currentFormatVersion)|manual|\(secondaryRequirement.rawValue)|\(trackSignature)"
    }

    /// Key written by the first manual-selection implementation. Keep it only
    /// for one-way migration when the automatic selection algorithm changes.
    static func legacyManualKey(
        trackSignature: String,
        secondaryRequirement: LyricsSecondaryRequirement
    ) -> String {
        let oldSelection = "lyrics-v\(LyricsDocument.currentFormatVersion)|selection|\(secondaryRequirement.rawValue)|\(trackSignature)"
        return "manual|\(oldSelection)"
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

    func candidateChoices(signature: String) -> ([LyricsCandidateChoice], String?)? {
        guard let cached: CachedCandidateChoices = decode(signature: signature),
              isFresh(cached.storedAt) else { return nil }
        return (cached.choices, cached.selectedCandidateID)
    }

    func storeCandidateChoices(
        _ choices: [LyricsCandidateChoice],
        selectedCandidateID: String?,
        signature: String
    ) {
        encode(
            CachedCandidateChoices(
                choices: choices,
                selectedCandidateID: selectedCandidateID,
                storedAt: now()
            ),
            signature: signature
        )
    }

    func manualSelection(signature: String) -> LyricsCandidateChoice? {
        guard let cached: CachedManualSelection = decode(signature: signature),
              isFresh(cached.storedAt) else { return nil }
        return cached.choice
    }

    func storeManualSelection(_ choice: LyricsCandidateChoice, signature: String) {
        encode(CachedManualSelection(choice: choice, storedAt: now()), signature: signature)
    }

    func remove(signature: String) {
        try? fileManager.removeItem(at: fileURL(for: signature))
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

    private func decode<Value: Decodable>(signature: String) -> Value? {
        guard let data = try? Data(contentsOf: fileURL(for: signature)) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    private func encode<Value: Encodable>(_ value: Value, signature: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: fileURL(for: signature), options: .atomic)
    }

    private func isFresh(_ storedAt: Date) -> Bool {
        let age = now().timeIntervalSince(storedAt)
        guard age >= 0, age < Self.maxAge else { return false }
        return true
    }
}
