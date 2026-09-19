#if os(iOS)
import AppIntents

/// Interactive Live Activity controls run in the app process because these
/// intents modify audio playback. They control the same system Apple Music
/// player that DriveVerse observes, including user-imported library tracks.
struct TogglePlaybackIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play or Pause"
    static var isDiscoverable: Bool { false }

    func perform() async throws -> some IntentResult {
#if !WIDGET_EXTENSION
        let model = await AppModel.shared
        await model.togglePlayback()
#endif
        return .result()
    }
}

struct PreviousTrackIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Previous Track"
    static var isDiscoverable: Bool { false }

    func perform() async throws -> some IntentResult {
#if !WIDGET_EXTENSION
        let model = await AppModel.shared
        await model.skipToPreviousItem()
#endif
        return .result()
    }
}

struct NextTrackIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Next Track"
    static var isDiscoverable: Bool { false }

    func perform() async throws -> some IntentResult {
#if !WIDGET_EXTENSION
        let model = await AppModel.shared
        await model.skipToNextItem()
#endif
        return .result()
    }
}

struct SeekPlaybackIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Seek Playback"
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Offset in seconds")
    var offsetSeconds: Double

    init() {
        offsetSeconds = 0
    }

    init(offsetSeconds: Double) {
        self.offsetSeconds = offsetSeconds
    }

    func perform() async throws -> some IntentResult {
#if !WIDGET_EXTENSION
        let model = await AppModel.shared
        await model.seek(bySeconds: offsetSeconds)
#endif
        return .result()
    }
}
#endif
